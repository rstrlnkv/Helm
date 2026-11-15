import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **A press already past the page's guard is not allowed to land after the
/// hand-back.** It reads the two agent folders, which takes a moment, and in that
/// moment `willDisable()` can read the record and empty it; the switch that then
/// lands is written into a record nobody reads again.
final class ASwitchInFlightIsGivenBackTests: XCTestCase {
    func testAPressHeldInTheFolderReadIsRefusedOnceTheModuleIsSwitchedOff() async {
        let label = "com.vendor.updater"
        let path = "/Users/x/Library/LaunchAgents/\(label).plist"
        var fake = LeftoversFakeFiles()
        fake.listing["/Users/x/Library/LaunchAgents"] = ["\(label).plist"]
        fake.plists[path] = PlistData(["Label": label])
        let gate = LeftoversGate()
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = LeftoversEngine(home: URL(fileURLWithPath: "/Users/x"),
                                files: LeftoversGatedFiles(fake, gate: gate),
                                apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                switcher: switcher, store: store)

        let press = Task { await e.setDisabled(LeftoversToggle(label: label, path: path, disabled: true)) }
        XCTAssertTrue(gate.waitUntilEntered(), "the press never reached the folder read")
        e.willDisable()
        gate.release()
        await press.value

        XCTAssertEqual(switcher.calls.map(\.label), [], "a switch landed after the hand-back")
        XCTAssertEqual(store.stringArray("disabledByHelm"), [])
    }
}
