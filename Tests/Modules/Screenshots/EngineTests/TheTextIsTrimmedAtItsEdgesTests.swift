import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A text starts where its first visible letter is.** Blanks, line breaks and invisible characters at either end of a
/// paste are not part of the layer, so the line stands at the click and not hundreds of points to the right of it.
///
/// What it would print if it failed totally: the layer keeps the text as pasted and its frame is wider by the blanks.
final class TheTextIsTrimmedAtItsEdgesTests: XCTestCase {
    private func placed(_ text: String) -> Annotation? {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 600, height: 300))
        editing.place(text: text, at: CGPoint(x: 40, y: 50))
        return editing.layers.first
    }

    func testBlanksAndBreaksAtBothEndsAreDroppedAndTheInnerOnesStayAsSpaces() throws {
        let text = String(repeating: "\n", count: 200) + " \u{200B}hi\tthere\u{FEFF}\n\n  "
        XCTAssertEqual(try XCTUnwrap(placed(text)).text, "hi there")
    }

    func testControlCharactersInsideATextGo() throws {
        XCTAssertEqual(try XCTUnwrap(placed("a\u{0}b\u{7}c\u{1B}d\u{7F}e")).text, "abcde")
    }

    func testAGraphemeKeepsAtMostTheScalarBoundAndItsLetterSurvives() throws {
        let kept = try XCTUnwrap(placed("e" + String(repeating: "\u{301}", count: 5000))).text
        XCTAssertEqual(kept?.unicodeScalars.count, AnnotationText.maxScalarsPerGrapheme)
        XCTAssertEqual(kept?.count, 1)
    }
}
