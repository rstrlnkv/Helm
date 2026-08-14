import HelmTestSupport
import HelmUI
import ServiceManagement
import XCTest
@testable import HelmApp

/// «Open Helm at login» against the only thing that can refuse it.
///
/// The switch was `@State private var launchAtLogin = LoginItem.isEnabled`,
/// written once at construction, whose `onChange` called a method that **caught
/// the throw and discarded it** — while the two permission rows beside it are
/// re-probed on every activation. So if `register()` failed the switch stayed on
/// and Helm did not open at login; if the person removed Helm from System
/// Settings ▸ Login Items with the window open, the switch stayed on then too.
/// It is the first switch anybody touches in this app.
///
/// The family named on 2026-08-12: a local flag standing in for a live external
/// fact, with no reverse channel from the port that knows. `TrashWatch` is the
/// shape this follows — one value from the facts that decide it, rather than a
/// boolean beside a boolean.
@MainActor
final class TheLoginSwitchHearsBackTests: XCTestCase {

    /// The whole finding: a write that threw is not an on switch.
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

    func testBothSentencesAreWrittenInAllEightLanguages() throws {
        for state in [LoginItemState.refused, .needsApproval] {
            let english = try XCTUnwrap(AppStr.loginItemNote(state, language: .en))
            for language in AppLanguage.allCases where language != .en {
                let translated = try XCTUnwrap(AppStr.loginItemNote(state, language: language))
                XCTAssertNotEqual(translated, english,
                                  "\(language.rawValue) fell back to English for \(state)")
            }
        }
        let english = AppStr.openLoginItems(language: .en)
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(AppStr.openLoginItems(language: language), english,
                              "\(language.rawValue) fell back to English for the button")
        }
    }
}
