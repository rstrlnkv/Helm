import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A text is only what a person can see of it, and the bound is on what costs.** The inputs the text tool's own tests
/// did not feed `place(text:at:style:)`: strings that draw nothing (zero-width, control, joiner characters), strings
/// that are one grapheme and a great many scalars, right-to-left and mixed-direction lines, a tab, the bound's two sides,
/// a point at the area's corner.
///
/// What it would print if it failed totally: a text of nothing visible is a layer (`layers.count == 1`) with a box a
/// person cannot see or hit, and one undo step for nothing.
final class TheTextMeetsInputsNobodyFedItTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
    private let at = CGPoint(x: 40, y: 50)

    private func placed(_ text: String, at point: CGPoint? = nil, style: AnnotationStyle = .standard) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: bounds)
        editing.place(text: text, at: point ?? at, style: style)
        return editing
    }

    func testATextOfNothingAPersonCanSeeLeavesNoLayerAndNoStep() {
        let invisible: [String: String] = [
            "ZWSP": "\u{200B}", "ZWNJ": "\u{200C}", "ZWJ": "\u{200D}", "word joiner": "\u{2060}", "BOM": "\u{FEFF}",
            "LRM": "\u{200E}", "RLM": "\u{200F}", "NUL": "\u{0}", "BEL": "\u{7}", "ESC": "\u{1B}", "DEL": "\u{7F}",
            "soft hyphen": "\u{AD}", "NBSP": "\u{A0}", "ideographic space": "\u{3000}", "narrow NBSP": "\u{202F}",
            "line separator": "\u{2028}", "several": "\u{200B}\u{0}\u{200E} \u{FEFF}",
        ]
        for (name, text) in invisible {
            var editing = AnnotationEditing(bounds: bounds)
            XCTAssertFalse(editing.place(text: text, at: at), "\(name) was placed as a text")
            XCTAssertTrue(editing.layers.isEmpty, "\(name) left a layer")
            XCTAssertFalse(editing.canUndo, "\(name) left an undo step")
        }
    }

    func testTheBoundIsOnGraphemesAtBothSidesOfItAndTheTextKeepsEveryOneOfThem() throws {
        for count in [AnnotationText.maxLength - 1, AnnotationText.maxLength, AnnotationText.maxLength + 1] {
            let text = String(repeating: "я", count: count)
            let kept = try XCTUnwrap(placed(text).layers.first?.text)
            XCTAssertEqual(kept.count, min(count, AnnotationText.maxLength), "\(count) letters")
        }
        let families = String(repeating: "👨‍👩‍👧‍👦", count: AnnotationText.maxLength + 1)
        let kept = try XCTUnwrap(placed(families).layers.first?.text)
        XCTAssertEqual(kept.count, AnnotationText.maxLength)
        XCTAssertEqual(kept, String(families.prefix(AnnotationText.maxLength)), "the cut tore a family apart")
        // A mark joins the letter before it: 256 letters and a mark is still 256 graphemes, and nothing is cut.
        let marked = String(repeating: "e", count: AnnotationText.maxLength) + "\u{301}"
        XCTAssertEqual(try XCTUnwrap(placed(marked).layers.first?.text), marked)
    }

    func testOneGraphemeOfAHugeNumberOfScalarsIsNotALayoutBomb() throws {
        // The bound counts graphemes, so "e" and two hundred thousand marks is one letter under it.
        let bomb = "e" + String(repeating: "\u{301}", count: 200_000)
        XCTAssertEqual(bomb.count, 1)
        let started = Date()
        let editing = placed(bomb)
        let layer = try XCTUnwrap(editing.layers.first)
        _ = layer.frame
        _ = AnnotationText.tile(of: layer, scale: 2)
        let spent = Date().timeIntervalSince(started)
        XCTAssertLessThan(spent, 2, "a one-grapheme text of 200 000 scalars took \(spent) s to place, measure and draw")
        XCTAssertLessThanOrEqual(layer.text?.unicodeScalars.count ?? 0, 4 * AnnotationText.maxLength,
                                 "the bound lets \(layer.text?.unicodeScalars.count ?? 0) scalars through")
    }

    func testRightToLeftAndMixedLinesHaveAFiniteFrameAndAnInkTile() throws {
        for text in ["مرحبا بالعالم", "שלום עולם", "Hello שלום 123 مرحبا", "e\u{301}\u{302}\u{303}", "🇷🇺🇯🇵🏳️‍🌈", "a\tb"] {
            let layer = try XCTUnwrap(placed(text).layers.first, text)
            XCTAssertTrue(layer.frame.width.isFinite && layer.frame.width > 0, "\(text.debugDescription): \(layer.frame)")
            XCTAssertGreaterThan(layer.frame.height, 5)
            let tile = try XCTUnwrap(AnnotationText.tile(of: layer, scale: 2), text)
            XCTAssertTrue(tile.pixels.width > 0)
        }
    }

    func testATabInTheTextIsASpaceTheFieldAndTheLayerAgreeOn() throws {
        // The field has no tab key and a pasted tab would be laid on the field's tab stops while the layer lays its own.
        let layer = try XCTUnwrap(placed("a\tb").layers.first?.text)
        XCTAssertFalse(layer.contains("\t"), "a tab stayed in the one line: \(layer.debugDescription)")
    }

    func testATextAtTheAreasCornersIsKeptNearWhereTheClickWasAndSurvivesUndoAndRedo() throws {
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 600, y: 300), CGPoint(x: 600, y: 0), CGPoint(x: 0, y: 300),
                       CGPoint(x: -50, y: -50), CGPoint(x: 5000, y: 5000)] {
            var editing = placed("corner", at: corner)
            let layer = try XCTUnwrap(editing.layers.first, "\(corner)")
            XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(layer.start), "\(layer.start)")
            editing.undo()
            editing.redo()
            XCTAssertEqual(editing.layers, [layer])
            let moved = layer.translated(by: CGPoint(x: -3, y: -3), within: bounds)
            XCTAssertTrue(moved.frame.origin.x.isFinite && moved.frame.origin.y.isFinite)
        }
    }

    func testAWideTextAgainstTheRightWallCanBeMovedBackIntoTheArea() throws {
        let wide = String(repeating: "W", count: 100)
        let layer = try XCTUnwrap(placed(wide, style: AnnotationStyle(thickness: .thick)).layers.first)
        XCTAssertGreaterThan(layer.frame.width, bounds.width, "the control: the text is wider than the area")
        let back = layer.translated(by: CGPoint(x: -1000, y: 0), within: bounds)
        XCTAssertLessThanOrEqual(back.frame.minX, bounds.minX + 0.001, "a text wider than the area cannot be brought to its left wall")
    }

    func testThicknessAndRecolourOfASelectedTextAreOneStepEachAndUndoRestoresTheFrame() throws {
        var editing = placed("Step me")
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 58), tool: nil))
        editing.end()
        let first = try XCTUnwrap(editing.selected).frame
        editing.setThickness(.thick)
        editing.recolor(.blue)
        XCTAssertGreaterThan(try XCTUnwrap(editing.selected).frame.width, first.width)
        editing.undo()
        editing.undo()
        XCTAssertEqual(editing.layers.first?.frame, first)
        editing.redo()
        editing.redo()
        XCTAssertEqual(editing.layers.first?.style.color, .blue)
        XCTAssertEqual(editing.layers.first?.style.thickness, .thick)
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(editing.layers.first?.text, "Step me")
        editing.undo()
        XCTAssertEqual(editing.layers.first?.frame.origin, CGPoint(x: 40, y: 50))
    }

    func testDeleteOfASelectedTextIsOneStepAndUndoBringsItsWordsBack() throws {
        var editing = placed("gone")
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 58), tool: nil))
        editing.end()
        editing.deleteSelected()
        XCTAssertTrue(editing.layers.isEmpty)
        editing.undo()
        XCTAssertEqual(editing.layers.first?.text, "gone")
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty)
    }
}
