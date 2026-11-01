import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// The hand-written lists have to agree with what they name.
///
/// **`HelmApp` can carry a test target after all.** Every plan written about
/// this assumed it could not — it is an `executableTarget` with a `main.swift`,
/// which historically cannot be imported for testing — so four defects lived in
/// `ScanCoordinator` unpinnable, and the fix was written as "move the decisions
/// out". Moving them out was right for its own reasons and this target is what
/// covers the rest: `.testTarget(dependencies: ["HelmApp"])`, `@testable import`,
/// and the registry answers. Nothing needed to move for these.
///
/// **Every engine builds in 55 ms with an in-memory store**, measured over the nine there were
/// before this file was written, so a test may hold the real registry
/// rather than a copy of it. `activate()` is never called: building is what these
/// checks need, and starting the modules' watchers inside a test is not.
final class ListsAgreeWithTheTreeTests: XCTestCase {

    @MainActor private func engines() -> [(id: String, engine: any ModuleEngine)] {
        // In-memory, never `UserDefaults`: a test that builds every engine
        // against the real store leaves every module's settings behind, and the
        // house rule about harnesses was written after exactly that.
        let backing = InMemoryKeyValueStore()
        return ModuleRegistry.all.map { descriptor in
            (descriptor.idRaw,
             engine(of: descriptor, store: NamespacedStore(namespace: descriptor.idRaw,
                                                           backing: backing)))
        }
    }

    /// Generic so the descriptor's `Model` is opened: `makeModule` cannot be
    /// called on an `any ModuleDescriptor`. It builds the model beside the
    /// engine, so a model whose init did work would do it here; no test
    /// asserts that it does not.
    @MainActor private func engine<D: ModuleDescriptor>(of descriptor: D,
                                                         store: NamespacedStore) -> any ModuleEngine {
        descriptor.makeModule(store: store).engine
    }

    // MARK: - The scan list

    /// A name in the list that is not a module is a scan that can never run —
    /// and it fails the way this codebase reads as "the module could not
    /// answer", which is a sentence about a module that exists.
    @MainActor func testEveryScannableModuleIsInTheRegistry() {
        let known = Set(ModuleRegistry.all.map(\.idRaw))
        for id in ScanRunner.scannableModules {
            XCTAssertTrue(known.contains(id),
                          "`\(id)` is in ScanRunner.scannableModules and not in ModuleRegistry.all")
        }
    }

    /// **This holds the engine's half of a silent, expensive failure.** A module
    /// in the list whose descriptor does not override the scan falls to the
    /// default, which answers `nil`; the caller reads `nil` and logs "no answer".
    /// That the descriptor passes the call on is held by `testTheDescriptorPassesTheScanOn`
    /// in each scanner's stopped-model class; `testEveryScannableModuleHasAPassOnTest`
    /// holds that the test is there.
    /// The coordinator then wakes every minute, tries again once per
    /// `ScanSchedule.retryInterval`, up to the day's runs, and nothing anywhere says the module never had a scan to run.
    @MainActor func testEveryScannableModuleHasAnEngineThatCanScan() {
        let scannable = Set(ScanRunner.scannableModules)
        for (id, engine) in engines() where scannable.contains(id) {
            XCTAssertTrue(engine is BackgroundScanning,
                          "`\(id)` is listed as scannable, and \(type(of: engine)) "
                          + "does not conform to BackgroundScanning")
        }
    }

    /// And the other direction, which is the half a list forgets: a module that
    /// grew the capability and was never added scans nothing, for ever, with
    /// nothing to see.
    @MainActor func testEveryEngineThatCanScanIsListed() {
        let scannable = Set(ScanRunner.scannableModules)
        for (id, engine) in engines() where engine is BackgroundScanning {
            XCTAssertTrue(scannable.contains(id),
                          "\(type(of: engine)) can scan in the background and `\(id)` "
                          + "is not in ScanRunner.scannableModules")
        }
    }

    /// Each scanning module's descriptor passes the scan on, and a test says so.
    /// The test reads the list: a scanner whose stopped-model class has no
    /// such test fails here, not in silence.
    func testEveryScannableModuleHasAPassOnTest() throws {
        for id in ScanRunner.scannableModules {
            let name = id.prefix(1).uppercased() + id.dropFirst()
            let source = try RepoSource.text(
                of: "Tests/Modules/\(name)/UITests/AStopped\(name)ModelReachesNoWorkTests.swift")
            XCTAssertTrue(source.contains("\(name)Descriptor().backgroundScan"),
                          "`\(id)` is scannable and no test calls its descriptor's backgroundScan")
        }
    }

    /// A test directory with no flag on its module's row is a suite nobody compiles: the manifest never reads the
    /// filesystem, SwiftPM says nothing, and `swift package describe` exits 0 with the targets gone.
    ///
    /// **The manifest is read as code.** A flag spelled in a comment is no flag, so block comments go, every line is cut
    /// at `//`, and only then is the row looked for. And the rows only count if the composition still lists the
    /// test targets they switch on, which a row cannot say. Both are read as text: the getter between them,
    /// `testTargets`, is not read, so a lost half of it stays green here, and a `HELM_FULL_SUITE=1` run names it
    /// through `Tests/optional-tests.txt` while each directory holds a listed class (`Scripts/test.sh`).
    func testEveryTestDirectoryOfAModuleIsDeclaredInTheManifest() throws {
        let text = try RepoSource.text(of: "Package.swift")
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        let code = text.split(separator: "\n").compactMap { line -> String? in
            let kept = line.components(separatedBy: "//")[0]
            return kept.trimmingCharacters(in: .whitespaces).isEmpty ? nil : kept
        }
        XCTAssertTrue(code.contains { $0.contains("modules.flatMap(\\.testTargets)") },
                      "Package.swift does not put `modules.flatMap(\\.testTargets)` into `targets:`: "
                      + "the flags on the rows switch on nothing")
        let root = RepoSource.root.appendingPathComponent("Tests/Modules")
        let manager = FileManager.default
        var checked = 0
        for module in try manager.contentsOfDirectory(atPath: root.path) where !module.hasPrefix(".") {
            let row = code.first { $0.contains("Module(name: \"\(module)\"") } ?? ""
            XCTAssertFalse(row.isEmpty, "`Tests/Modules/\(module)` has no `Module(name: \"\(module)\"` row in Package.swift: "
                           + "the flags below would fail for the wrong reason")
            for (directory, flag) in [("EngineTests", "engineTests"), ("UITests", "uiTests")] {
                guard manager.fileExists(atPath: root.appendingPathComponent("\(module)/\(directory)").path) else { continue }
                checked += 1
                XCTAssertTrue(row.contains("\(flag): true"), "`Tests/Modules/\(module)/\(directory)` exists and its row "
                              + "in Package.swift does not set `\(flag): true` in code, so whatever it holds is never compiled")
            }
        }
        XCTAssertGreaterThan(checked, 0, "no module test directory was read: the path is wrong")
    }

    // MARK: - The registry

    /// Two modules under one id share a store, a panel row and a settings page.
    @MainActor func testModuleIdsAreUnique() {
        let ids = ModuleRegistry.all.map(\.idRaw)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate module ids: \(ids)")
    }

    /// The sidebar draws `shortName` and everything else draws `name`; an empty
    /// one is a row with nothing in it, which no screenshot review catches
    /// because nobody photographs every module.
    @MainActor func testEveryModuleIsNamed() {
        for descriptor in ModuleRegistry.all {
            let metadata = descriptor.moduleMetadata
            XCTAssertFalse(metadata.name.isEmpty, "`\(descriptor.idRaw)` has no name")
            XCTAssertFalse(metadata.shortName.isEmpty, "`\(descriptor.idRaw)` has no short name")
        }
    }

    /// A symbol macOS does not ship draws nothing at all — an empty square in
    /// the sidebar, the panel and the icon menu.
    @MainActor func testEveryModuleSymbolResolves() {
        for descriptor in ModuleRegistry.all {
            let symbol = descriptor.moduleMetadata.sfSymbol
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                            "`\(descriptor.idRaw)` names the symbol `\(symbol)`, which macOS does not have")
        }
    }
}
