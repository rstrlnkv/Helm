// swift-tools-version: 6.0
import PackageDescription

/// **A module is two source targets and the test targets it keeps, and the manifest says so once.**
///
/// Every module had its own nine lines repeated nine times — engine, UI, engine
/// tests, UI tests, and an entry in `HelmApp`'s dependency list — so adding one
/// meant five separate correct edits in five separate places, and a single wrong
/// `path:` here breaks `swift test` for everybody. It already has: `Package.swift`
/// declared `Tests/Modules/Autopilot/UITests` for weeks while that directory
/// existed only as untracked files in one checkout, and SwiftPM refuses the whole
/// manifest without it — so the suite ran here and on nobody else's machine.
///
/// **A test target exists only where a kept test lives.** A flag true over a missing
/// directory is a manifest SwiftPM refuses, on every machine, the day it is missing. A
/// flag false over a directory that holds tests is the quiet way: SwiftPM says nothing
/// and the directory is not compiled, so `ListsAgreeWithTheTreeTests` reads the two
/// against each other.
///
/// **The manifest never reads the filesystem.** It would be easy to walk
/// `Sources/Modules` and believe what is there — and then a missing directory
/// would be a missing target instead of an error, which is the same silence in a
/// new shape. A compile error has to stay a compile error everywhere.
struct Module {
    let name: String
    /// Only the UI half has ever carried resources.
    var uiResources: [Resource] = []
    /// A test target only where a kept test lives; `Tests/Modules/<Name>/EngineTests` and `.../UITests`.
    var engineTests = false
    var uiTests = false

    var engine: String { "Module_\(name)_Engine" }
    var ui: String { "Module_\(name)_UI" }
}

/// The order is the order `HelmApp` listed them in, which is roughly the order
/// they were written.
let modules: [Module] = [
    Module(name: "KeepAwake", engineTests: true, uiTests: true),
    Module(name: "VPN", engineTests: true, uiTests: true),
    Module(name: "Uninstaller", engineTests: true, uiTests: true),
    Module(name: "Homebrew", engineTests: true, uiTests: true),
    Module(name: "Leftovers", engineTests: true, uiTests: true),
    Module(name: "Disk", engineTests: true, uiTests: true),
    Module(name: "Duplicates", engineTests: true, uiTests: true),
    Module(name: "Autopilot", engineTests: true, uiTests: true),
    // flag-icons flag artwork, MIT — see NOTICE.md.
    Module(name: "Layout", uiResources: [.copy("Flags")], engineTests: true, uiTests: true),
    // The editor palette's Pen, Marker, Pencil, Eraser and Ruler artwork, from a community recreation of Apple's PencilKit
    // picker, modified for Helm, and the Spotlight, its shape drawn for Helm — NOTICE.md records the source and the owner's decision;
    // author and licence are placeholders there for the owner.
    Module(name: "Screenshots", uiResources: [.process("PaletteObjects.xcassets")], engineTests: true, uiTests: true),
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

    /// A test target declares one half of its module and no more: a UI test
    /// gets the engine through the UI target that already depends on it.
    /// `HelmTestSupport` is the exception every test target gets, because it is
    /// the harness rather than the subject.
    var testTargets: [Target] {
        (engineTests ? [.testTarget(name: "\(engine)Tests", dependencies: [.byName(name: engine), "HelmTestSupport"],
                                    path: "Tests/Modules/\(name)/EngineTests")] : [])
            + (uiTests ? [.testTarget(name: "\(ui)Tests", dependencies: [.byName(name: ui), "HelmTestSupport"],
                                      path: "Tests/Modules/\(name)/UITests")] : [])
    }
}

/// The three every module is built on, and the one Objective-C target under
/// them.
///
/// **`HelmLaunch` is the package's only non-Swift target, and it exists for
/// the calls `HelmLaunch.h` declares.** `NSTask` raises an Objective-C exception on some launch paths, and
/// such an exception goes straight past a Swift `catch` into `std::terminate` —
/// so the guard that was written around `process.run()` could not work, whatever
/// it said, and a shipped build died with SIGABRT. The `@try` has to sit in
/// Objective-C with no Swift frame between it and the raise; that is
/// the launch. `HelmReadNumber` calls an object's own floating-point getter
/// by name, where a raise would be just as fatal. `HelmLaunch.h` carries the
/// measurement of the first and says what the second rests on.
let foundation: [Target] = [
    .target(name: "HelmLaunch"),
    .target(name: "HelmContract"),
    // One edge, and only this direction: `StatusPlan` chooses among the
    // contract's `StatusAppearance` values. The contract stays free of
    // everything.
    .target(name: "HelmRuntime", dependencies: ["HelmContract", "HelmLaunch"]),
    .target(name: "HelmUI", dependencies: ["HelmContract", "HelmRuntime"]),
]

/// The harness, which belongs to every test target and to no product.
///
/// A plain target rather than a test target: a test target cannot be depended
/// on, and this has to reach every one of them. It is under `Tests/` because that is
/// what it is — nothing in `Sources/` may import it, and nothing can, since no
/// product lists it.
///
/// **And a release build must not reach it either.** It imports XCTest, which
/// resolves out of the Xcode-only framework path, so building the whole package
/// in Release made a full Xcode install a requirement of packaging the app —
/// and put `HelmTestSupport.swiftmodule` in Release beside `HelmApp`.
/// `ReleaseBuildsTheProductTests` holds the packaging script to the product.
///
/// What lives here is what was written once per test file until it was written
/// wrong: a scratch directory whose teardown **drains**, and the file-of-N-bytes
/// every filesystem test needs. `Tests/Support/ScratchDirectory.swift` carries
/// the measurement that says why.
/// It depends on `HelmRuntime` for one reason: a stand-in for a *port* has to
/// conform to that port's protocol, and `SealKeyPort` lives there. The
/// dependency runs the only way it can — support may reach the shared plumbing,
/// nothing may reach support.
let support: [Target] = [
    // `HelmUI` for the measuring-bench declaration `MountedRender` makes:
    // a page idles while its window is off screen, and every bench window is.
    .target(name: "HelmTestSupport", dependencies: ["HelmRuntime", "HelmUI"], path: "Tests/Support"),
]

/// Screen instruments: built by `swift build --target HelmReadout`, listed in no
/// product (SwiftPM synthesises one for an executable target) and no dependency of
/// `HelmApp`, so `--product HelmApp` in `Scripts/package-app.sh` never builds them;
/// no dependencies, so an import of Helm's own target fails its build.
let instruments: [Target] = [
    .executableTarget(name: "HelmReadout"),
]

/// The kit on show: `swift build --product HelmShowcase`. Listed in no product (SwiftPM synthesises one for
/// an executable target) and no dependency of `HelmApp`, so `--product HelmApp` never builds it. It depends
/// on `HelmUI` alone, so the build refuses an engine (not reached through `HelmUI`); it cannot refuse
/// `HelmRuntime`, which is reached through `HelmUI`, and `TheBoundariesTheBuildCannotHoldTests` reads the
/// import lines for that.
let showcase: [Target] = [
    .executableTarget(name: "HelmShowcase", dependencies: ["HelmUI"]),
]

/// The host and the tests that belong to no module.
let host: [Target] = [
    // The host's words sit in a library, not in `HelmApp`: an executable target's testable
    // variant is compiled without its string catalogs (only the product variant lists them in its
    // sources phase), so `L(.x)` there builds for the product and fails `swift build --build-tests`.
    // A library has a static and a `-dynamic` target; tests build on the static one. Read with
    // `swift package dump-pif --preserve-structure`.
    .target(name: "HelmAppStrings", dependencies: ["HelmRuntime", "HelmUI"]),
    .executableTarget(
        name: "HelmApp",
        // The UI targets only: the host talks to a module through its descriptor,
        // and each descriptor already depends on its own engine. A direct edge
        // here is a door past the descriptor into an engine's internals.
        dependencies: ["HelmAppStrings", "HelmContract", "HelmRuntime", "HelmUI", "HelmLaunch"]
            + modules.map { .byName(name: $0.ui) }
    ),
    .testTarget(name: "HelmContractTests",
                dependencies: ["HelmContract", "HelmTestSupport"]),
    .testTarget(name: "HelmAppTests",
                dependencies: ["HelmApp", "HelmAppStrings", "HelmContract", "HelmRuntime", "HelmUI",
                               "HelmTestSupport"]),
    .testTarget(name: "HelmRuntimeTests",
                dependencies: ["HelmRuntime", "HelmContract", "HelmTestSupport"]),
    .testTarget(name: "HelmUITests", dependencies: ["HelmUI", "HelmTestSupport"]),
]

let package = Package(
    name: "Helm",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    // One product: the app. Declared so `--product HelmApp` in
    // `Scripts/package-app.sh` names something this file says exists, rather
    // than the product SwiftPM synthesises for an executable target — a rename
    // of that target would otherwise break the release build silently.
    //
    // It is not what keeps the harness out of Release. Measured: with this list
    // in place a bare `swift build -c release` still builds every target,
    // `HelmTestSupport` included. Naming the product on the command line is
    // what prunes the graph.
    products: [
        .executable(name: "HelmApp", targets: ["HelmApp"]),
    ],
    targets: foundation
        + modules.flatMap(\.sourceTargets)
        + support
        + instruments
        + showcase
        + host
        + modules.flatMap(\.testTargets)
)
