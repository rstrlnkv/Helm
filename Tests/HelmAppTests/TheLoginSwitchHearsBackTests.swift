import HelmTestSupport
import HelmUI
import ServiceManagement
import XCTest
@testable import HelmApp
import HelmAppStrings

/// «Open Helm at login» against the only thing that can refuse it.
///
/// The switch shows what the system says, not what Helm last tried: a
/// `register()` that threw is not on, and Helm removed from System Settings ▸
/// Login Items with the window open turns the switch off. A local flag
/// standing in for a live external fact has no reverse channel from the port
/// that knows. `TrashWatch` is the shape this follows: one value from the
/// facts that decide it, rather than a boolean beside a boolean.
@MainActor
final class TheLoginSwitchHearsBackTests: XCTestCase {

    /// A write that threw is not an on switch.
    func testARefusedRegistrationIsNotAnOnSwitch() {
        let state = LoginItemState.state(status: .notRegistered, refused: true)
        XCTAssertEqual(state, .refused)
        XCTAssertFalse(state.isOn,
                       "the switch stays on while Helm does not open at login, which is the "
                       + "defect this state exists to make impossible")
    }

    /// Registered and waiting on the person is neither on nor off, and saying
    /// «on» is the same lie in a quieter voice.
    func testWaitingForApprovalIsItsOwnState() {
        let state = LoginItemState.state(status: .requiresApproval, refused: false)
        XCTAssertEqual(state, .needsApproval)
        XCTAssertTrue(state.isOn, "the person did ask for it; what is missing is macOS's answer")
    }

    /// The system has the last word, not the last thing Helm tried. A refusal
    /// that is followed by an enabled registration — the person allowed it in
    /// System Settings — is history.
    func testTheSystemsAnswerOutranksTheRefusalHelmRemembers() {
        XCTAssertEqual(LoginItemState.state(status: .enabled, refused: true), .on)
        XCTAssertEqual(LoginItemState.state(status: .requiresApproval, refused: true),
                       .needsApproval)
    }

    func testAnUnregisteredItemNobodyAskedForIsSimplyOff() {
        XCTAssertEqual(LoginItemState.state(status: .notRegistered, refused: false), .off)
        XCTAssertEqual(LoginItemState.state(status: .notFound, refused: false), .off)
        XCTAssertFalse(LoginItemState.state(status: .notRegistered, refused: false).isOn)
    }

    /// Two of the four states have something to say, and two have nothing —
    /// a caption under an ordinary switch is a caption nobody reads.
    func testOnlyTheTwoStatesThatNeedASentenceHaveOne() {
        XCTAssertNil(AppStr.loginItemNote(.on))
        XCTAssertNil(AppStr.loginItemNote(.off))
        XCTAssertNotNil(AppStr.loginItemNote(.refused))
        XCTAssertNotNil(AppStr.loginItemNote(.needsApproval))
    }

    /// Switching off from «waiting for approval» must unregister, or the switch
    /// springs back on and Reset leaves the registration.
    func testSwitchingOffGivesBackARegistrationWaitingForApproval() {
        XCTAssertTrue(LoginItem.unregisters(from: .enabled))
        XCTAssertTrue(LoginItem.unregisters(from: .requiresApproval))
        XCTAssertFalse(LoginItem.unregisters(from: .notRegistered))
        XCTAssertFalse(LoginItem.unregisters(from: .notFound))
    }

    /// The write path itself: off from «waiting for approval» calls unregister.
    func testRequestingOffFromWaitingForApprovalCallsUnregister() throws {
        var unregistered = 0, registered = 0
        try LoginItem.request(false, status: .requiresApproval,
                              register: { registered += 1 }, unregister: { unregistered += 1 })
        XCTAssertEqual(unregistered, 1)
        XCTAssertEqual(registered, 0)
        try LoginItem.request(false, status: .notRegistered,
                              register: { registered += 1 }, unregister: { unregistered += 1 })
        XCTAssertEqual(unregistered, 1)
    }

    /// The other branch of the same seam: on registers unless already enabled.
    func testRequestingOnRegistersUnlessAlreadyEnabled() throws {
        for (status, expected) in [(SMAppService.Status.notRegistered, 1),
                                   (.enabled, 0),
                                   (.requiresApproval, 1)] {
            var registered = 0, unregistered = 0
            try LoginItem.request(true, status: status,
                                  register: { registered += 1 }, unregister: { unregistered += 1 })
            XCTAssertEqual(registered, expected, "\(status)")
            XCTAssertEqual(unregistered, 0, "\(status)")
        }
    }
}
