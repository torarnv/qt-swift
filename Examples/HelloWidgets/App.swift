// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtWidgets

@main
struct HelloWidgets: QtApplication {
    init() {
        let title: QString = "Hello 🌍 from Qt \(QLibraryInfo.version())"

        #if compiler(>=6.5)
            let widget = QWidget()
            widget.setWindowTitle(title)
        #else
            let widget = QSizeGrip(nil)
            unsafeBitCast(widget, to: QWidget.self).setWindowTitle(title)
        #endif

        widget.resize(400, 300)
        widget.show()
    }
}
