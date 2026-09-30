import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The password dialog has three answers and the page has three sentences for
/// them. «Cancel» is the ordinary way it ends and used to read as a failed
/// `mkdir` — a red «Failed» with code 1 over a Mac nothing had touched.
final class ACancelledPasswordIsNotAFailedPrefixTests: XCTestCase {

    private func rigWithTools(reply: PrivilegedOutcome, holds: Bool = false) -> WaitRig {
        let rig = WaitRig(reply: reply, holdsDialog: holds)
        rig.tools.gitExecutable = true
        return rig
    }

    func testADeclinedDialogIsAuthorizationDeclinedWithNoCodeAndNoInstaller() async {
        let rig = rigWithTools(reply: .declined)

        rig.engine.installBrew()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .authorizationDeclined)
        XCTAssertNil(state?.exitCode, "a cancelled dialog was given an exit code")
        XCTAssertTrue(rig.runner.calls.isEmpty, "the installer ran after the person said no")
    }

    /// Root was asked and the script failed: the other named outcome, with the
    /// status of the script.
    func testAFailedPrepIsPrefixNotPreparedWithItsStatus() async {
        let rig = rigWithTools(reply: .failed(1))

        rig.engine.installBrew()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .prefixNotPrepared)
        XCTAssertEqual(state?.exitCode, 1)
        XCTAssertTrue(rig.runner.calls.isEmpty)
    }

    func testAnAcceptedDialogStartsTheInstallerWithTheDeclaredEnvironment() {
        let rig = rigWithTools(reply: .done)

        rig.engine.installBrew()

        XCTAssertEqual(rig.runner.calls.count, 1)
        XCTAssertEqual(rig.runner.calls.first?.env, HomebrewEngine.installerEnvironment)
    }

    /// The installer itself ends non-zero: named, with its code.
    func testAFailedInstallerIsInstallerFailedWithItsCode() async {
        let rig = rigWithTools(reply: .done)

        rig.engine.installBrew()
        rig.runner.finishAll(code: 7)

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .installerFailed)
        XCTAssertEqual(state?.exitCode, 7)
    }

    /// Every ending frees the gate.
    func testEveryNamedEndingFreesTheGate() {
        for reply in [PrivilegedOutcome.declined, .failed(1)] {
            let rig = rigWithTools(reply: reply)
            rig.engine.installBrew()
            rig.engine.installBrew()
            XCTAssertEqual(rig.privileged.scripts.count, 2, "\(reply): the gate stayed shut")
        }
    }

    /// The person presses Stop while the dialog is up and then answers no: the
    /// end they asked for wins over the answer, so the page says «Stopped».
    func testAStopWhileTheDialogIsUpWinsOverACancel() async {
        let rig = rigWithTools(reply: .declined, holds: true)
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            rig.engine.installBrew()
            returned.signal()
        }
        rig.privileged.waitUntilOnScreen()

        rig.engine.stop()
        rig.privileged.answer()

        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success, "installBrew never returned")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped,
                       "a Stop the person pressed was reported as their answer to the dialog")
    }
}
