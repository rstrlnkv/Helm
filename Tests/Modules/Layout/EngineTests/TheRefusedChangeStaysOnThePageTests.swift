import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The right to a blind undo and the record of what happened are two different
/// things, and the engine kept them in one field. `undoLast` set `undo = nil`,
/// the state's `lastConversion` read `undo?.event` — so the moment somebody
/// rejected a change, the row describing it and the «Never this word» button
/// vanished together. The button was reachable only for changes the person had
/// NOT rejected, which is exactly where it is least needed.
final class TheRefusedChangeStaysOnThePageTests: XCTestCase {

    func testAnUndoneConversionStaysVisibleAndSaysSo() async {
        let typing = FakeTyping()
        let tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), automatic: true)
        engine.activate()

        tap.type("ghbdtn"); tap.space()
        let converted = await latestLayoutState(engine)
        XCTAssertEqual(converted?.lastConversion?.before, "ghbdtn",
                       "precondition: the conversion reached the page")
        XCTAssertEqual(converted?.lastConversionUndone, false,
                       "precondition: a change not yet rejected is not marked undone")

        engine.undoLast()
        XCTAssertEqual(typing.performed.count, 2,
                       "precondition: the undo actually retyped — otherwise the row "
                       + "below is rightly about the conversion still standing")
        let undone = await latestLayoutState(engine)
        XCTAssertEqual(undone?.lastConversion?.before, "ghbdtn", """
            rejecting a change erased its record: the row and the «Never this \
            word» button vanish exactly when the person has just said the module \
            was wrong about this word.
            """)
        XCTAssertEqual(undone?.lastConversionUndone, true, """
            the record survived but does not say it was taken back — the page \
            would show a change as standing when the person just rejected it.
            """)
        engine.deactivate()
    }
}
