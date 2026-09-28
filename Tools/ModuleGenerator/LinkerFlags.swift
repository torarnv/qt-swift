// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

// Write a response file with the linker flags that depend on the Qt
// library path, for the consuming package's link line.
func writeLinkerFlags(for qt: QtPaths, to path: String) {
    let libDir = spmShellEscaped(qt.libDir)
    var linkerFlags = [
        "-L \(libDir)",
        "-Xlinker -rpath -Xlinker \(libDir)"
    ]
    #if os(macOS)
        linkerFlags.append("-F \(libDir)")
        // Make room for adjusting RPATHs later
        linkerFlags.append("-Xlinker -headerpad_max_install_names")
    #endif

    try! (linkerFlags.joined(separator: "\n") + "\n")
        .write(toFile: path, atomically: true, encoding: .utf8)
}

private func spmShellEscaped(_ path: String) -> String {
    let syntax: Set<Character> = [" ", "\t", "'", "\"", "\\"]
    return path.map { syntax.contains($0) ? "\\\($0)" : String($0) }.joined()
}
