// swift-tools-version: 6.4;(experimentalCGen)

import Foundation
import PackageDescription

let package = Package(
    name: "Qt",
    platforms: [
        .macOS("15")
    ],
    targets: [
        .plugin(
            // Build tool to update the known Qt modules that this package
            // will generate targets and products for.
            name: "Update Qt Modules",
            capability: .command(
                intent: .custom(
                    verb: "update-qt-modules",
                    description: """
                        Discovers installed Qt modules via
                        pkg-config and writes .qt-modules.json
                        """),
                permissions: [
                    .writeToPackageDirectory(
                        reason:
                            "Write the discovered Qt module set to .qt-modules.json")
                ]),
            path: "Plugins/UpdateQtModules")
    ],
    cxxLanguageStandard: .cxx17,
)

// Load known modules from .qt-modules.json
guard let modules = loadModules() else {
    // Don't warn when SPM is computing package dependencies
    // by just reading Package.swift from a git repository.
    if Package.dir.path != "/" {
        print(
            """
            Qt modules meta-data not found. Please generate via
            `swift package update-qt-modules`
            """)
    }
    exit(0)
}

package.targets += [
    // A systemLibrary target who's only job is to propagate the -I{prefix}/mkspecs
    // path to the module generator build plugin, so that it knows which Qt is being
    // used. Include paths are then synthesized by the generator, and linker flags
    // added via a response file, so no further Qt system libraries are needed.
    // FIXME: Ideally we would add one systemLibrary per Qt module, so that we would
    // reflect all the include and linker flags directly, but that also brings in a
    // wall of warnings from SwiftPM about prohibited flag(s) for -DQT_FOO_LIB.
    .systemLibrary(
        name: "Locate Qt",
        path: "Sources",
        pkgConfig: "Qt6Platform"
            // Intentionally no providers, as doing so makes SwiftPM pick
            // up Qt from Homebrew even if it's installed with --skip-link,
            // and we give our own instructions if Qt is not found anyways.
    ),
    // A module generator build tool plugin that can produce module maps
    // and API notes for each module, thanks to experimentalCGen.
    .plugin(
        name: "ModuleGeneratorPlugin",
        capability: .buildTool(),
        dependencies: ["ModuleGenerator"],
        path: "Plugins/ModuleGenerator"),
    .executableTarget(
        name: "ModuleGenerator",
        path: "Tools/ModuleGenerator")
]

let modulesByName = Dictionary(
    modules.map { ($0.name, $0) },
    uniquingKeysWith: { first, _ in first })

// Add targets for every known Qt module
package.targets += modules.flatMap { moduleTargets(for: $0) }

// Every Qt module gets a QtFooModule target, that generates the
// module map for the module. In addition we check if there are
// matching swift files in a Sources/QtFoo directory, and if so
// we build a Swift overlay module for the Qt module. If there
// are also C++ files in the directory we build a support library
// as well, that the overlay module can use for glue code. If we're
// not building a Swift overlay for the module it is represented
// in the product list by its QtFooModule target alone.
func moduleTargets(for module: QtModule) -> [Target] {
    let name = module.name

    // Set up target for dynamic module map generation. This relies
    // on the experimentalCGen feature, which allows a build tool
    // plugin to not only generate sources, but also provide headers,
    // a module.modulemap file, and API notes. SwiftPM needs a header
    // to create a target, which Sources/module.h provides.
    var targets: [Target] = [
        .target(
            name: "\(name)Module",
            dependencies: [.target(name: "Locate Qt")],
            path: "Sources",
            publicHeadersPath: ".",
            cxxSettings: Target.silenceUnusedCommandLineWarnings,
            linkerSettings: name == "QtCore"
                ? [
                    .unsafeFlags([
                        // Use a response file for linker flags that depend on
                        // the Qt library path, which we don't know at this point.
                        // The module generator writes this file during the build,
                        // based on the Qt version in use at the time.
                        "@"
                            + FileManager.default.temporaryDirectory
                            .appendingPathComponent("qt-linker-flags.def").path
                    ])
                ] : [],
            plugins: [.plugin(name: "ModuleGeneratorPlugin")]
        )
        .sourcesMatching("module.h")
    ]

    let moduleSources = moduleFiles(name)
    let hasOverlay = moduleSources.contains { $0.hasSuffix(".swift") }
    guard hasOverlay else { return targets }

    var overlayDependencies = dependencyProductTargets(module)
        .map { Target.Dependency.target(name: $0) }

    if moduleSources.contains(where: { $0.hasSuffix(".cpp") }) {
        // Shim target for the convenience of the overlay. Depends on the
        // shims of dependency modules, so it can include their headers.
        let shimDependencies = transitiveDependencies(module)
            .filter { moduleFiles($0.name).contains { $0.hasSuffix(".cpp") } }
            .map { Target.Dependency.target(name: "\($0.name)Shims") }
        targets.append(
            .target(
                name: "\(name)Shims",
                dependencies: ([module] + transitiveDependencies(module))
                    .map { .target(name: "\($0.name)Module") } + shimDependencies,
                path: "Sources/\(name)",
                publicHeadersPath: ".",
                cxxSettings: Target.silenceUnusedCommandLineWarnings
            )
            .sourcesMatching("*.cpp", among: moduleSources))

        overlayDependencies.append(.target(name: "\(name)Shims"))
    }

    // The overlay
    targets.append(
        .target(
            name: name,
            dependencies: overlayDependencies,
            path: "Sources/\(name)",
            swiftSettings: SwiftSetting.common
        )
        .sourcesMatching("*.swift", among: moduleSources))

    return targets
}

package.products = modules.map { module in
    let targets = Set([productTarget(module)] + dependencyProductTargets(module))
    return .library(name: module.name, targets: targets.sorted())
}

extension SwiftSetting {
    static let common: [SwiftSetting] = {
        var settings: [SwiftSetting] = [.interoperabilityMode(.Cxx)]
        #if compiler(<6.5)
            // Enabled by default in Swift 6.5, but 6.4 needs opt-in
            settings.append(.enableExperimentalFeature("ImportCxxMembersLazily"))
        #endif
        return settings
    }()
}

// MARK: - Tests

let testSources: [String] =
    ((try? FileManager.default.contentsOfDirectory(
        atPath: Package.dir.appendingPathComponent("Tests").path)) ?? [])
    .filter { $0.hasSuffix(".swift") }

var moduleWarningSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-Xcc", "-fdiagnostics-absolute-paths",
        "-Xcc", "-fdiagnostics-show-note-include-stack"
    ]),
    .unsafeFlags([
        "-Xcc", "-Wincomplete-module",
        "-Xcc", "-Wincomplete-umbrella",
        "-Xcc", "-Watimport-in-framework-header",
        "-Xcc", "-Wnon-modular-include-in-module",
        "-Xcc", "-Wnon-modular-include-in-framework-module",
        "-Xcc", "-Wmodule-map-path-outside-directory",
        "-Xcc", "-Wquoted-include-in-framework-header",
        "-Xcc", "-Wframework-include-private-from-public",
        "-Xcc", "-Wincomplete-framework-module-declaration"
    ]),
    .unsafeFlags(["-Xcc", "-Werror"], .when(configuration: .release))
]

#if os(Linux)
    // Silence warnings that result from non-modularized system headers
    moduleWarningSettings.append(
        .unsafeFlags([
            "-Xcc", "-Wno-non-modular-include-in-module",
            "-Xcc", "-Wno-deprecated-builtins",
            "-Xcc", "-Wno-ignored-attributes",
            "-Xcc", "-Wno-module-import-in-extern-c"
        ]))
#endif

package.targets += [
    .plugin(
        name: "TestGeneratorPlugin",
        capability: .buildTool(),
        path: "Plugins/ModuleBuildTests"
    ),
    // Add a test that imports every single known Qt module,
    // triggering clang module compilation in the process. The
    // test then checks each .pcm, validating that the module
    // didn't make claim to headers from other Qt modules.
    .testTarget(
        name: "ModuleBuildTests",
        dependencies: Array(Set(modules.map { productTarget($0) }))
            .sorted().map { .target(name: $0) },
        path: "Tests",
        swiftSettings: SwiftSetting.common + moduleWarningSettings + [
            // Make sure we see module map warnings, even if we
            // declare our modules as system modules.
            .unsafeFlags(
                modules.flatMap { module in
                    ["-Xcc", "-Wsystem-headers-in-module=\(module.name)"]
                })
        ],
        plugins: [.plugin(name: "TestGeneratorPlugin")]
    )
    .sourcesMatching("ModuleBuildTests.swift", among: testSources)
]

// Add test targets for modules with deciated test files
for module in modules {
    let name = module.name
    let testFile = "\(name)Tests.swift"
    guard testSources.contains(testFile) else { continue }
    package.targets.append(
        .testTarget(
            name: "\(name)Tests",
            dependencies: [.target(name: productTarget(module))],
            path: "Tests",
            swiftSettings: SwiftSetting.common + moduleWarningSettings + [
                .unsafeFlags([
                    "-Xcc", "-Wsystem-headers-in-module=\(name)"
                ])
            ]
        )
        .sourcesMatching(testFile, among: testSources)
    )
}

// MARK: - Helpers

extension Package {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
}

struct QtModule: Decodable {
    let name: String
    let requires: [String]
    let repo: String
}

func loadModules() -> [QtModule]? {
    let knownModules = Package.dir.appendingPathComponent(".qt-modules.json")
    guard let data = try? Data(contentsOf: knownModules) else { return nil }
    guard let modules = try? JSONDecoder().decode([QtModule].self, from: data) else { return nil }

    let brokenModules: Set<String> = [
        // These modules ship public headers that include private headers
        "QtHelp",
        "QtRemoteObjects",
        "QtRemoteObjectsQml",
        "QtIfRemoteObjectsHelper",
        "QtVirtualKeyboard",
        "QtVirtualKeyboardQml",

        // Textually include a sibling AppMan framework they don't
        // declare as a dependency
        "QtAppManApplicationQmlPrivate",
        "QtAppManSharedQmlPrivate",
        "QtAppManTestQmlPrivate",

        // Replaced by QtGraphs. Uses same class names, clashing
        "QtDataVisualization", "QtDataVisualizationQml",
        "QtCharts", "QtChartsQml",

        // Quoted includes from embedded Google protobuf headers
        "QtProtobufWellKnownTypes",

        // Internal module not meant to be used by end users
        "QtExamplesAssetDownloader", "QtQmlAssetDownloader",
        "QtAppManSystemUIQmlPrivate"

    ]

    return filterModules(modules.filter { !brokenModules.contains($0.name) })
        .sorted { $0.name < $1.name }
}

// Allow consumers to limit the module set to the modules listed in
// QT_SWIFT_MODULES and their dependencies, as swift build runs the
// module generator plugin for every target, even those not in use.
// https://github.com/swiftlang/swift-package-manager/issues/10590
func filterModules(_ modules: [QtModule]) -> [QtModule] {
    guard let filter = Context.environment["QT_SWIFT_MODULES"], !filter.isEmpty else {
        return modules
    }
    let byName = Dictionary(
        modules.map { ($0.name, $0) },
        uniquingKeysWith: { first, _ in first })
    var included = Set<String>()
    func include(_ name: String) {
        guard included.insert(name).inserted, let module = byName[name] else { return }
        module.requires.forEach(include)
    }
    for name in filter.split(separator: ",") {
        include(name.trimmingCharacters(in: .whitespaces))
    }
    return modules.filter { included.contains($0.name) }
}

func moduleFiles(_ module: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(
        atPath: Package.dir.appendingPathComponent("Sources/\(module)").path)) ?? [])
        .sorted()
}

func productTarget(_ module: QtModule) -> String {
    let hasOverlay = moduleFiles(module.name).contains { $0.hasSuffix(".swift") }
    return hasOverlay ? module.name : "\(module.name)Module"
}

func transitiveDependencies(_ module: QtModule) -> [QtModule] {
    var seen = Set<String>()
    var result: [QtModule] = []
    func visit(_ name: String) {
        guard seen.insert(name).inserted, let required = modulesByName[name] else { return }
        result.append(required)
        for next in required.requires { visit(next) }
    }
    for name in module.requires { visit(name) }
    return result
}

func dependencyProductTargets(_ module: QtModule) -> [String] {
    let targets = ["\(module.name)Module"] + transitiveDependencies(module).map(productTarget)
    return Array(Set(targets)).sorted()
}

extension Target {
    // Simplify source listings when we share source directories. With no explicit
    // file list, read the target's own source directory off disk.
    func sourcesMatching(_ pattern: String, among files: [String]? = nil) -> Target {
        let available =
            files
            ?? ((try? FileManager.default.contentsOfDirectory(
                atPath: Package.dir.appendingPathComponent(path ?? "Sources/\(name)").path)) ?? [])
            .sorted()
        let matches: (String) -> Bool
        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            matches = { $0.hasSuffix(suffix) }
        } else {
            matches = { $0 == pattern }
        }
        self.sources = available.filter(matches)
        self.exclude = available.filter { file in
            if publicHeadersPath != nil, file.hasSuffix(".h") { return false }
            return !matches(file)
        }
        return self
    }

    // The build system enables clang modules for every target, but pairs
    // -fmodules with -fno-cxx-modules, leaving -fmodules-cache-path unused
    // in our C++ only targets.
    static let silenceUnusedCommandLineWarnings: [CXXSetting] = [
        .unsafeFlags(["-Wno-unused-command-line-argument"])
    ]
}
