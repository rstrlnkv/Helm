import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A resize animates the next update, once: the flag is set by the menu's call when it asks for a size the folder lacks, spent by
/// the next update (an answer or not), and never set by a resize that asks for the size the folder has. A plain update, a search, a regrid or a drop do not animate. The curve itself (`HelmMotion.reorder`) is not observable from a
/// test, so the flag is read by reflection.
@MainActor final class TheResizeAnimationFlagIsOneShotTests: XCTestCase {
    private let id = UUID()

    private func armed(_ s: LaunchpadScreenState) -> Bool? {
        Mirror(reflecting: s).children.first { $0.label == "animateNextUpdate" }?.value as? Bool
    }

    private func rig() -> LiftRig {
        let r = LiftRig(self, apps: ["a", "b", "c"], layout: LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: ["a", "b"])), .app("c")]))
        r.state.onResize = { [unowned r] id, large in if let s = r.engine.apply(.resize(id, large: large)) { r.state.update(snapshot: s) } }
        return r
    }

    func testTheFlagIsSetByTheMenuAndSpentByTheNextUpdateOnly() {
        let r = rig()
        XCTAssertEqual(armed(r.state), false, "subject: the flag is readable and off")
        r.state.onResize = nil
        r.state.resize(id, large: true)
        XCTAssertEqual(armed(r.state), true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertEqual(armed(r.state), false, "the update spent it")
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertEqual(armed(r.state), false)
    }

    func testAResizeTheEngineRefusesDoesNotLeaveTheFlagForALaterUpdate() {
        let r = rig()
        r.state.resize(id, large: false)
        XCTAssertEqual(armed(r.state), false, "a resize that changed nothing must not animate the next, unrelated update")
    }
}
