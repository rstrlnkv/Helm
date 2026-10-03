import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A text is a layer when drawing it leaves ink, and what `place` keeps always fits the bounds.** Blank characters
/// outside the categories `isInvisible` lists (a filler, a braille blank, a lone variation selector) leave no layer and
/// no undo step; a cut that ends in a joiner does not fuse with the grapheme after it.
///
/// What it would print if it failed totally: the five blank scalars are placed as layers, and the 300 emoji come out as
/// one grapheme of thousands of scalars.
final class TheTextIsKeptByItsInkAndByItsBoundsTests: XCTestCase {
    private func place(_ text: String) -> (placed: Annotation?, steps: Bool) {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 600, height: 300))
        editing.place(text: text, at: CGPoint(x: 40, y: 50))
        return (editing.layers.first, editing.canUndo)
    }

    func testBlankScalarsLeaveNoLayerAndNoStep() {
        for scalar in ["\u{3164}", "\u{2800}", "\u{FE0F}", "\u{115F}", "\u{034F}", "\u{200B}"] {
            let result = place(scalar)
            XCTAssertNil(result.placed, "U+\(String(scalar.unicodeScalars.first!.value, radix: 16)) was placed")
            XCTAssertFalse(result.steps)
            XCTAssertFalse(AnnotationText.hasInk(scalar))
        }
    }

    func testALetterHasInkAndIsPlaced() {
        XCTAssertTrue(AnnotationText.hasInk("a"))
        XCTAssertEqual(place("a").placed?.text, "a")
    }

    func testAJoinedEmojiStaysWhole() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(place(family).placed?.text, family)
    }

    func testCutsEndingInAJoinerDoNotFuseIntoOneGrapheme() throws {
        // 17 scalars each: a cut at 16 leaves a joiner at the end.
        let grapheme = "👨" + String(repeating: "\u{200D}👨", count: 8)
        XCTAssertEqual(grapheme.unicodeScalars.count, 17)
        XCTAssertEqual(grapheme.count, 1)
        let placed = try XCTUnwrap(place(String(repeating: grapheme, count: 300)).placed?.text)
        XCTAssertTrue(AnnotationText.fits(placed))
    }
}
