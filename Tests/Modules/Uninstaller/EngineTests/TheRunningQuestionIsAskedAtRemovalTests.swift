import XCTest
@testable import Module_Uninstaller_Engine

/// `ScanResult.runningNow` is a reading, stale in both directions by the press,
/// so the question is asked again where the answer is used. This is the rule
/// (`UninstallPlan.verdict`); `TheAppIsAskedAgainAtRemovalTests` is the engine
/// asking it.
final class TheRunningQuestionIsAskedAtRemovalTests: XCTestCase {

    private func app(_ id: String) -> UninstallPlan.RunningApp {
        UninstallPlan.RunningApp(path: "/Applications/\(id).app", bundleID: "com.acme.\(id)")
    }

    /// Nothing is up: the permission is beside the point.
    func testABatchWithNothingRunningProceedsWhateverThePersonAllowed() {
        for allowed in [true, false] {
            XCTAssertEqual(UninstallPlan.verdict(running: [], mayQuit: allowed), .proceed,
                           "a batch with nothing running waited on a permission it does not need "
                           + "(mayQuit: \(allowed))")
        }
    }

    /// Ticked «Force quit and remove anyway»: every app that is up now — not the
    /// ones that were up when the scan ran — is asked to quit first.
    func testAnAllowedForceQuitNamesEveryAppThatIsUpNow() {
        let running = [app("player"), app("editor")]

        XCTAssertEqual(UninstallPlan.verdict(running: running, mayQuit: true),
                       .quitFirst(running),
                       "an app that came up after the review was not asked to quit")
    }

    /// Not ticked: nothing in the whole batch moves, since a leftover carries no
    /// link back to its app and "everything except that bundle" is a
    /// half-uninstall.
    func testAnAppThatIsUpWithNoPermissionRefusesTheWholeBatch() {
        let running = [app("player")]

        XCTAssertEqual(UninstallPlan.verdict(running: running, mayQuit: false),
                       .refuse(running),
                       "a batch holding a running app moved the files around it")
    }
}
