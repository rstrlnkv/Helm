import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **Two presses are one at a time.** Each reads the record, adds its label and
/// writes it back; run side by side the later write drops the earlier label, and
/// that label is then disabled with nothing to give it back.
final class TwoPressesLoseNoLabelTests: XCTestCase {
    private func make() -> (LeftoversEngine, LeftoversFakeSwitcher, NamespacedStore) {
        let switcher = LeftoversFakeSwitcher()
        let store = NamespacedStore(namespace: "leftovers.test.\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        let e = LeftoversEngine(home: URL(fileURLWithPath: "/Users/x"), files: LeftoversFakeFiles(),
                                apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                switcher: switcher, store: store)
        return (e, switcher, store)
    }

    func testASecondPressWaitsForTheFirstAndBothLabelsAreRecorded() async {
        let (e, switcher, store) = make()
        let gate = LeftoversGate()
        switcher.gate = gate

        let first = Task { await e.setDisabled(true, label: "com.example.agent.one") }
        XCTAssertTrue(gate.waitUntilEntered(), "the first press never reached the port")
        let second = Task { await e.setDisabled(true, label: "com.example.agent.two") }
        await grace()
        gate.release()
        await first.value
        await second.value

        XCTAssertEqual(switcher.mostConcurrent, 1)
        XCTAssertEqual(store.stringArray("disabledByHelm").sorted(),
                       ["com.example.agent.one", "com.example.agent.two"])
    }

    func testAGiveBackFromAnotherThreadSeesTheLabelOfAPressInFlight() async {
        let (e, switcher, store) = make()
        let gate = LeftoversGate()
        switcher.gate = gate
        let label = "com.example.agent.one"

        let press = Task { await e.setDisabled(true, label: label) }
        XCTAssertTrue(gate.waitUntilEntered(), "the press never reached the port")
        let gaveBack = expectation(description: "willDisable returned")
        DispatchQueue.global().async { e.willDisable(); gaveBack.fulfill() }
        await grace()
        gate.release()
        await press.value
        await fulfillment(of: [gaveBack], timeout: 10)

        XCTAssertEqual(switcher.calls.last?.label, label)
        XCTAssertEqual(switcher.calls.last?.disabled, false, "the label was left disabled")
        XCTAssertEqual(store.stringArray("disabledByHelm"), [])
    }
}
