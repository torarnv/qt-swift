// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import PackagePlugin

// Emit one QtFooBuildTest.swift per Qt module that is both installed on this
// machine and known by the package, each holding a single `import QtFoo`.

@main
struct ModuleBuildTests: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let qt = QtPaths(context: context) else {
            Diagnostics.error("Unable to locate Qt system libraries\n")
            return []
        }

        let installed = Set(
            ((try? FileManager.default.contentsOfDirectory(
                atPath: qt.modulesDir)) ?? [])
                .filter { $0.hasSuffix(".json") }
                .map { "Qt" + $0.dropLast(".json".count) })

        let known = Set(context.package.products.map { $0.name })
        let modules = installed.intersection(known).sorted()

        return modules.map { module in
            let output = context.pluginWorkDirectoryURL.appending(path: "\(module)BuildTest.swift")
            return .buildCommand(
                displayName: "Generate \(module) build test",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo 'import \(module)' > \"$0\"", output.path],
                inputFiles: [],
                outputFiles: [output])
        }
    }
}
