// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

let paths = Paths(from: CommandLine.arguments)
let moduleName = CommandLine.arguments.last!

// We own every file in the outputDir, so start fresh every run.
// Discarding does a quick rename, and hands the deletion to a
// background thread, so that we can start the work below ASAP.
let discardedOutputDir = FileManager.discardDirectory(at: paths.outputDir)
defer { discardedOutputDir.wait() }
try! FileManager.default.createDirectory(
    atPath: paths.outputDir,
    withIntermediateDirectories: true)

// A header is required for SwiftPM to add our output dir to
// the include paths, and a source is required for the final
// link of the module to succeed.
let dummyOutput = "\(paths.outputDir)/\(moduleName)"
FileManager.createEmptyFile(atPath: "\(dummyOutput).h")
FileManager.createEmptyFile(atPath: "\(dummyOutput).cpp")

let module = QtModule(moduleName, from: paths.qt, and: paths.packageRoot)

copyPromotedHeaders(for: module, to: paths.outputDir)
createHeaderSymlinks(for: module, in: paths.outputDir)

writeModuleMap(for: module, to: paths.outputDir)
writeApiNotes(for: module, to: paths.outputDir)

if let linkerFlagsFile = paths.linkerFlagsFile {
    writeLinkerFlags(for: paths.qt, to: linkerFlagsFile)
}
