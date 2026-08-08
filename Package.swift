// swift-tools-version: 6.0
import PackageDescription

/// **A module is four targets, and the manifest says so once.**
///
/// Every module had its own nine lines repeated nine times — engine, UI, engine
/// tests, UI tests, and an entry in `HelmApp`'s dependency list — so adding one
/// meant five separate correct edits in five separate places, and a single wrong
/// `path:` here breaks `swift test` for everybody. It already has: `Package.swift`
/// declared `Tests/Modules/Autopilot/UITests` for weeks while that directory
/// existed only as untracked files in one checkout, and SwiftPM refuses the whole
/// manifest without it — so the suite ran here and on nobody else's machine.
///
/// The shape is deliberately not optional. All four directories are required of
/// every module, so a missing one is a build failure on every machine on the day
/// it is missing, rather than a module quietly having no tests. KeepAwake was
/// exactly that: engine tests and no UI tests, while its UI target held the menu
/// bar look, a shared view-model cache and the settings accessors.
///
/// **The manifest never reads the filesystem.** It would be easy to walk
/// `Sources/Modules` and believe what is there — and then a missing directory
/// would be a missing target instead of an error, which is the same silence in a
/// new shape. A compile error has to stay a compile error everywhere.
struct Module {
    let name: String
    /// Only the UI half has ever carried resources.
    var uiResources: [Resource] = []

    var engine: String { "Module_\(name)_Engine" }
    var ui: String { "Module_\(name)_UI" }
}

/// The order is the order `HelmApp` listed them in, which is roughly the order
/// they were written.
let modules: [Module] = [
    Module(name: "KeepAwake"),
    Module(name: "VPN"),
    Module(name: "Uninstaller"),
    Module(name: "Homebrew"),
    Module(name: "Leftovers"),
    Module(name: "Disk"),
    Module(name: "Duplicates"),
    Module(name: "Autopilot"),
    // EmojiOne v2.2.7 flag artwork, CC-BY 4.0 — see NOTICE.md.
    Module(name: "Layout", uiResources: [.copy("Flags")]),
]

extension Module {

    var sourceTargets: [Target] {
        [
            .target(
                name: engine,
                dependencies: ["HelmContract", "HelmRuntime"],
                path: "Sources/Modules/\(name)/Engine"
            ),
            .target(
                name: ui,
                dependencies: ["HelmContract", "HelmUI", .byName(name: engine)],
                path: "Sources/Modules/\(name)/UI",
                resources: uiResources
            ),
        ]
    }

    /// A test target reaches one half of its module and no further: a UI test
    /// gets the engine through the UI target that already depends on it.
    var testTargets: [Target] {
        [
            .testTarget(
                name: "\(engine)Tests",
                dependencies: [.byName(name: engine)],
                path: "Tests/Modules/\(name)/EngineTests"
            ),
            .testTarget(
                name: "\(ui)Tests",
                dependencies: [.byName(name: ui)],
                path: "Tests/Modules/\(name)/UITests"
            ),
        ]
    }
}

/// The three every module is built on.
let foundation: [Target] = [
    .target(name: "HelmContract"),
    // One edge, and only this direction: `EngineReply` is engine-side wire
    // plumbing that logs, and the log lives here. The contract stays free of
    // everything.
    .target(name: "HelmRuntime", dependencies: ["HelmContract"]),
    .target(name: "HelmUI", dependencies: ["HelmContract", "HelmRuntime"],
            resources: [.process("Resources")]),
]

/// The host and the tests that belong to no module.
let host: [Target] = [
    .executableTarget(
        name: "HelmApp",
        // The UI targets only: the host talks to a module through its descriptor
        // and the transport, and each descriptor already depends on its own
        // engine. A direct edge here is a door past the transport into an
        // engine's internals.
        dependencies: ["HelmContract", "HelmRuntime", "HelmUI"]
            + modules.map { .byName(name: $0.ui) }
    ),
    .testTarget(name: "HelmContractTests", dependencies: ["HelmContract"]),
    .testTarget(name: "HelmAppTests",
                dependencies: ["HelmApp", "HelmContract", "HelmRuntime", "HelmUI"]),
    .testTarget(name: "HelmRuntimeTests", dependencies: ["HelmRuntime", "HelmContract"]),
    .testTarget(name: "HelmUITests", dependencies: ["HelmUI"]),
]

let package = Package(
    name: "Helm",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    targets: foundation
        + modules.flatMap(\.sourceTargets)
        + host
        + modules.flatMap(\.testTargets)
)
