import HelmRuntime
import XCTest
@testable import Module_Launchpad_Engine

/// `SystemAppLauncher` is the one place a launch reaches LaunchServices, and a test process must not reach it:
/// Calculator is there on every Mac, so an answer of `true` would mean it was opened on the owner's screen.
final class TheSuiteDoesNotLaunchAppsTests: XCTestCase {
    func testTheSystemLauncherAnswersFalseAndOpensNothingInATestProcess() async {
        XCTAssertTrue(TestProcess.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app"), "the subject needs a real app to refuse")
        let opened = await SystemAppLauncher().open(URL(fileURLWithPath: "/System/Applications/Calculator.app", isDirectory: true))
        XCTAssertFalse(opened)
    }
}
