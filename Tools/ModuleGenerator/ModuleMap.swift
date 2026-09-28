// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

func writeModuleMap(for module: QtModule, to outputDir: String) {
    try! (moduleDeclarations(for: module) + "\n")
        .write(
            toFile: "\(outputDir)/module.modulemap",
            atomically: true, encoding: .utf8)
}

// Generate module declarations for a single Qt module
private func moduleDeclarations(for qtModule: QtModule) -> String {
    var publicModule = ModuleDeclaration(name: qtModule.name)
    publicModule.body += headerDeclarations(for: qtModule.headers?.publicHeaders ?? [])
    publicModule.body += qtModule.overlayPublicHeaders.map { "header \"\($0)\"" }
    publicModule.body += qtModule.promotedHeaders.map {
        "private header \"\(promotedHeaderPath(for: $0, in: qtModule))\""
    }

    let linkDeclarations =
        qtModule.hasFramework
        ? ["link framework \"\(qtModule.name)\""]
        : qtModule.hasLibrary
            ? ["link \"\(qtModule.libraryName)\""]
            : []
    publicModule.body += linkDeclarations

    publicModule.body += Set(
        qtModule.dependencies
            .filter { $0.hasPrefix("Qt") }
    )
    .sorted().map { "use \($0)" }

    var declarations = [publicModule]

    // Private headers in Qt are not ready to be modularized
    let modularizePrivateHeaders = false
    if modularizePrivateHeaders || !qtModule.overlayPrivateHeaders.isEmpty {
        var privateModule = ModuleDeclaration(name: "\(qtModule.name)_Private")
        privateModule.body += qtModule.overlayPrivateHeaders.map { "header \"\($0)\"" }
        if modularizePrivateHeaders {
            privateModule.body += headerDeclarations(for: qtModule.headers?.privateHeaders ?? [])
        }
        privateModule.body += linkDeclarations
        declarations.append(privateModule)
    }

    return declarations.map(\.text).joined(separator: "\n\n")
}

private func headerDeclarations(for headerFiles: [String]) -> [String] {
    guard !headerFiles.isEmpty else { return [] }

    // Qt uses #pragmas in headers to steer the name of the forwarding
    // headers it generates, or to generate deprecation-headers, which
    // affects the qualifiers we use in the module map.

    var pragmasByHeader: [String: [QtPragma]] = [:]
    for header in headerFiles where header.hasSuffix(".h") {
        let pragmas = qtPragmas(inHeader: header)
        guard !pragmas.isEmpty else { continue }
        pragmasByHeader[header] = pragmas
    }
    var deprecatedNames: Set<String> = []
    for pragma in pragmasByHeader.values.joined() where pragma.name == "qt_deprecates" {
        guard let name = pragma.arguments.first else { continue }
        deprecatedNames.insert(name)
        deprecatedNames.insert(name.lowercased())
    }

    func line(_ header: String, textual: Bool) -> String {
        return "\(textual ? "textual " : "")header \"\(header)\""
    }

    var lines: [String] = []
    var forwarders: [String] = []
    var textualForwarders: Set<String> = []
    for header in headerFiles {
        let name = header.lastPathComponent
        guard name.hasSuffix(".h") else {
            if !name.contains(".") { forwarders.append(header) }
            continue
        }
        let textual = shouldBeTextual(name, deprecatedNames: deprecatedNames)
        if textual {
            for pragma in pragmasByHeader[header] ?? [] where pragma.name == "qt_class" {
                if let name = pragma.arguments.first { textualForwarders.insert(name) }
            }
        }
        lines.append(line(header, textual: textual))
    }
    for header in forwarders {
        let name = header.lastPathComponent
        let textual =
            textualForwarders.contains(name)
            || explicitlyTextualHeaders.contains(name)
            || deprecatedNames.contains(name)
        lines.append(line(header, textual: textual))
    }
    return lines
}

private func shouldBeTextual(_ entry: String, deprecatedNames: Set<String>) -> Bool {
    if entry.hasSuffix("_deprecated.h") {
        return true
    } else if explicitlyTextualHeaders.contains(entry) {
        return true
    } else if promotedPrivateHeaders.contains(entry) {
        // The public module builds the copy, so don't build the original
        return true
    } else if deprecatedNames.contains(String(entry.dropLast(2))) {
        return true
    } else if entry.hasSuffix("_impl.h") {
        return true
    } else if entry.hasSuffix("_interface.h") || entry.hasSuffix("_adaptor.h") {
        // https://codereview.qt-project.org/c/qt/qtbase/+/763231
        return true
    } else {
        return false
    }
}

// Headers that don't build cleanly as part of a module map
let explicitlyTextualHeaders: Set<String> = [
    // https://codereview.qt-project.org/c/qt/qtbase/+/763009
    "qvulkanfunctions.h", "QVulkanFunctions", "QVulkanDeviceFunctions",
    "qvulkanwindow.h", "QVulkanWindow", "QVulkanWindowRenderer",

    // QtDesigner ships these as compat headers that warn and forward to
    // QtUiPlugin. Importing them into the module fires the deprecation warning.
    "customwidget.h", "QDesignerCustomWidgetInterface",
    "QDesignerCustomWidgetCollectionInterface",
    "qdesignerexportwidget.h", "QDesignerExportWidget",

    // Includes non-Qt headers, which we don't have the include paths for
    "qcollator_p.h", "qcborcommon_p.h", "qdoublescanprint_p.h",
    "qtimezoneprivate_p.h", "qv4regexp_p.h", "qfontengine_ft_p.h",
    "qquickflexboxlayoutitem_p.h", "qquickflexboxlayoutengine_p.h",

    // error: "Include qmetaobject_p.h (or moc's utils.h) before including this file."
    "qmetaobject_moc_p.h",

    // Redefinition of enumerator 'CpuFeatureAES' from qsimd_p.h
    "qsimd_x86_p.h",

    // Relies on explicitly enabled QT_USE_QSTRINGBUILDER
    "qsgcurvestrokenode_p_p.h", "qsgcurvestrokenode_p.h", "qsgcurveprocessor_p.h",

    // Uses types without including their declaration
    "dbus_minimal_p.h",  // qint64
    "qapplekeymapper_p.h"  // NSEventModifierFlags
]

struct ModuleDeclaration {
    let name: String
    var body: [String] = []

    // We want to tag our modules as system, to silence warnings from Qt headers,
    // but in Linux builds that trips PackageModuleLoadedFromSDK because no -sdk
    // is passed, so we have to disable it there.
    #if os(macOS)
        let systemAttribute = " [system]"
    #else
        let systemAttribute = ""
    #endif

    var text: String {
        let indentedBody = body.map { "    " + $0 }.joined(separator: "\n")
        return """
            module \(name)\(systemAttribute) {
                requires cplusplus17
            \(indentedBody)
                export *
            }
            """
    }
}

// MARK: - Pragmas

struct QtPragma {
    let name: String
    let arguments: [String]
}

func qtPragmas(inHeader path: String) -> [QtPragma] {
    let lineLimit = 50  // Assume pragmas come in early
    guard let text = readFile(path: path, lineLimit: lineLimit),
        text.contains("pragma qt_")
    else { return [] }
    let spaces: (Character) -> Bool = { $0 == " " || $0 == "\t" }
    var pragmas: [QtPragma] = []
    for line in text.split(whereSeparator: \.isNewline).prefix(lineLimit) {
        var rest = line.drop(while: spaces)
        guard rest.first == "#" else { continue }
        rest = rest.dropFirst().drop(while: spaces)
        guard rest.hasPrefix("pragma") else { continue }
        rest = rest.dropFirst("pragma".count).drop(while: spaces)
        guard rest.hasPrefix("qt_") else { continue }
        let nameChars = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        rest = rest[nameChars.endIndex...].drop(while: spaces)
        var arguments: [String] = []
        if rest.first == "(", let close = rest.firstIndex(of: ")") {
            arguments = rest[rest.index(after: rest.startIndex)..<close]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        pragmas.append(QtPragma(name: String(nameChars), arguments: arguments))
    }
    return pragmas
}

private func readFile(path: String, lineLimit: Int) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    var data = Data()
    var newlines = 0
    while newlines < lineLimit {
        let chunk = handle.readData(ofLength: 4096)
        if chunk.isEmpty { break }
        data.append(chunk)
        newlines += chunk.lazy.filter { $0 == 0x0A }.count
    }
    return String(decoding: data, as: UTF8.self)
}
