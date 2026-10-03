// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import QtQuick

@main
struct HelloQuick: QtApplication {
    init() {
        let title: QString = "Hello 🌍 from Qt \(QLibraryInfo.version())"

        #if compiler(>=6.5)
            let quickView = QQuickView()
            quickView.setTitle(title)
            quickView.setResizeMode(QQuickView.SizeRootObjectToView)
        #else
            let quickView = QQuickView(nil, nil)
            unsafeBitCast(quickView, to: QWindow.self).setTitle(title)
            quickView.setResizeMode(QQuickView.ResizeMode(rawValue: 1))
        #endif

        let qmlFile = Bundle.module.url(forResource: "App", withExtension: "qml")!
        quickView.setSource(QUrl.fromLocalFile(QString(qmlFile.path)))
        quickView.resize(400, 300)
        quickView.show()
    }
}
