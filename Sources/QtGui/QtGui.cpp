// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include <QtCore_p.h>

#include <QtGui/qguiapplication.h>

static void registerApplicationType()
{
    // The QtWidgets shim may have run first, and QApplication wins
    if (QtPrivate::applicationFactory)
        return;

    QtPrivate::applicationFactory = [](int &argc, char **argv) -> QCoreApplication * {
        return new QGuiApplication(argc, argv);
    };
    QtPrivate::applicationExec = &QGuiApplication::exec;
}
Q_CONSTRUCTOR_FUNCTION(registerApplicationType)
