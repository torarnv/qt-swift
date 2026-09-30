// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#pragma once

#include <QtCore/qcoreapplication.h>
#include <QtCore/qstring.h>
#include <QtCore/qversionnumber.h>

const char16_t *qStringConstData(const QString &string);

QVersionNumber qLibraryInfoVersion();

namespace QtPrivate {
// Set by constructor functions in the QtGui and QtWidgets shims,
// so that the application type matches the linked Qt modules.
extern QCoreApplication *(*applicationFactory)(int &argc, char **argv);
extern int (*applicationExec)();
}

void qCreateApplication(int argc, char **argv);
int qExecApplication();
