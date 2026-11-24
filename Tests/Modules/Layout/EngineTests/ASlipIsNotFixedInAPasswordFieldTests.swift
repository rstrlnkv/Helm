import XCTest
import HelmRuntime
@testable import Module_Layout_Engine

/// A slipped Shift is not repaired in an app's own password field.
///
/// `isSecureInput()` is the cheap system-wide flag; `isSecure()` reads the focused element's role and is the only
/// one that sees a password field in a browser that never escalated. The two answers differ here on purpose: the
/// flag is off, the field is secure. The capital fix must still leave the word alone, whatever else guards the
/// path, and the tap must have seen the word (the dictionary knows `Hello`), so a refusal is the secure answer's.
final class ASlipIsNotFixedInAPasswordFieldTests: XCTestCase {

    private func rig(secureField: Bool) -> (LayoutEngine, FakeTyping, FakeTap) {
        let typing = FakeTyping(), tap = FakeTap(), secure = FakeSecure()
        secure.passwordField = secureField
        let store = layoutStore()
        store.set(true, for: LayoutKey.fixCapitals)
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(),
            translation: FakeTranslation(table: [:]),
            spell: FakeSpell(valid: ["Hello"]),
            secure: secure, activation: FakeActivation(), automatic: true, settings: store)
        engine.activate()
        return (engine, typing, tap)
    }

    func testTheSameSlipIsFixedOutsideAPasswordFieldAndLeftAloneInside() {
        let (open, openTyping, openTap) = rig(secureField: false)
        openTap.type("HEllo"); openTap.space()
        XCTAssertEqual(openTyping.performed.count, 1, "control: the slip is repaired where the field is ordinary")

        let (closed, closedTyping, closedTap) = rig(secureField: true)
        closedTap.type("HEllo"); closedTap.space()
        XCTAssertTrue(closedTyping.performed.isEmpty, "a secure field was rewritten")
        withExtendedLifetime((open, closed)) {}
    }
}
