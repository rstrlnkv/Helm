import HelmTestSupport
import XCTest

/// **The menu bar's once-a-second tick is switched by what is drawn, not left
/// running or left off.**
///
/// A module emits only when its payload changes, so a countdown (ring or text)
/// moves only while `StatusItemController.timerTick` runs. `refreshIcon` must
/// hand it `StatusPlan.wantsSecondTick(appearance)` each time it decides; a tick
/// armed for good wakes every second on a Mac with nothing counting, one never
/// armed freezes the countdown. `StatusPlanTests` pins the predicate; this pins
/// that the controller asks it.
///
/// A scan, because `StatusItemController` owns the real status item and a fake
/// of it would stand for a side that is not a port.
final class TheMenuBarSecondTickFollowsTheAppearanceTests: XCTestCase {

    func testTheTimerTickIsSwitchedByTheAppearance() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/StatusItemController.swift")
        let code = source.split(separator: "\n").map { RepoSource.code(String($0)) }
        XCTAssertTrue(code.contains { $0.contains("timerTick = RepeatingTick") },
                      "precondition: the scan found the tick it is about")
        XCTAssertTrue(code.contains { $0.contains("timerTick.set(active: StatusPlan.wantsSecondTick(appearance))") },
                      "refreshIcon no longer switches the tick by the appearance")
    }
}
