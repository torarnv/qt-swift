// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HelloWidgets",
    platforms: [.macOS("15")],
    products: [
        .executable(name: "HelloWidgets", targets: ["HelloWidgets"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "HelloWidgets",
            dependencies: [
                .product(name: "QtWidgets", package: "qt-swift")
            ],
            path: ".",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("ImportCxxMembersLazily")
            ],
        )
    ]
)
