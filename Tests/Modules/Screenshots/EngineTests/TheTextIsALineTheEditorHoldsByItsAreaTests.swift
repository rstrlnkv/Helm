import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A text is one line, placed in one undo step, held by its area and by no handle.** `place(text:at:style:)` is the one
/// entry that bounds it; its frame is the line's own room from where it starts, so a step that changes the font moves the
/// frame with it; a click between two of its letters is on it; a change of its words is an edit a person can see.
final class TheTextIsALineTheEditorHoldsByItsAreaTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
    private let at = CGPoint(x: 40, y: 50)

    private func placed(_ text: String, style: AnnotationStyle = .standard) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: bounds)
        editing.place(text: text, at: at, style: style)
        return editing
    }

    func testAPlacedTextIsOneLayerAndOneStepAndUndoTakesItAway() throws {
        var editing = placed("Hello")
        let layer = try XCTUnwrap(editing.layers.first, "nothing was placed, so the steps below say nothing")
        XCTAssertEqual(layer.tool, .text)
        XCTAssertEqual(layer.text, "Hello")
        XCTAssertEqual(layer.start, at)
        XCTAssertTrue(editing.canUndo)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "one undo did not remove the placed text")
        XCTAssertFalse(editing.canUndo, "placing the text took more than one step")
        editing.redo()
        XCTAssertEqual(editing.layers.first?.text, "Hello")
    }

    func testAnEmptyOrBlankTextLeavesNoLayerAndNoStep() {
        for text in ["", " ", "   \t ", "\n", " \n \n"] {
            var editing = AnnotationEditing(bounds: bounds)
            XCTAssertFalse(editing.place(text: text, at: at), "\(text.debugDescription) was placed")
            XCTAssertTrue(editing.layers.isEmpty)
            XCTAssertFalse(editing.canUndo, "\(text.debugDescription) left an undo step")
        }
        var editing = AnnotationEditing(bounds: bounds)
        XCTAssertFalse(editing.place(text: "x", at: CGPoint(x: CGFloat.nan, y: 1)), "a point that is no number placed a text")
        XCTAssertTrue(editing.layers.isEmpty)
        XCTAssertTrue(placed(" a  b ").layers.first?.text == "a  b", "the control: a text with a letter in it keeps its inner spaces, not the outer")
    }

    func testTheTextIsBoundedAtTheEntryByGraphemesAndHasNoBreak() throws {
        // A flag is two scalars and one grapheme; the bound counts what a person sees as one letter.
        let flags = String(repeating: "🇷🇺", count: AnnotationText.maxLength + 40)
        let bounded = try XCTUnwrap(placed(flags).layers.first?.text)
        XCTAssertEqual(bounded.count, AnnotationText.maxLength)
        XCTAssertEqual(AnnotationText.maxLength, 256)
        let two = try XCTUnwrap(placed("one\ntwo\r\nthree").layers.first?.text)
        XCTAssertEqual(two, "one two three")
        XCTAssertFalse(two.contains { $0.isNewline }, "a break stayed in a one-line text: \(two.debugDescription)")
    }

    func testTheFrameIsTheLinesRoomFromWhereItStartsAndFollowsTheStep() throws {
        let sizes = try AnnotationThickness.allCases.map { step -> CGSize in
            let layer = try XCTUnwrap(placed("Hello, Helm", style: AnnotationStyle(thickness: step)).layers.first)
            XCTAssertEqual(layer.frame.origin, at, "\(step)")
            XCTAssertEqual(layer.frame.size, AnnotationText.size(of: layer))
            return layer.frame.size
        }
        XCTAssertLessThan(sizes[0].width, sizes[1].width)
        XCTAssertLessThan(sizes[1].width, sizes[2].width, "a larger step did not make a longer line")
        XCTAssertLessThan(sizes[0].height, sizes[2].height)
        // A step change on the placed text is an edit of it, and the frame it is held by moves with it.
        var editing = placed("Hello, Helm")
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 58), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "the press on the text selected nothing")
        let before = try XCTUnwrap(editing.selected).frame
        editing.setThickness(.thick)
        let after = try XCTUnwrap(editing.selected).frame
        XCTAssertEqual(after.origin, before.origin)
        XCTAssertGreaterThan(after.width, before.width, "the frame stayed at the old size")
        editing.undo()
        XCTAssertEqual(editing.layers.first?.frame, before, "the step was not one undo step")
    }

    func testTheTextHasNoHandleAndAClickBetweenItsLettersIsOnIt() throws {
        let editing = placed("A B", style: AnnotationStyle(thickness: .thick))
        let layer = try XCTUnwrap(editing.layers.first)
        XCTAssertTrue(layer.handles.isEmpty, "a text offers handles")
        XCTAssertNil(layer.resized(.bottomRight, to: CGPoint(x: 300, y: 200)), "a text was resized")
        let middle = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        XCTAssertTrue(AnnotationHit.hits(layer, at: middle))
        XCTAssertTrue(editing.takes(at: middle))
        XCTAssertFalse(editing.takes(at: CGPoint(x: 400, y: 250)), "the control: bare picture is not on the text")
        XCTAssertFalse(AnnotationHit.hits(layer, at: CGPoint(x: layer.frame.maxX + 30, y: layer.frame.midY)))
    }

    func testAMoveCarriesTheTextAndItsWordsThroughEveryEdit() throws {
        let editing = placed("Привет")
        let layer = try XCTUnwrap(editing.layers.first)
        let moved = layer.translated(by: CGPoint(x: 25, y: 10), within: bounds)
        XCTAssertEqual(moved.text, "Привет")
        XCTAssertEqual(moved.start, CGPoint(x: 65, y: 60))
        XCTAssertEqual(moved.frame.size, layer.frame.size)
        var style = layer.style
        style.thickness = .thin
        XCTAssertEqual(layer.restyled(style).text, "Привет")
        // The frame stays inside the area when it is moved against a wall.
        let wall = layer.translated(by: CGPoint(x: 5000, y: 0), within: bounds)
        XCTAssertLessThanOrEqual(wall.frame.maxX, bounds.maxX + 0.001, "the text left the area through its right wall")
    }

    func testARecolourOfATextIsOneStepAndUndoBringsTheUntouchedInkBack() throws {
        var editing = placed("ink")
        XCTAssertTrue(editing.press(at: CGPoint(x: 45, y: 55), tool: nil))
        editing.end()
        let before = editing.layers
        XCTAssertNil(before[0].style.color)
        editing.recolor(.blue)
        XCTAssertEqual(editing.layers[0].style.color, .blue)
        XCTAssertEqual(editing.layers[0].text, "ink", "the recolour lost the words")
        editing.recolor(.green)
        editing.undo()
        editing.undo()
        XCTAssertEqual(editing.layers, before, "undo did not bring the untouched ink back")
    }

    func testAChangeOfTheWordsIsAnEditAPersonCanSee() throws {
        let one = Annotation(tool: .text, start: at, end: at, text: "one", id: 1)
        let two = Annotation(tool: .text, start: at, end: at, text: "two", id: 1)
        XCTAssertFalse(one.looksLike(two), "a text with other words looks the same as before")
        XCTAssertTrue(one.looksLike(one))
        XCTAssertNotEqual(one, two)
    }

    func testAPressOnBarePictureLetsGoOfTheSelection() throws {
        var editing = placed("note")
        editing.begin(.rectangle, at: CGPoint(x: 300, y: 100))
        editing.drag(to: CGPoint(x: 360, y: 160), shift: false)
        editing.end()
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 58), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "nothing was selected, so letting go says nothing")
        let steps = editing.canUndo
        editing.deselect()
        XCTAssertNil(editing.selected)
        XCTAssertEqual(editing.canUndo, steps)
    }
}
