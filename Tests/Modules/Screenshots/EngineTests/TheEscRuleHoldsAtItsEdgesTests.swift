import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The Esc rule at its edges.** The question has no time limit: the value holds it
/// asked until another input withdraws it, so these sit on what is left to go wrong —
/// the same instant, a rearm, and the inputs that withdraw it.
final class TheEscRuleHoldsAtItsEdgesTests: XCTestCase {

    private func armed() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        editing.begin(.arrow, at: CGPoint(x: 10, y: 10))
        editing.drag(to: CGPoint(x: 100, y: 80), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1, "no layer, so the rule below would close at once for another reason")
        XCTAssertEqual(editing.escape(), .armed)
        return editing
    }

    /// Nothing but a second Esc is asked of the value, so there is no interval it could
    /// be too late for: the plate and the rule are the same flag.
    func testTheSecondPressClosesWhateverTheDelayBecauseTheRuleHasNoClock() {
        var editing = armed()
        XCTAssertTrue(editing.isArmed, "the plate was down while the question stood")
        XCTAssertEqual(editing.escape(), .close, "a second press asked again")
    }

    /// A closed question is not left armed for a third press to read.
    func testAfterTheCloseTheNextPressStartsAgain() {
        var editing = armed()
        XCTAssertEqual(editing.escape(), .close)
        XCTAssertEqual(editing.escape(), .close, "with the question still armed a press cannot ask")
    }

    /// Input in between withdraws the question however it comes, and the next Esc asks afresh.
    func testARearmedQuestionIsAskedAfreshAfterAWithdrawal() {
        var editing = armed()
        editing.disarm()
        XCTAssertFalse(editing.isArmed, "the withdrawal left the plate up")
        XCTAssertEqual(editing.escape(), .armed, "a press after a withdrawal closed the picture")
        XCTAssertEqual(editing.escape(), .close)
    }

    /// A placed text is a layer like any other: the first Esc after it asks, and the second closes. (The Esc that ends the
    /// field is the overlay's and never reaches this value: `TheTextFieldTakesTheKeysTheEditorWouldTests`.)
    func testAPlacedTextMakesTheFirstEscAskLikeAnyLayer() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(editing.place(text: "note", at: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(editing.escape(), .armed, "a text on the picture closed it at once")
        XCTAssertEqual(editing.escape(), .close)
    }

    /// An empty text leaves no layer, so the Esc after it finds the picture bare and closes at once.
    func testAnEmptyTextLeavesTheEscRuleWithNothingToAsk() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertFalse(editing.place(text: "  ", at: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(editing.escape(), .close, "an empty text left something for Esc to ask about")
    }

    /// Placing a text is an input: it withdraws a question already asked, and the next Esc asks afresh.
    func testPlacingATextWithdrawsTheQuestion() {
        var editing = armed()
        XCTAssertTrue(editing.place(text: "late", at: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(editing.isArmed, "placing a text left the question up")
        XCTAssertEqual(editing.escape(), .armed)
    }
}

/// The question has no clock in real time either: a pause long enough for any window to lapse.
final class TheEscQuestionOutlastsAPauseTests: XCTestCase {
    func testASecondPressAfterARealPauseStillClosesAndTheQuestionStaysArmed() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        editing.begin(.arrow, at: CGPoint(x: 10, y: 10))
        editing.drag(to: CGPoint(x: 100, y: 80), shift: false)
        editing.end()
        XCTAssertEqual(editing.escape(), .armed)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(editing.isArmed, "the question lapsed during a pause")
        XCTAssertEqual(editing.escape(), .close, "a late second press asked again")
    }
}
