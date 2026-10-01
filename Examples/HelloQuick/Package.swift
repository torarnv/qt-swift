// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "HelloQuick",
    platforms: [.macOS("15")],
    products: [
        .executable(name: "HelloQuick", targets: ["HelloQuick"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "HelloQuick",
            dependencies: [
                .product(name: "QtQuick", package: "qt-swift")
            ],
            path: ".",
            resources: [.copy("App.qml")],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("ImportCxxMembersLazily")
            ],
        )
    ]
)
