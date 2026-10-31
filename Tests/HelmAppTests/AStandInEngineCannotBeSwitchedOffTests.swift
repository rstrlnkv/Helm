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
/// **The switch is driven; the reset is read off the source.** `setEnabled` runs for
/// real on the shared host against a recording descriptor (as
/// `TheHostPutsAModulesOwnItemInTheMenuBarTests` does). `ResetEverything.run()` is not
/// called: with its guard gone it trashes this Mac's Helm folders, forgets the
/// preferences of the running bundle and relaunches. What is pinned there is that the
/// guard on `anyStandsIn` stands before the first step, and the behaviour it asks
/// (`anyStandsIn`) is driven here both ways.
@MainActor
final class AStandInEngineCannotBeSwitchedOffTests: XCTestCase {

    private static let standInID = "test-stand-in-engine"
    private static let ordinaryID = "test-ordinary-engine"

    private final class PageModel {}

    private final class Probe: ModuleEngine {
        let standsIn: Bool
        var willDisableCalls = 0
        var deactivateCalls = 0
        init(standsIn: Bool) { self.standsIn = standsIn }
        func activate() {}
        func willDisable() { willDisableCalls += 1 }
        func deactivate() { deactivateCalls += 1 }
    }

    private class Base: ModuleDescriptor {
        class var id: ModuleID { fatalError() }
        static var metadata: ModuleMetadata {
            ModuleMetadata(id: id, name: "Probe", summary: "", sfSymbol: "gear", permissions: [])
        }
        static let category: ModuleCategory = .utilities
        static let tint = ModuleTint(ordinary: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)),
                                     increasedContrast: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)))
        static let glyph = ShellGlyph.settings
        let engine: Probe
        init(standsIn: Bool) { engine = Probe(standsIn: standsIn) }
        func makeModule(store: NamespacedStore) -> ModuleParts<PageModel> {
            ModuleParts(engine: engine, model: PageModel())
        }
        func menuBar(_ vm: PageModel) -> MenuBarContribution? { nil }
        func settingsPage(_ vm: PageModel) -> AnyView { AnyView(EmptyView()) }
    }
    private final class StandIn: Base {
        override class var id: ModuleID { ModuleID(AStandInEngineCannotBeSwitchedOffTests.standInID) }
    }
    private final class Ordinary: Base {
        override class var id: ModuleID { ModuleID(AStandInEngineCannotBeSwitchedOffTests.ordinaryID) }
    }

    /// The host's store is `UserDefaults.standard`: the keys written are taken back out.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        for id in [Self.standInID, Self.ordinaryID] {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        super.tearDown()
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
        XCTAssertEqual(d.engine.willDisableCalls, 0, "the stand-in was asked to give back what it never took")
        XCTAssertEqual(d.engine.deactivateCalls, 0, "the stand-in was torn down by a refused switch")
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
        XCTAssertEqual(d.engine.willDisableCalls, 1)
        XCTAssertEqual(d.engine.deactivateCalls, 1)
        XCTAssertNil(host.liveModule(Self.ordinaryID))
    }

    /// The reset's guard stands before the first step of the plan, and asks the host.
    func testTheResetRefusesBeforeAnyStep() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/ResetEverything.swift")
        let body = try XCTUnwrap(SwiftSource.body(of: "run", in: source), "ResetEverything.run is gone")
        let guardAt = try XCTUnwrap(body.range(of: "guard !ModuleHost.shared.anyStandsIn"),
                                    "«Reset all settings» no longer asks whether a stand-in is live")
        let loopAt = try XCTUnwrap(body.range(of: "for step in ResetPlan.order"))
        XCTAssertLessThan(guardAt.lowerBound, loopAt.lowerBound,
                          "the guard comes after a step has already run")
        let guardText = String(body[guardAt.lowerBound..<loopAt.lowerBound])
        XCTAssertTrue(guardText.contains("return"), "the guard does not leave `run()`")
    }
}
