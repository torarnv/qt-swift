// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import PackagePlugin

// Resolves the location of the Qt install, and related directories, via the
// flags passed through the "Locate Qt" target.
//
// Plugin target cannot depend on library targets, and two targets cannot claim
// the same path as a source, so every plugin compiles its own copy through a
// symlinked copy of this file.

struct QtPaths {
    let prefix: String
    let modulesDir: String
    let includeDir: String
    let libDir: String

    init?(context: PluginContext) {
        let platformFlags = context.package.targets
            .compactMap { $0 as? SystemLibraryTarget }
            .first { $0.name == "Locate Qt" }!

        guard
            let mkspecFlag = platformFlags.compilerFlags.first(where: {
                $0.hasPrefix("-I") && $0.contains("/mkspecs/")
            })
        else { return nil }

        self.init(
            installPrefix: mkspecFlag.dropFirst("-I".count)
                .components(separatedBy: "/mkspecs/").first!)
    }

    init(installPrefix: String) {
        var prefix = installPrefix
        let defaultModulesDir = "\(prefix)/modules"

        if prefix.hasSuffix("/share/qt") {
            // Homebrew keeps mkspecs and the module metadata under <prefix>/share/qt
            // while the headers and libraries stay at <prefix>, so step back out of
            // share/qt before resolving the include and lib defaults.
            prefix = String(prefix.dropLast("/share/qt".count))
        }
        self.prefix = prefix

        let defaultIncludeDir = "\(prefix)/include"
        let defaultLibDir = "\(prefix)/lib"

        // Respect Linux multiarch distros, that keep Qt's tree under an arch-qualified
        // directory instead of a flat prefix, or cases of non-default Qt install layout.
        if let qtConf = QtConf(atPath: "\(prefix)/qt6.conf") {
            self.modulesDir =
                qtConf.resolve("HostData")
                .map { "\($0)/modules" } ?? defaultModulesDir
            self.includeDir = qtConf.resolve("Headers") ?? defaultIncludeDir
            self.libDir = qtConf.resolve("Libraries") ?? defaultLibDir
        } else {
            self.modulesDir = defaultModulesDir
            self.includeDir = defaultIncludeDir
            self.libDir = defaultLibDir
        }
    }

    private struct QtConf {
        private let entries: [String: String]
        private let prefix: String
        private let hostPrefix: String

        init?(atPath path: String) {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }
            var section = ""
            var parsed: [String: String] = [:]
            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix(";") { continue }
                if line.hasPrefix("["), line.hasSuffix("]") {
                    section = String(line.dropFirst().dropLast())
                    continue
                }
                guard section == "Paths", let eq = line.firstIndex(of: "=") else { continue }
                let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                parsed[key] = value
            }
            entries = parsed

            let confDir = (path as NSString).deletingLastPathComponent
            func absolute(_ value: String?) -> String? {
                guard let value = value else { return nil }
                return value.hasPrefix("/") ? value : "\(confDir)/\(value)"
            }
            prefix = absolute(parsed["Prefix"]) ?? confDir
            hostPrefix = absolute(parsed["HostPrefix"]) ?? prefix
        }

        func resolve(_ key: String) -> String? {
            guard let value = entries[key] else { return nil }
            guard !value.hasPrefix("/") else { return value }
            return "\(key.hasPrefix("Host") ? hostPrefix : prefix)/\(value)"
        }
    }
}
