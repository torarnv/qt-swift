// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include <QtCore_p.h>

#include <QtWidgets/qapplication.h>

static void registerApplicationType()
{
    QtPrivate::applicationFactory = [](int &argc, char **argv) -> QCoreApplication * {
        return new QApplication(argc, argv);
    };
    QtPrivate::applicationExec = &QApplication::exec;
}
Q_CONSTRUCTOR_FUNCTION(registerApplicationType)
