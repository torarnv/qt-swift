// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtWidgets

@main
struct HelloWidgets: QtApplication {
    init() {
        let widget = QSizeGrip(nil)
        #if compiler(>=6.5)
            widget.setWindowTitle("Hello 🌍 from Qt \(qtVersion())")
        #endif
        widget.resize(400, 300)
        widget.show()
    }
}
