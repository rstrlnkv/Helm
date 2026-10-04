import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The lines through the pointer run across the screen only while ⌥ is held.** The cursor is the system's
/// crosshair; the lines are the option's, and they follow what the last `flagsChanged` said, not the modifiers
/// of whichever event came last: a drag event carries flags too, and a release of ⌥ in the middle of a drag
/// is not seen by a move.
@MainActor
final class TheLinesCrossTheScreenOnlyWhileOptionIsHeldTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func open(mode: CaptureOverlay.Mode = .area) throws -> (display: DisplayID, views: [OverlayView]) {
        overlay?.close()
        let frames = try OverlayRig.frames()
        let id = try XCTUnwrap(frames.first?.id)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), mode: mode) { _ in }
        overlay = built
        XCTAssertTrue(built.build())
        built.mouseMoved(on: id, at: CGPoint(x: 400, y: 300))
        return (id, try frames.map { try XCTUnwrap(built.view(for: $0.id)) })
    }

    func testNoLinesWithoutTheOptionAndLinesWhileItIsHeld() throws {
        let (display, views) = try open()
        XCTAssertFalse(views[0].linesAreDrawn, "lines with no option held")
        overlay?.flagsChanged([.option])
        XCTAssertTrue(views[0].linesAreDrawn, "⌥ is held and there are no lines")
        overlay?.mouseMoved(on: display, at: CGPoint(x: 500, y: 350))
        XCTAssertTrue(views[0].linesAreDrawn, "a move forgot that ⌥ is held")
        overlay?.flagsChanged([])
        XCTAssertFalse(views[0].linesAreDrawn, "the lines stayed after ⌥ went up")
    }

    func testOtherModifiersAreNotTheOption() throws {
        let (_, views) = try open()
        overlay?.flagsChanged([.shift, .command, .control])
        XCTAssertFalse(views[0].linesAreDrawn)
        overlay?.flagsChanged([.shift, .option])
        XCTAssertTrue(views[0].linesAreDrawn, "the control: option among others is the option")
    }

    /// The lines run through the pointer, so they are on its display and on no other.
    func testTheLinesAreOnTheDisplayOfThePointerOnly() throws {
        let (_, views) = try open()
        overlay?.flagsChanged([.option])
        XCTAssertTrue(views[0].linesAreDrawn, "the subject")
        for other in views.dropFirst() { XCTAssertFalse(other.linesAreDrawn, "lines on a display the pointer is not on") }
    }

    /// ⌥ is also "from the centre" for a drag. Letting go of it mid-drag takes the lines away and leaves the
    /// selection, and the dim, as they are.
    func testOptionReleasedInTheMiddleOfADragTakesTheLinesAndKeepsTheSelection() throws {
        let (display, views) = try open()
        overlay?.flagsChanged([.option])
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 300), flags: [.option])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 450, y: 340), flags: [.option])
        XCTAssertTrue(views[0].linesAreDrawn, "the subject: lines through the pointer in a drag")
        XCTAssertTrue(views[0].dimIsDrawn)
        overlay?.flagsChanged([])
        XCTAssertFalse(views[0].linesAreDrawn, "⌥ went up in the drag and the lines stayed")
        XCTAssertTrue(views[0].dimIsDrawn, "the selection went with ⌥")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 480, y: 360), flags: [])
        XCTAssertFalse(views[0].linesAreDrawn, "a drag event without ⌥ brought the lines back")
    }

    /// In window mode ⌥ is the no-shadow click, never the lines; and a held area is edited with no crosshair.
    func testNoLinesInTheWindowModeOrInTheEditor() throws {
        let (windowDisplay, windowViews) = try open(mode: .window)
        overlay?.flagsChanged([.option])
        overlay?.mouseMoved(on: windowDisplay, at: CGPoint(x: 120, y: 120))
        XCTAssertFalse(windowViews[0].linesAreDrawn, "lines over a window pick")
        let (display, views) = try open()
        overlay?.flagsChanged([.option])
        XCTAssertTrue(views[0].linesAreDrawn, "the control: the same flags in the area mode draw them")
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [.option])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 300), flags: [.option])
        overlay?.mouseUp(on: display)
        XCTAssertNotNil(views[0].areaSizePlate, "the subject: the area is being edited")
        XCTAssertFalse(views[0].linesAreDrawn, "lines in the editor")
    }

    /// The overlay is built and rebuilt in one process: ⌥ held for one capture is not held for the next.
    func testANewOverlayStartsWithNoLinesWhateverTheLastOneSaw() throws {
        _ = try open()
        overlay?.flagsChanged([.option])
        overlay?.close()
        let (_, views) = try open()
        XCTAssertFalse(views[0].linesAreDrawn)
    }
}
