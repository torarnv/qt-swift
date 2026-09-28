// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import PackagePlugin

// Emit the set of installed Qt 6 modules, their inter-module dependencies, and
// each module's source repository, as a JSON array written to .qt-modules.json
// in the package source directory.

@main
struct UpdateQtModules: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        guard pkgConfigAvailable() else {
            throw StringError(
                """
                Could not find pkg-config in PATH. Please install pkg-config and \
                add its location to your PATH.
                """)
        }

        let mkspecsDir = (try? pkgConfig("--variable=mkspecsdir", "Qt6Platform")) ?? ""
        guard !mkspecsDir.isEmpty else {
            throw StringError(
                """
                Could not find Qt via pkg-config. Please install Qt and point \
                PKG_CONFIG_PATH to it.
                """)
        }
        let modulesDir = URL(fileURLWithPath: mkspecsDir)
            .deletingLastPathComponent()
            .appendingPathComponent("modules")

        let version = try pkgConfig("--modversion", "Qt6Platform")
        let packages = try pkgConfig("--list-package-names")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("Qt6") }
            .sorted()

        // A module built against a different Qt than Qt6Platform means a mixed
        // installation. The emitted set would be inconsistent, so refuse it.
        let conflicts = try pkgConfig(["--modversion", "--verbose"] + packages)
            .split(whereSeparator: \.isNewline)
            .filter { line in
                let parts = line.components(separatedBy: ": ")
                return parts.count == 2 && parts[1] != version
            }
        guard conflicts.isEmpty else {
            throw StringError(
                """
                Conflicting package versions found (not matching \(version)):
                \(conflicts.joined(separator: "\n"))
                Consider limiting the search via PKG_CONFIG_LIBDIR.
                """)
        }

        var results = [Result<QtModule?, Error>?](repeating: nil, count: packages.count)
        results.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let slots = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: packages.count) { index in
                slots[index] = Result { try emitModule(packages[index], modulesDir: modulesDir) }
            }
        }

        var modules: [QtModule] = []
        var seen = Set<String>()
        for result in results.compactMap({ $0 }) {
            guard let module = try result.get() else { continue }
            if seen.insert(module.name).inserted {
                modules.append(module)
            }
        }
        modules.sort { $0.name < $1.name }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(modules)

        let output = context.package.directoryURL.appendingPathComponent(".qt-modules.json")
        try (data + Data("\n".utf8)).write(to: output, options: .atomic)
        print("Wrote \(modules.count) modules for Qt \(version) to \(output.path)")
    }

    private func emitModule(_ package: String, modulesDir: URL) throws -> QtModule? {
        let module = String(package.dropFirst("Qt6".count))
        let moduleFile = modulesDir.appendingPathComponent("\(module).json")
        guard let data = try? Data(contentsOf: moduleFile),
            let info = try? JSONDecoder().decode(ModuleFile.self, from: data),
            let repo = info.repository, !repo.isEmpty
        else {
            return nil
        }

        let requires = try pkgConfig("--print-requires", package)
            .split(whereSeparator: \.isNewline)
            .compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) }
            .map { $0.hasPrefix("Qt6") ? "Qt" + $0.dropFirst("Qt6".count) : $0 }

        return QtModule(name: "Qt\(module)", requires: requires, repo: repo)
    }
}

struct QtModule: Encodable {
    let name: String
    let requires: [String]
    let repo: String
}

private struct ModuleFile: Decodable {
    let repository: String?
}

private struct StringError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func pkgConfigAvailable() -> Bool {
    return (try? pkgConfig("--version")) != nil
}

private func pkgConfig(_ arguments: String...) throws -> String {
    return try pkgConfig(arguments)
}

private func pkgConfig(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config"] + arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    try process.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw StringError("pkg-config \(arguments.joined(separator: " ")) failed")
    }
    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
