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
    /// The coordinator then wakes every minute, spends a day's budget per tick,
    /// and nothing anywhere says the module never had a scan to run.
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
