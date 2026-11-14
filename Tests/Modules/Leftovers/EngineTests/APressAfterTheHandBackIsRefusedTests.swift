import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// The engine's latch is the last word, behind the page's `stopped`: a press that
/// arrives after `willDisable()` (the window Reset all settings leaves before the
/// relaunch) reaches no `launchctl` and writes no record.
final class APressAfterTheHandBackIsRefusedTests: XCTestCase {
    func testAPressAfterWillDisableSwitchesNothingAndRecordsNothing() async {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = LeftoversEngine(home: URL(fileURLWithPath: "/Users/x"), files: LeftoversFakeFiles(),
                                apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                switcher: switcher, store: store)

        e.willDisable()
        await e.setDisabled(true, label: "com.example.agent.one")

        XCTAssertEqual(switcher.calls.map(\.label), [])
        XCTAssertEqual(store.stringArray("disabledByHelm"), [])
    }
}
