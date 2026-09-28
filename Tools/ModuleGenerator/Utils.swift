// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

struct QtPaths: Sendable {
    let prefix: String
    let includeDir: String
    let libDir: String
}

struct Paths: Sendable {
    let qt: QtPaths
    let packageRoot: String
    let outputDir: String
    let linkerFlagsFile: String?

    init(from commandLine: [String]) {
        guard commandLine.count >= 7 else {
            let usage =
                "usage: ModuleGenerator"
                + " <qtprefix> <libdir> <includedir>"
                + " <packageroot> <outdir> [linkerflagsfile] <module>\n"
            FileHandle.standardError.write(Data(usage.utf8))
            exit(1)
        }
        qt = QtPaths(
            prefix: commandLine[1],
            includeDir: commandLine[3],
            libDir: commandLine[2])
        packageRoot = commandLine[4]
        outputDir = commandLine[5]
        linkerFlagsFile = commandLine.count > 7 ? commandLine[6] : nil
    }
}

struct QtModule: Sendable {
    let name: String
    let libraryName: String
    let dependencies: [String]

    let hasFramework: Bool
    let hasLibrary: Bool

    let headers: ModuleHeaders?

    let overlayDir: String

    // The overlay's own C++ in Sources/<Module>,
    // split by Qt's <name>_p.h convention.
    let overlayPublicHeaders: [String]
    let overlayPrivateHeaders: [String]

    let promotedHeaders: [String]

    init(_ moduleName: String, from qt: QtPaths, and packageRoot: String) {
        name = moduleName
        let overlayDir = "\(packageRoot)/Sources/\(moduleName)"
        self.overlayDir = overlayDir

        let libraryName = "Qt6" + moduleName.dropFirst("Qt".count)
        self.libraryName = libraryName

        dependencies = QtModule.dependencies(for: libraryName, from: qt)

        let frameworkPath = "\(qt.libDir)/\(moduleName).framework"
        hasFramework = FileManager.isDirectory(atPath: frameworkPath)
        hasLibrary = ["dylib", "a", "so"].contains {
            FileManager.isFile(atPath: "\(qt.libDir)/lib\(libraryName).\($0)")
        }

        let publicDir = hasFramework ? "\(frameworkPath)/Headers" : "\(qt.includeDir)/\(moduleName)"
        headers =
            FileManager.isDirectory(atPath: publicDir) ? ModuleHeaders(qtModule: moduleName, publicDir: publicDir) : nil

        let overlayHeaders =
            (FileManager.default.enumerator(atPath: overlayDir)?
            .compactMap { $0 as? String } ?? [])
            .filter { $0.hasSuffix(".h") }
            .sorted()
            .map { "\(overlayDir)/\($0)" }
        overlayPublicHeaders = overlayHeaders.filter { !$0.hasSuffix("_p.h") }
        overlayPrivateHeaders = overlayHeaders.filter { $0.hasSuffix("_p.h") }

        promotedHeaders = (headers?.privateHeaders ?? [])
            .filter { promotedPrivateHeaders.contains($0.lastPathComponent) }
    }

    // Resolve dependencies for a module by reading them off the
    // corresponding pkg-config file, since Qt's module .json files
    // don't encode any dependency information.
    private static func dependencies(for libraryName: String, from qt: QtPaths) -> [String] {
        let path = "\(qt.libDir)/pkgconfig/\(libraryName).pc"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
            let line = contents.split(separator: "\n")
                .first(where: { $0.hasPrefix("Requires:") })
        else {
            return []
        }

        let names = line.dropFirst("Requires:".count)
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .filter { $0.hasPrefix("Qt6") }
            .map { name -> String in
                let base = name.hasSuffix("Private") ? name.dropLast("Private".count) : name
                return "Qt" + base.dropFirst("Qt6".count)
            }

        let moduleName = "Qt" + libraryName.dropFirst("Qt6".count)
        return Set(names).subtracting([moduleName]).sorted()
    }
}

extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

extension FileManager {
    static func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    static func createEmptyFile(atPath path: String) {
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            fatalError("Failed to create \(path)")
        }
    }

    // Move a directory out of the way and delete it in the background, so
    // a caller wanting the path empty can start refilling it right away.
    static func discardDirectory(at path: String) -> DiscardedDirectory {
        let removal = DispatchGroup()

        let discarded = "\(path).discarded-\(getpid())"
        if rename(path, discarded) == 0 {
            DispatchQueue.global().async(group: removal) {
                FileManager.removeTree(atPath: discarded)
            }
        } else {
            FileManager.removeTree(atPath: path)
        }

        return DiscardedDirectory(removal: removal)
    }

    private static func removeTree(atPath root: String) {
        var files: [String] = []
        var directories: [String] = []

        func walk(_ directory: String) {
            directories.append(directory)
            guard let handle = opendir(directory) else { return }
            defer { closedir(handle) }
            while let entry = readdir(handle) {
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
                guard name != "." && name != ".." else { continue }
                let path = "\(directory)/\(name)"
                if entry.pointee.d_type == UInt8(DT_DIR) {
                    walk(path)
                } else {
                    files.append(path)
                }
            }
        }

        walk(root)

        files.parallelForEach { _ = unlink($0) }

        for directory in directories.reversed() {
            _ = rmdir(directory)
        }
    }

    struct DiscardedDirectory {
        fileprivate let removal: DispatchGroup

        func wait() {
            removal.wait()
        }
    }
}

extension Array where Element: Sendable {
    func parallelForEach(_ body: @Sendable (Element) -> Void) {
        guard !isEmpty else { return }
        DispatchQueue.concurrentPerform(iterations: count) { body(self[$0]) }
    }
}
