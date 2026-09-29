# Qt for Swift

Use [Qt](https://www.qt.io) from Swift. This package exposes every installed
Qt 6 module to Swift so you can `import QtCore`, `import QtWidgets`,
or `import QtQuick` and call Qt's C++ APIs directly from Swift code.

## Requirements

### Swift 6.4 or later

Shipped with Xcode, or installed via [`swiftly`](https://github.com/swiftlang/swiftly).

> [!IMPORTANT]
> This project heavily exercises the Swift C++ interoperability machinery and
> `experimentalCGen` build tool feature, and you may hit sharp corners. If possible,
> use a nightly Swift toolchain, to ensure the smoothest ride.

### Qt 6.8 or later

Installed from the [Qt Online Installer](https://www.qt.io/development/download-qt-installer-oss),
system package manager ([Homebrew](https://formulae.brew.sh/formula/qt), `apt`, etc), or your own
local build.

> [!TIP]
> If Qt has been installed outside of the system `pkg-config` location you
> can point the build to it via `swift build --pkg-config-path <…>` or by opening
> Xcode with a custom `PKG_CONFIG_PATH` set: `open --env PKG_CONFIG_PATH=<…> -a Xcode`

### Platforms

The package has been tested on [![macOS][macos-badge]][ci] and [![Linux][linux-badge]][ci]

[macos-badge]: https://img.shields.io/github/check-runs/torarnv/qt-swift/main?nameFilter=macOS&label=macOS&logo=apple
[linux-badge]: https://img.shields.io/github/check-runs/torarnv/qt-swift/main?nameFilter=Linux&label=Linux&logo=linux&logoColor=white
[ci]: https://github.com/torarnv/qt-swift/actions/workflows/ci.yml

## Installation

### Swift Package Manager

Add the package to the dependencies in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/torarnv/qt-swift.git", branch: "main")
]
```

Then depend on the Qt modules you need, and turn on C++ interoperability in
every target that imports Qt:

```swift
.executableTarget(
    name: "MyApp",
    dependencies: [
        .product(name: "QtWidgets", package: "qt-swift")
    ],
    swiftSettings: [
        .interoperabilityMode(.Cxx),
        .enableExperimentalFeature("ImportCxxMembersLazily")
    ]
)
```

### Xcode project

Choose _File → Add Package Dependencies_, enter `https://github.com/torarnv/qt-swift.git`,
and add the Qt modules you need to your app target.

Then turn on the same Swift settings as above, using a configuration file.
Choose _File → New → File from Template_, pick _Configuration Settings File_,
and name it `Qt.xcconfig`:

```
SWIFT_OBJC_INTEROP_MODE = objcxx
OTHER_SWIFT_FLAGS = $(inherited) -enable-experimental-feature ImportCxxMembersLazily
```

Select the project in the navigator, open the _Info_ tab, and under
_Configurations_ set `Qt` as the configuration file of your app target,
for both _Debug_ and _Release_.

## Features

### Applications

Conform your `@main` type to `QtApplication`. The package creates the Qt
application object, calls your `init()` to set up the UI, and then runs the
event loop until the application quits.

```swift
import QtWidgets

@main
struct HelloWidgets: QtApplication {
    init() {
        // ...
    }
}
```

### Strings

`QString` and Swift `String` convert in both directions, and `QString` accepts
string literals and interpolation:

```swift
let title: QString = "Hello from Qt \(6) 👋🏻"
let text = String(title)
print(QString("Hællø 🌍"))
```

## Examples

The `Examples` directory holds small projects you can build and run:

- `HelloCore` prints the Qt version
- `HelloWidgets` shows a window using Qt Widgets
- `HelloQuick` shows a Qt Quick scene

## License

Qt for Swift is available under the terms of the GNU Lesser General Public
License v3 (`LGPL-3.0-only`), or under a commercial Qt license. See the
`LICENSES` directory for the full texts.
