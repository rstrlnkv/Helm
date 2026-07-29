import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// Defaults matter here: the spin is off unless somebody asked for it, and the
/// two colours have to answer before anybody has picked one.
final class VPNSpinSettingsTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn-test",
                                           backing: InMemoryKeyValueStore()))
    }

    func testTheSpinIsOffUntilItIsAskedFor() {
        XCTAssertFalse(settings().automationSpin)
    }

    func testTheSpinCanBeSwitchedOn() {
        let s = settings()
        s.setAutomationSpin(true)
        XCTAssertTrue(s.automationSpin)
    }

    func testTheTwoColoursHaveDefaultsBeforeAnybodyPicks() {
        XCTAssertEqual(settings().spinTint(for: .connected), "green")
        XCTAssertEqual(settings().spinTint(for: .disconnected), "orange")
    }

    func testEachKindKeepsItsOwnColour() {
        let s = settings()
        s.setSpinTint("purple", for: .connected)
        XCTAssertEqual(s.spinTint(for: .connected), "purple")
        XCTAssertEqual(s.spinTint(for: .disconnected), "orange",
                       "setting one colour must not move the other")
    }
}
