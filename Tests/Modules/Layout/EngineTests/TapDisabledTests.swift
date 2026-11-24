import XCTest
import CoreGraphics
@testable import Module_Layout_Engine

/// macOS switches an event tap off behind the app's back, and says so exactly
/// once — by delivering an event of its own down the tap that is being
/// switched off. Miss it and Layout stops converting words with nothing on
/// screen, nothing in the log, and its own switch still reading "on".
///
/// Two causes, and the remedy differs. `tapDisabledByTimeout` is the system
/// deciding the callback was too slow: the grant is intact and the documented
/// repair is to enable the tap again. Revocation is not that — the grant is
/// gone, re-enabling would fail every time, and the honest thing is to stand
/// down and let the module say it is not watching.
final class TapDisabledTests: XCTestCase {

    func testBothWaysTheSystemDisablesATapAreRecognised() {
        XCTAssertTrue(TapDisabled.disables(.tapDisabledByTimeout))
        XCTAssertTrue(TapDisabled.disables(.tapDisabledByUserInput))
    }

    /// The events the tap exists to read are not the tap being switched off —
    /// without this the first keystroke would be treated as a disabling.
    func testOrdinaryEventsAreNotADisabling() {
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged, .leftMouseDown] {
            XCTAssertFalse(TapDisabled.disables(type), "\(type.rawValue) is ordinary traffic")
        }
    }

    func testATimeoutWithTheGrantStillGivenIsRecoverable() {
        XCTAssertEqual(TapDisabled.response(stillTrusted: true), .enableItAgain)
    }

    /// The revocation case. Re-enabling cannot work without the grant, and a
    /// retry loop against a permission the user has just taken away is the
    /// module arguing with them.
    func testARevokedGrantStandsDown() {
        XCTAssertEqual(TapDisabled.response(stillTrusted: false), .standDown)
    }
}
