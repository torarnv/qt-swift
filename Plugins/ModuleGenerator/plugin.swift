// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import PackagePlugin

@main
struct ModuleGenerator: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name.hasSuffix("Module") else {
            Diagnostics.error("Module generator target '\(target.name)' must be named QtFooModule\n")
            return []
        }
        let module = String(target.name.dropLast("Module".count))

        guard let qt = QtPaths(context: context) else {
            if module == "QtCore" {
                Diagnostics.error("Unable to locate Qt system libraries\n")
                #if canImport(XcodeProjectPlugin)
                    print(
                        """
                        Please install Qt, and point your build to it by quitting Xcode and running

                            open --env PKG_CONFIG_PATH=<…> -a Xcode

                        if Qt is installed outside of the system pkg-config location.
                        """)
                #else
                    Diagnostics.warning(
                        """
                        Please install Qt, and point your build to it via

                            swift build --pkg-config-path <…>

                        if Qt is installed outside of the system pkg-config location.
                        """)
                #endif
            }
            return []
        }

        // Run module generator, which generates a module map and API notes
        // for the target's Qt module, and symlinks the Qt headers into a
        // synthetic structure in our output directory.

        let moduleGeneratorTool = try context.tool(named: "ModuleGenerator")
        let outputDir = context.pluginWorkDirectoryURL.appending(path: "include")

        var arguments = [
            qt.prefix,
            qt.libDir,
            qt.includeDir,
            context.package.directoryURL.path,
            outputDir.path
        ]
        var outputFiles = [
            outputDir.appending(path: "module.modulemap"),
            // We need to 'officially' produce a header to make SwiftPM add
            // our include directory to the header search paths, which we
            // rely on for our synthesized Qt header structure.
            outputDir.appending(path: "\(module).h"),
            // The target has no sources of its own, but the
            // link step still expects an object file from it.
            outputDir.appending(path: "\(module).cpp")
        ]

        // Now that we know the Qt location we can write a response file
        // that feeds into the consuming package's link line, reflecting
        // both the link time library and framework paths, as well as the
        // runtime RPATH, so users don't need to set additional environment
        // variables to run binaries built against Qt libraries with @rpath
        // install-names. FIXME: Ideally the response file would live in
        // the consuming package's build dir, but we don't know that at
        // the time of building the main package manifest, and we can't
        // rely on encoding a relative `.build/` path in the manifest,
        // as that would break for anyone passing a custom --scratch-path,
        // including Xcode. But since we declare the response file as
        // an output, we won't pick up a stale respone file from another
        // Qt build, unless they happen in parallel and trample eachother.
        // The .def extension makes SwiftPM treat the file as a header,
        // as any extension it doesn't know turns the file into a resource,
        // with a resource bundle target to go with it, which we don't want.
        if module == "QtCore" {
            let responseFile = FileManager.default.temporaryDirectory
                .appending(path: "qt-linker-flags.def")
            arguments.append(responseFile.path)
            outputFiles.append(responseFile)
        }
        arguments.append(module)

        return [
            .buildCommand(
                displayName: "Generate module map, API notes, and header structure for \(module)",
                executable: moduleGeneratorTool.url,
                arguments: arguments,
                inputFiles: overlayInputs(context.package.directoryURL),
                outputFiles: outputFiles
            )
        ]
    }

    // The generator reads the overlays for API notes to copy and headers to list
    // in the module map, so both decide whether its output is stale.
    func overlayInputs(_ packageDir: URL) -> [URL] {
        let sources = packageDir.appending(path: "Sources")
        let files =
            FileManager.default.enumerator(
                at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return
            files
            .filter { ["apinotes", "h"].contains($0.pathExtension) }
            .sorted { $0.path < $1.path }
    }
}
