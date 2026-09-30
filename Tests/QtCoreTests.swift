// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import QtCore
import Testing

@Test func qstringConvertsToSwiftString() {
    let text = "Hællø 🌍"
    let qstring = text.withCString { QString.fromUtf8($0, -1) }
    #expect(String(qstring) == text)
    #expect("\(qstring)" == text)
}

@Test func nullQStringConvertsToEmptyString() {
    #expect(String(QString()).isEmpty)
}

@Test func swiftStringConvertsToQString() {
    let text = "Hællø 🌍"
    #expect(String(QString(text)) == text)
    #expect(QString("").size() == 0)
}

@Test func qstringTakesStringLiterals() {
    let literal: QString = "Hællø 🌍"
    #expect(String(literal) == "Hællø 🌍")

    let interpolated: QString = "Qt \(6) rules"
    #expect(String(interpolated) == "Qt 6 rules")
}

// MARK: - Version

@Test func qlibraryInfoVersionIsInitialized() {
    // Swift drops calls to Q_DECL_CONST_FUNCTION functions returning C++
    // types, which left the result as uninitialized memory.
    let version = QLibraryInfo.version()
    #expect(!version.isNull())
    #expect(version.majorVersion() >= 6)
    #expect(version.segmentCount() >= 3)
}

@Test func qversionNumberConvertsToString() {
    let version = QLibraryInfo.version()
    let expected = [version.majorVersion(), version.minorVersion(), version.microVersion()]
        .map(String.init)
        .joined(separator: ".")
    #expect(version.description == expected)
    #expect("\(version)" == expected)
}

// MARK: - Objects

@Test func qobjectImportsAsReferenceType() {
    // A reference type is a pointer. Imported by value it would be the C++ object.
    #expect(MemoryLayout<QObject>.size == MemoryLayout<UnsafeRawPointer>.size)
}

@Test func qobjectSubclassesInheritReferenceSemantics() {
    // Neither carries an API notes entry. Deriving from QObject is enough.
    #expect(MemoryLayout<QThread>.size == MemoryLayout<UnsafeRawPointer>.size)
    #expect(MemoryLayout<QTimer>.size == MemoryLayout<UnsafeRawPointer>.size)
}

@Test func qobjectPointersImportAsOptionalObjects() {
    let thread: QThread? = QThread.currentThread()
    #expect(thread != nil)
    #expect(thread!.parent() == nil)
}

@Test func qobjectBindingsShareOneObject() {
    let thread = QThread.currentThread()!
    let alias = QThread.currentThread()!
    let wasBlocked = thread.blockSignals(true)
    #expect(alias.signalsBlocked())
    _ = thread.blockSignals(wasBlocked)
}

@Test func qobjectSubclassesInheritMembers() {
    let thread = QThread.currentThread()!
    #expect(thread.inherits("QObject"))
    #expect(thread.inherits("QThread"))
    #expect(!thread.isWidgetType())
}
