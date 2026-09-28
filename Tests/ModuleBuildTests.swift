// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import Testing

private let qtModules: [QtModule] = discoverQtModules()
private let publicQtModules: [QtModule] = qtModules.filter { !$0.isPrivate }
private let privateQtModules: [QtModule] = qtModules.filter(\.isPrivate)

// Swift scans every imported module for operator overloads when it resolves an
// infix operator, so a single < pushes the C++ interop importer through all the
// Qt modules we import in this test. An incomplete C++ type makes that scan fail.
// See https://github.com/swiftlang/swift/issues/92350 for more details.
@Test func allImportedTypesAreComplete() {
    let names = ["b", "a", "c"]
    #expect(names.sorted { $0 < $1 } == ["a", "b", "c"])
}

// Reading .pcm files via clang -module-file-info only works
// if the swift that produced them matches clang exactly.
private let requiresMatchedClang: ConditionTrait = .enabled(
    if: clangCanReadSwiftEmittedModule(), "clang and swift versions must match")

@Test(requiresMatchedClang)
func didBuildClangModules() throws {
    #expect(!qtModules.isEmpty, "No Qt clang module .pcm files found under \(buildDir().path)")
}

// QtFoo shouldn't absob any headers from QtBar
@Test(requiresMatchedClang, arguments: qtModules)
func moduleDoesNotAbsorbForeignHeader(_ module: QtModule) throws {
    var foreign: Set<String> = []
    for header in module.headers {
        if isTextualHeader(header) { continue }
        // A nil owner is a system or toolchain header, outside Qt's tree
        guard let owner = owningQtModule(header) else { continue }
        if owner == module.family { continue }
        foreign.insert(header)
    }
    if !foreign.isEmpty {
        Issue.record(
            """
            \(module.name) absorbed headers from other Qt modules: \(foreign.sorted())
            """, severity: module.isPrivate ? .warning : .error)
    }
}

// QtFoo shouldn't absorb any _p.h private headers
@Test(requiresMatchedClang, arguments: publicQtModules)
func publicModuleDoesNotAbsorbPrivateHeader(_ module: QtModule) throws {
    var absorbed: Set<String> = []
    for header in module.headers {
        if isTextualHeader(header) { continue }
        if owningQtModule(header) == nil { continue }
        if !isPrivateHeader(header) { continue }
        absorbed.insert(header)
    }
    #expect(
        absorbed.isEmpty,
        "\(module.name) absorbed private Qt headers: \(absorbed.sorted())")
}

// QtFoo_Private shouldn't absorb any non-_p.h (public) headers
@Test(requiresMatchedClang, arguments: privateQtModules)
func privateModuleDoesNotAbsorbPublicHeader(_ module: QtModule) throws {
    var absorbed: Set<String> = []
    for header in module.headers {
        if isTextualHeader(header) { continue }
        if owningQtModule(header) != module.family { continue }
        if isPrivateHeader(header) { continue }
        absorbed.insert(header)
    }
    #expect(
        absorbed.isEmpty,
        "\(module.name) absorbed public \(module.family) headers: \(absorbed.sorted())")
}

// MARK: - Helpers

private func buildDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // tests
        .deletingLastPathComponent()  // package root
        .appendingPathComponent(".build")
}

private func clangCanReadSwiftEmittedModule() -> Bool {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("qtswift-clang-probe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let header = dir.appendingPathComponent("probe.h")
        try "int probe_answer(void);\n".write(to: header, atomically: true, encoding: .utf8)
        let map = dir.appendingPathComponent("module.modulemap")
        try """
        module Probe {
            header "probe.h"
            export *
        }
        """.write(to: map, atomically: true, encoding: .utf8)
        let pcm = dir.appendingPathComponent("probe.pcm")
        guard emitPCM(moduleMap: map, output: pcm) else { return false }
        let (name, _) = parseModuleFileInfo(moduleFileInfo(pcm))
        return name != nil
    } catch {
        return false
    }
}

private func emitPCM(moduleMap: URL, output: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swiftc", "-emit-pcm", "-module-name", "Probe",
        moduleMap.path, "-o", output.path
    ]
    let sink = Pipe()
    process.standardOutput = sink
    process.standardError = sink
    try? process.run()
    _ = try? sink.fileHandleForReading.readToEnd()
    process.waitUntilExit()
    return process.terminationStatus == 0
        && FileManager.default.fileExists(atPath: output.path)
}

private func moduleFileInfo(_ pcm: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["clang", "-module-file-info", pcm.path]
    let out = Pipe()
    process.standardOutput = out
    process.standardError = out
    try? process.run()
    // -module-file-info prints far more than a pipe buffer holds, so drain to
    // EOF before waiting; waiting first would deadlock against clang's write.
    let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

private func parseModuleFileInfo(_ text: String) -> (name: String?, headers: [String]) {
    var name: String?
    var headers: [String] = []
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Module name:") {
            name = String(line.dropFirst("Module name:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("Input file:") {
            var path = String(line.dropFirst("Input file:".count)).trimmingCharacters(in: .whitespaces)
            if path.hasSuffix("[System]") {
                path = String(path.dropLast("[System]".count)).trimmingCharacters(in: .whitespaces)
            }
            // A dependency's module map lists as an input of the importing
            // module even when the import is clean, so only actual headers
            // signal absorption.
            guard !path.hasSuffix(".modulemap"), !path.hasSuffix(".json") else { continue }
            headers.append(path)
        }
    }
    return (name, headers)
}

struct QtModule: CustomTestStringConvertible, Sendable {
    let name: String
    let headers: [String]
    var testDescription: String { name }
    var isPrivate: Bool { name.hasSuffix("_Private") }
    var family: String { isPrivate ? String(name.dropLast("_Private".count)) : name }
}

private func discoverQtModules() -> [QtModule] {
    let build = buildDir()
    var byName: [String: (modified: Date, module: QtModule)] = [:]
    let walk = FileManager.default.enumerator(at: build, includingPropertiesForKeys: [.contentModificationDateKey])
    while let url = walk?.nextObject() as? URL {
        guard url.pathExtension == "pcm", url.lastPathComponent.hasPrefix("Qt") else { continue }
        let (name, headers) = parseModuleFileInfo(moduleFileInfo(url))
        guard let name, name.hasPrefix("Qt") else { continue }
        let modified =
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let existing = byName[name], existing.modified.compare(modified) != .orderedAscending { continue }
        byName[name] = (modified, QtModule(name: name, headers: headers))
    }
    let modules = byName.values.map(\.module)
        .sorted { $0.name.compare($1.name) == .orderedAscending }
    return modules
}

private func owningQtModule(_ path: String) -> String? {
    for component in path.split(separator: "/").dropLast().reversed() {
        let name = String(component)
        if name.hasSuffix(".framework") {
            let base = String(name.dropLast(".framework".count))
            if base.hasPrefix("Qt") { return base }
        } else if name.hasPrefix("Qt"), name.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return name.hasSuffix("Module") ? String(name.dropLast("Module".count)) : name
        }
    }
    return nil
}

private func isTextualHeader(_ path: String) -> Bool {
    path.hasSuffix("_impl.h")
}

private let privateSubdirs: Set<String> = ["private", "qpa", "rhi", "spi"]
private func isPrivateHeader(_ path: String) -> Bool {
    path.hasSuffix("_p.h") || path.split(separator: "/").contains { privateSubdirs.contains(String($0)) }
}
