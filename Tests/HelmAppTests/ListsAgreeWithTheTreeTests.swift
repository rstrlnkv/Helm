import HelmContract
import HelmRuntime
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
/// **Every engine builds in 55 ms with an in-memory store**, measured over all
/// nine before this file was written, so a test may hold the real registry
/// rather than a copy of it. `activate()` is never called: building is what these
/// checks need, and starting nine modules' watchers inside a test is not.
final class ListsAgreeWithTheTreeTests: XCTestCase {

    @MainActor private func engines() -> [(id: String, engine: any ModuleEngine)] {
        // In-memory, never `UserDefaults`: a test that builds nine engines
        // against the real store leaves nine modules' settings behind, and the
        // house rule about harnesses was written after exactly that.
        let backing = InMemoryKeyValueStore()
        return ModuleRegistry.all.map { descriptor in
            (descriptor.idRaw,
             descriptor.makeEngine(store: NamespacedStore(namespace: descriptor.idRaw,
                                                          backing: backing)))
        }
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

    /// **The failure this closes is silent and expensive.** A module in the list
    /// whose engine does not handle the command falls to `default: return
    /// Data()`; the caller decodes nothing, reads `nil`, and logs "no answer".
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
