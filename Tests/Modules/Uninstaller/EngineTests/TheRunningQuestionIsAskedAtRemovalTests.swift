import XCTest
@testable import Module_Uninstaller_Engine

/// **`runningNow` is a reading, and a reading goes stale.**
///
/// The review screen's `running` flag comes from the scan — `ScanResult.runningNow`,
/// read once — and both directions of its staleness are defects. The person quits
/// the app themselves while reading the review, and the button stays dead for
/// good; the person launches it again, and the bundle is moved out from under a
/// live process, which then writes its preferences on exit and puts back exactly
/// the leftovers the uninstall just took (`UninstallerEngine.waitUntilGone` is
/// the paragraph about that, and nothing was consulting it).
///
/// So the question is asked again where the answer is used. This is the rule that
/// says what the answer means; `TheAppIsAskedAgainAtRemovalTests` is the engine
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

    /// Not ticked: nothing moves. **The whole batch**, not merely the running
    /// app's own bundle — the leftovers in the batch carry no link back to the app
    /// they came from, so trashing "everything except that bundle" is precisely
    /// the half-uninstall `waitUntilGone` exists to prevent: the app keeps
    /// running, exits, and writes its preferences back.
    func testAnAppThatIsUpWithNoPermissionRefusesTheWholeBatch() {
        let running = [app("player")]

        XCTAssertEqual(UninstallPlan.verdict(running: running, mayQuit: false),
                       .refuse(running),
                       "a batch holding a running app moved the files around it")
    }
}
