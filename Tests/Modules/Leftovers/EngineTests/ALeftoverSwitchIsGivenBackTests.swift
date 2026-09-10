import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// A login item Helm switched off is switched back on when the module is.
///
/// **Why this is a test.** The switch reaches outside both of Helm's folders —
/// `launchctl disable` is a change to the user's own launchd domain that
/// survives a reboot and survives deleting Helm — and for a year nothing put it
/// back, while `ARCHITECTURE.md` described a reset that «hands back what is
/// outside Helm». The give-back is one port call; what was missing was the
/// record of which labels were ours to give back.
///
/// **Why the record and not the system's list.** `disabledLabels()` answers what
/// *the system* has disabled, which includes every switch the person threw in
/// System Settings. Re-enabling those would be Helm undoing decisions that were
/// never Helm's, silently, during a reset.
final class ALeftoverSwitchIsGivenBackTests: XCTestCase {

    /// **Every port is named at every construction** — the default of any one of
    /// them is this Mac's own filesystem or its `launchctl`, and
    /// `EveryEngineNamesItsPortsTests` holds that promise for the whole module.
    /// `home`, `files`, `apps` and `loaded` are inert here: this test drives only
    /// `setDisabled` and `willDisable`, which never reach the scanner.
    private func engine(_ switcher: LeftoversFakeSwitcher,
                        _ store: NamespacedStore) -> LeftoversEngine {
        LeftoversEngine(home: URL(fileURLWithPath: "/Users/x"), files: LeftoversFakeFiles(),
                       apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                       switcher: switcher, store: store)
    }

    func testTheLabelsHelmDisabledAreRecorded() async throws {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = engine(switcher, store)

        await e.setDisabled(true, label: "com.example.agent.one")
        await e.setDisabled(true, label: "com.example.agent.two")

        XCTAssertEqual(store.stringArray("disabledByHelm").sorted(),
                       ["com.example.agent.one", "com.example.agent.two"])
    }

    func testSwitchingOneBackOnLeavesTheRecordWithoutIt() async throws {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = engine(switcher, store)

        await e.setDisabled(true, label: "com.example.agent.one")
        await e.setDisabled(false, label: "com.example.agent.one")

        XCTAssertEqual(store.stringArray("disabledByHelm"), [],
                       "a label given back by hand is no longer ours to give back at reset")
    }

    func testDisablingTheModuleGivesBackEveryLabelItTook() async throws {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = engine(switcher, store)

        await e.setDisabled(true, label: "com.example.agent.one")
        await e.setDisabled(true, label: "com.example.agent.two")
        let beforeGiveBack = switcher.labels.count

        e.willDisable()

        XCTAssertEqual(switcher.labels.count, beforeGiveBack + 2,
                       "each recorded label is asked about a second time — the give-back")
        XCTAssertEqual(store.stringArray("disabledByHelm"), [],
                       "the record is state, not a log: what has been given back is gone from it")
    }

    func testAModuleThatDisabledNothingAsksTheSystemNothing() throws {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        engine(switcher, store).willDisable()
        XCTAssertEqual(switcher.labels, [],
                       "an empty record must not become a sweep over the system's own list")
    }
}
