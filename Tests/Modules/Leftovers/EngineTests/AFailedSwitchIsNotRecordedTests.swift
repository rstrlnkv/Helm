import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **The record is what launchd accepted, not what was asked.**
///
/// A switch launchd refused, written down as Helm's, would be enabled at the
/// give-back; one that timed out is the opposite risk, a disabled label with no
/// record that nothing would ever give back. `SwitchAnswer` carries the three
/// cases.
final class AFailedSwitchIsNotRecordedTests: XCTestCase {
    private let one = "com.example.agent.one"
    private let two = "com.example.agent.two"

    private func engine(_ switcher: LeftoversFakeSwitcher, _ store: NamespacedStore) -> LeftoversEngine {
        LeftoversEngine(home: URL(fileURLWithPath: "/Users/x"), files: LeftoversFakeFiles(),
                        apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                        switcher: switcher, store: store)
    }

    func testARefusedDisableLeavesTheRecordUnchanged() async {
        let switcher = LeftoversFakeSwitcher()
        let store = freshLeftoversStore()
        store.set([two], for: "disabledByHelm")
        switcher.answers[one] = .refused

        await engine(switcher, store).setDisabled(true, label: one)

        XCTAssertEqual(store.stringArray("disabledByHelm"), [two])
    }

    func testAnEnableThatFailsAtTheGiveBackKeepsExactlyThatLabel() async {
        let switcher = LeftoversFakeSwitcher()
        let store = freshLeftoversStore()
        let e = engine(switcher, store)
        await e.setDisabled(true, label: one)
        await e.setDisabled(true, label: two)
        switcher.answers[two] = .refused

        e.willDisable()

        XCTAssertEqual(store.stringArray("disabledByHelm"), [two])
    }

    func testADisableThatTimedOutIsRecordedBecauseItMayHaveLanded() async {
        let switcher = LeftoversFakeSwitcher()
        let store = freshLeftoversStore()
        switcher.answer = .unknown

        await engine(switcher, store).setDisabled(true, label: one)

        XCTAssertEqual(store.stringArray("disabledByHelm"), [one])
    }
}
