// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

// We do not depend on any systemLibraries for actual Qt modules,
// as that will bring in warnings from SwiftPM about prohibited
// flag(s) for -DQT_FOO_LIB, plus we don't ship .pc files for
// private modules yet. Instead we generate a synthetic include
// hierarchy in the build tool plugin's output dir, that covers
// all forms of includes used inside Qt or in user code, for both
// public and private headers.
func createHeaderSymlinks(for module: QtModule, in outputDir: String) {
    guard let headers = module.headers else { return }

    // Plan first, so we can resolve conflicts, and then do the creation in parallel
    var created = Set<String>()
    let links = headerLinks(for: headers, targeting: outputDir)
        .filter { created.insert($0.path).inserted }

    let directories = Set(links.map { $0.path.deletingLastPathComponent })
    for directory in directories {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    links.parallelForEach {
        try? FileManager.default.createSymbolicLink(atPath: $0.path, withDestinationPath: $0.target)
    }
}

// One module's installed headers
struct ModuleHeaders: Sendable {
    let qtModule: String

    let publicDir: String
    let publicHeaders: [String]
    let publicSubdirectories: [String]

    let privateDir: String?
    let privateHeaders: [String]

    init(qtModule: String, publicDir: String) {
        self.qtModule = qtModule
        self.publicDir = publicDir

        let (files, subdirectories, versionDir) = Self.collectHeaders(root: publicDir)
        publicHeaders = files

        publicSubdirectories = (subdirectories + (versionDir.map { [$0] } ?? []))
            .map { $0.lastPathComponent }

        if let versionDir = versionDir, FileManager.isDirectory(atPath: "\(versionDir)/\(qtModule)") {
            privateDir = "\(versionDir)/\(qtModule)"
        } else {
            privateDir = nil
        }

        privateHeaders = privateDir.map { Self.collectHeaders(root: $0).files.sorted() } ?? []
    }

    private static func collectHeaders(root: String) -> (files: [String], dirs: [String], versionDir: String?) {
        var files: [String] = []
        var dirs: [String] = []
        var versionDir: String?
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        for entry in entries.sorted() {
            let full = "\(root)/\(entry)"
            guard FileManager.isDirectory(atPath: full) else {
                files.append(full)
                continue
            }
            if isVersionDir(entry) {
                versionDir = full
            } else {
                dirs.append(full)
                let nested = collectHeaders(root: full)
                files.append(contentsOf: nested.files)
                if let nestedVersion = nested.versionDir { versionDir = nestedVersion }
            }
        }
        return (files, dirs, versionDir)
    }

    private static func isVersionDir(_ name: String) -> Bool {
        return name.contains(where: { $0.isNumber })
            && name.allSatisfy { $0.isNumber || $0 == "." }
    }
}

private func headerLinks(for headers: ModuleHeaders, targeting includeDir: String) -> [(path: String, target: String)] {
    let moduleSpecificIncludeDir = "\(includeDir)/\(headers.qtModule)"
    var links: [(path: String, target: String)] = []

    func link(_ header: String, from installed: String, into dirs: [String]) {
        for dir in dirs {
            links.append((path: "\(dir)/\(header)", target: installed))
        }
    }

    // Any header living direcly in the module's public include directory
    for path in headers.publicHeaders where path.deletingLastPathComponent == headers.publicDir {
        // Cover both #include <QtCore/qfoo.h>, and #include <qfoo.h>
        link(path.lastPathComponent, from: path, into: [moduleSpecificIncludeDir, includeDir])
    }

    // Any directory living directly in the module's public include directory
    for subdirectory in headers.publicSubdirectories {
        // Covers e.g. #include <QtProtobufWellKnownTypes/google/protobuf/any.qpb.h>
        link(subdirectory, from: "\(headers.publicDir)/\(subdirectory)", into: [moduleSpecificIncludeDir])
    }

    if let privateDir = headers.privateDir {
        for path in headers.privateHeaders {
            // Covers #include <QtGui/rhi/qbar_p.h>, and <rhi/qbar_p.h>
            link(String(path.dropFirst(privateDir.count + 1)), from: path, into: [moduleSpecificIncludeDir, includeDir])
            // Covers #include <qbar_p.h>
            link(path.lastPathComponent, from: path, into: [includeDir])
        }
    }

    return links
}

// MARK: - Promoted headers

// Swift's C++ interop importer eagerly tries to complete every QList<T>,
// even for incomplete (forward-declared) types, causing build issues.
// To work around it we promote a select set of headers (currently only
// one) from private to public, so Swift sees a complete definition.
// See https://github.com/swiftlang/swift/issues/92350 for more info.
func copyPromotedHeaders(for module: QtModule, to outputDir: String) {
    for header in module.promotedHeaders {
        let destination = "\(outputDir)/\(promotedHeaderPath(for: header, in: module))"
        copyPromotedHeader(header, to: destination)
    }
}

func promotedHeaderPath(for header: String, in module: QtModule) -> String {
    let name = header.lastPathComponent
    return "\(module.name)/\(name.dropLast("_p.h".count)).h"
}

let promotedPrivateHeaders: Set<String> = [
    "qwidgetitemdata_p.h"  // Needed by QTreeWidgetItem/QTableWidgetItem
]

private func copyPromotedHeader(_ source: String, to destination: String) {
    // Strip the header of any private includes. It must build on its own.
    let kept = try! String(contentsOfFile: source, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("#include") && trimmed.contains("_p.h"))
        }
    try! FileManager.default.createDirectory(
        atPath: destination.deletingLastPathComponent,
        withIntermediateDirectories: true)
    try! kept.joined(separator: "\n")
        .write(toFile: destination, atomically: true, encoding: .utf8)
}
