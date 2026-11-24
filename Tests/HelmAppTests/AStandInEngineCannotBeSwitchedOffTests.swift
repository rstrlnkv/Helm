import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **An engine that stands in for a module's real one must not be able to write the module's real "off".**
///
/// A stand-in (`ModuleEngine.standsIn`) is an engine that replaces the real one while
/// something else is shown or run: it holds no assertion and installed no `sudoers` rule.
/// If the person's switch reached the host's own store while it ran, the real
/// `enabled` key would say "off" and `willDisable()` would ask the stand-in to give
/// back what the real engine took — nothing — so the next ordinary launch would find
/// the module off, with the passwordless `pmset` rule in `/etc/sudoers.d` or sleep
/// still disabled and no engine alive to recover either. «Reset all settings» is the
/// same defect through another door: it would forget the preferences that say the
/// module ran.
///
/// **Both are driven.** `setEnabled` runs for real on the shared host against a
/// recording descriptor (as `TheHostPutsAModulesOwnItemInTheMenuBarTests` does). The
/// reset runs through `ResetEverything.run(standInIsLive:perform:)` with a recorder
/// for `perform`: the real steps trash this Mac's Helm folders, forget the preferences
/// of the running bundle and relaunch. `anyStandsIn`, the answer it is given, is
/// driven here both ways.
@MainActor
final class AStandInEngineCannotBeSwitchedOffTests: XCTestCase {

    private static let standInID = "test-stand-in-engine"
    private static let ordinaryID = "test-ordinary-engine"

    private final class PageModel {}

    private class Base: StandInDescriptor {
        class var id: ModuleID { fatalError() }
        let engine: FakeEngine
        init(standsIn: Bool) { engine = FakeEngine(standsIn: standsIn) }
        func makeModule(store: NamespacedStore) -> ModuleParts<PageModel> {
            ModuleParts(engine: engine, model: PageModel())
        }
    }
    private final class StandIn: Base {
        override class var id: ModuleID { ModuleID(AStandInEngineCannotBeSwitchedOffTests.standInID) }
    }
    private final class Ordinary: Base {
        override class var id: ModuleID { ModuleID(AStandInEngineCannotBeSwitchedOffTests.ordinaryID) }
    }

    /// The host's store is `UserDefaults.standard`: the keys written are taken back out.
    override func tearDown() async throws {
        ModuleHost.shared.shutdown()
        for id in [Self.standInID, Self.ordinaryID] {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        try await super.tearDown()
    }

    private func enabledKey(_ id: String) -> Any? {
        UserDefaults.standard.object(forKey: "module.\(id).enabled")
    }

    func testSwitchingAStandInOffWritesNothingAndAsksNothing() {
        let d = StandIn(standsIn: true)
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        XCTAssertNotNil(host.liveModule(Self.standInID), "the stand-in never went live; nothing below proves anything")
        XCTAssertEqual(enabledKey(Self.standInID) as? Bool, true, "precondition: switching on records on")

        host.setEnabled(d, false)

        XCTAssertEqual(enabledKey(Self.standInID) as? Bool, true, """
            switching a stand-in off wrote "off" into the real store: the next ordinary launch \
            finds the module off, with whatever the real engine had taken left and no engine to recover it.
            """)
        XCTAssertEqual(d.engine.willDisables, 0, "the stand-in was asked to give back what it never took")
        XCTAssertEqual(d.engine.deactivations, 0, "the stand-in was torn down by a refused switch")
        XCTAssertNotNil(host.liveModule(Self.standInID), "the refused switch still dropped the engine")
        XCTAssertTrue(host.anyStandsIn, "the host does not say a stand-in is live, so the reset cannot refuse")
    }

    /// Control: the refusal is about `standsIn`, not a dead switch.
    func testAnOrdinaryEngineIsStillSwitchedOff() {
        let d = Ordinary(standsIn: false)
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        XCTAssertNotNil(host.liveModule(Self.ordinaryID))
        XCTAssertFalse(host.anyStandsIn, "an ordinary engine was counted as a stand-in")

        host.setEnabled(d, false)

        XCTAssertEqual(enabledKey(Self.ordinaryID) as? Bool, false, "the person's off was not recorded")
        XCTAssertEqual(d.engine.willDisables, 1)
        XCTAssertEqual(d.engine.deactivations, 1)
        XCTAssertNil(host.liveModule(Self.ordinaryID))
    }

    /// A live stand-in refuses the reset before its first step.
    func testTheResetRefusesBeforeAnyStep() {
        var performed: [ResetPlan.Step] = []
        ResetEverything.run(standInIsLive: true) { performed.append($0) }
        XCTAssertEqual(performed, [], "a step ran while a stand-in engine was live")
    }
}
