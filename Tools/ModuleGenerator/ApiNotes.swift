// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation

// API notes let us adjust how Swift imports a C++ declaration
func writeApiNotes(for module: QtModule, to outputDir: String) {
    let source = "\(module.overlayDir)/\(module.name).apinotes"
    guard FileManager.isFile(atPath: source) else { return }
    try! FileManager.default.copyItem(
        atPath: source,
        toPath: "\(outputDir)/\(module.name).apinotes")

    // FIXME: Generate API notes based on header macros such
    // as Q_ENUM/Q_FLAG.
}
