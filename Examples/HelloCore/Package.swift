// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "HelloCore",
    platforms: [.macOS("15")],
    products: [
        .executable(name: "HelloCore", targets: ["HelloCore"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "HelloCore",
            dependencies: [
                .product(name: "QtCore", package: "qt-swift")
            ],
            path: ".",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .enableExperimentalFeature("ImportCxxMembersLazily")
            ],
        )
    ],
    cxxLanguageStandard: .cxx17
)
