import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The history's ceiling is held from both sides, and an edit left open is ended by what comes next.**
/// The ceiling is `AnnotationEditing.historyLimit` for undo and for redo alike: an undo walked
/// further than it exists stops, and what it walked over is exactly what redo brings back.
final class TheHistoryCeilingAndTheOpenEditMeetTheirEdgesTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func oneRectangle() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.rectangle, at: CGPoint(x: 150, y: 150), style: .standard)
        editing.drag(to: CGPoint(x: 350, y: 300), shift: false)
        editing.end()
        XCTAssertTrue(editing.press(at: CGPoint(x: 150, y: 225), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected)
        return editing
    }

    /// 300 distinct recolours (the colour alternates, so each one differs from the last), then undo
    /// until it stops and redo until it stops: the two counts are the ceiling, redo ends exactly
    /// where the work was, and the redo side is no deeper than the undo side.
    func testUndoThreeHundredTimesStopsAtTheCeilingAndRedoReturnsExactlyWhatWasWalkedOver() {
        var editing = oneRectangle()
        let colors: [AnnotationColor] = [.blue, .green]
        let base = AnnotationEditing.historyLimit
        XCTAssertLessThan(base, 300, "the feed is 300 edits and means to overrun the ceiling")
        var seen: [[Annotation]] = []
        for step in 0..<300 {
            editing.recolor(colors[step % 2] == editing.layers[0].style.color ? .orange : colors[step % 2])
            seen.append(editing.layers)
        }
        let final = editing.layers
        var undone = 0
        for _ in 0..<300 where editing.canUndo { editing.undo(); undone += 1 }
        XCTAssertEqual(undone, base, "undo kept \(undone) steps, the ceiling is \(base)")
        // The oldest steps are gone: the list undo stops at is the one `base` steps back, not the first.
        XCTAssertEqual(editing.layers, seen[300 - base - 1], "undo stopped at the wrong list")
        var redone = 0
        for _ in 0..<300 where editing.canRedo { editing.redo(); redone += 1 }
        XCTAssertEqual(redone, base, "redo brought back \(redone), the ceiling is \(base)")
        XCTAssertEqual(editing.layers, final)
        XCTAssertTrue(editing.canUndo)
    }

    /// A release that never comes during a resize: ⌘Z does nothing while the edit is open (it must
    /// not tear the list under the gesture), and the next press ends the resize as one step that
    /// undo then takes back.
    func testALostReleaseDuringAResizeThenUndoThenTheNextPressKeepsOneStep() {
        var editing = oneRectangle()
        let original = editing.layers
        var copy = editing
        var setup = 0
        while copy.canUndo { copy.undo(); setup += 1 }
        let handle = editing.layers[0].handles[2].point
        XCTAssertTrue(editing.press(at: handle, tool: nil))
        editing.drag(to: CGPoint(x: handle.x + 30, y: handle.y + 20), shift: false)
        let resized = editing.layers
        XCTAssertNotEqual(resized, original, "the resize moved nothing, so what follows says nothing")
        editing.undo()
        XCTAssertEqual(editing.layers, resized, "⌘Z mid-edit changed the list under the open gesture")
        XCTAssertTrue(editing.isBusy)
        _ = editing.press(at: CGPoint(x: 490, y: 390), tool: nil) // the next press, on nothing
        editing.end()
        XCTAssertFalse(editing.isBusy)
        XCTAssertEqual(editing.layers, resized, "the lost release dropped the resize")
        editing.undo()
        XCTAssertEqual(editing.layers, original, "the resize was not one step")
        var after = editing
        var rest = 0
        while after.canUndo { after.undo(); rest += 1 }
        XCTAssertEqual(rest, setup, "the resize left more than one step")
    }

    /// Esc is the way out of what is in progress: a stroke still under the pointer is what is in
    /// progress, and Esc must not leave it to become a layer on the release that follows.
    func testEscMidDrawingDropsTheDraft() {
        var editing = oneRectangle()
        editing.begin(.line, at: CGPoint(x: 120, y: 120), style: .standard)
        editing.drag(to: CGPoint(x: 300, y: 340), shift: false)
        XCTAssertNotNil(editing.draft, "nothing is being drawn, so Esc below says nothing")
        _ = editing.escape()
        editing.end()
        XCTAssertEqual(editing.layers.count, 1, "Esc left the drawing in progress and the release made it a layer")
    }
}
