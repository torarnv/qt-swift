// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

@_exported import QtCore
internal import QtCore_Private

#if canImport(Darwin)
    // On Apple platforms Qt's headers (qbytearray.h, qstringview.h) forward-declare
    // the Objective-C bridging types NSData and NSString rather than importing
    // Foundation. Swift's C++ importer then sees incomplete interfaces and leaves
    // orphaned "forward declared here" notes on every consumer. Re-export Foundation
    // so those types resolve to complete definitions.
    @_exported import Foundation
#endif

extension QLibraryInfo {
    // Workaround for https://github.com/swiftlang/swift/issues/92761
    public static func version() -> QVersionNumber {
        qLibraryInfoVersion()
    }
}

extension QVersionNumber: CustomStringConvertible {
    public var description: String {
        String(toString())
    }
}

// MARK: - Strings

extension String {
    public init(_ qstring: QString) {
        self = withExtendedLifetime(qstring) {
            let utf16 = UnsafeBufferPointer(
                start: qStringConstData(qstring),
                count: Int(qstring.size()))
            return String(decoding: utf16, as: UTF16.self)
        }
    }
}

extension QString: CustomStringConvertible {
    public var description: String {
        String(self)
    }
}

extension QString {
    public init(_ string: String) {
        var string = string
        self = string.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) {
                QString.fromUtf8($0.baseAddress, qsizetype($0.count))
            }
        }
    }
}

extension QString: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: DefaultStringInterpolation) {
        self.init(stringInterpolation.description)
    }
}

// MARK: - Application

public protocol QtApplication {
    @MainActor init()
}

extension QtApplication {
    @MainActor
    public static func main() {
        qCreateApplication(CommandLine.argc, CommandLine.unsafeArgv)
        let application = Self()
        exit(withExtendedLifetime(application) { qExecApplication() })
    }
}
