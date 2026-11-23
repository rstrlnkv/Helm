import HelmRuntime
import XCTest
@testable import Module_Launchpad_Engine

/// `SystemLaunchpadAuth` is the one place a lock reaches LocalAuthentication, and a test process must not reach it: an answer
/// of `.success` would mean a fingerprint was asked of the owner, anything else that a dialog could have been shown.
final class TheSuiteDoesNotAskForTouchIDTests: XCTestCase {
    func testTheSystemPortAnswersUnavailableAndShowsNothingInATestProcess() async {
        XCTAssertTrue(TestProcess.isRunning)
        let outcome = await SystemLaunchpadAuth().evaluate(reason: "test")
        XCTAssertEqual(outcome, .unavailable)
    }
}
