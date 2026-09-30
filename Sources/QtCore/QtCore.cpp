// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#ifdef __APPLE__
// When opening an app's Package.swift in Xcode it will allow running
// on any target, including iOS targets that don't match the Qt we're
// building against, resulting in build errors when GL headers are not
// found. Give a better error message here.
# include <TargetConditionals.h>
# if !TARGET_OS_OSX
#  error Qt for Swift supports macOS only for now. Please select 'My Mac' as the run destination
# endif
#endif

#include "QtCore_p.h"

#include <QtCore/qlibraryinfo.h>

// Workaround for https://github.com/swiftlang/swift/issues/92761
QVersionNumber qLibraryInfoVersion()
{
    return QLibraryInfo::version();
}

namespace QtPrivate {
QCoreApplication *(*applicationFactory)(int &argc, char **argv) = nullptr;
int (*applicationExec)() = nullptr;
}

void qCreateApplication(int argc, char **argv)
{
    // QCoreApplication keeps a reference to argc
    static int applicationArgc = argc;
    if (QtPrivate::applicationFactory)
        QtPrivate::applicationFactory(applicationArgc, argv);
    else
        new QCoreApplication(applicationArgc, argv);
}

int qExecApplication()
{
    if (QtPrivate::applicationExec)
        return QtPrivate::applicationExec();
    return QCoreApplication::exec();
}
