import AppKit
import CoreGraphics
import Foundation
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **An open pop-over takes Esc before Esc's own rule, and takes a click outside it without letting the click do
/// its usual work.**
///
/// Esc's rule (`AnnotationEditing.escape`) with a layer drawn is: the first press asks, the second closes the editor.
/// With the pop-over open the first Esc closes the pop-over and nothing else, so the rule's two presses come after it:
/// the structure asked here is that the pop-over consumes exactly one Esc, against a control run with none open. A
/// click outside is checked against the same gesture with the pop-over closed, which draws: the pen's stroke is
/// what "does nothing else" means. Names as in `ThePopoverEditsTheChosenToolsOwnStyleTests`.
@MainActor
final class TheOpenPopoverTakesEscAndAClickOutsideTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    /// An area, one rectangle drawn in it, the Pen chosen; the pop-over opened when asked.
    private func build(open: Bool) throws -> (DisplayID, OverlayView, CaptureOverlay) {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        let view = try XCTUnwrap(built.view(for: id))
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.pen))
        if open {
            built.perform(.thicknessAndOpacity(anchorX: 300))
            XCTAssertTrue(built.popoverIsOpen, "control: the pop-over is open for the test")
        }
        XCTAssertEqual(view.drawnShapes.count, 1, "control: one layer to ask about")
        return (id, view, built)
    }

    private func esc() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    // MARK: Esc

    func testControlWithNoPopoverEscAsksAndTheSecondEscCloses() throws {
        let (_, _, overlay) = try build(open: false)
        overlay.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "the first Esc only asks")
        overlay.keyDown(esc())
        XCTAssertEqual(results.count, 1, "the second Esc closes the editor: the rule the pop-over is measured against")
    }

    func testEscClosesThePopoverBeforeEscsOwnRuleAndTheRuleStillHasItsTwoPresses() throws {
        let (id, _, overlay) = try build(open: true)
        overlay.keyDown(esc())
        XCTAssertFalse(overlay.popoverIsOpen, "Esc left the pop-over open")
        XCTAssertTrue(results.isEmpty, "the Esc that closed the pop-over closed the editor")
        XCTAssertNotNil(overlay.chrome(on: id), "the palette is still up")
        overlay.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "the pop-over's Esc was also the rule's first press: the second closed the editor")
        overlay.keyDown(esc())
        XCTAssertEqual(results.count, 1, "the rule's own second press closes the editor")
    }

    func testARepeatOfEscDoesNotCloseThePopoverTwiceOverIntoTheRule() throws {
        let (_, _, overlay) = try build(open: true)
        let held = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: true, keyCode: 53)!
        overlay.keyDown(esc())
        for _ in 0..<5 { overlay.keyDown(held) }
        XCTAssertTrue(results.isEmpty, "a held Esc is one press")
        overlay.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "a held Esc asked the rule's question for the next press")
    }

    func testTheRightClickIsEscsDoorAndClosesThePopoverTheSameWay() throws {
        let (_, view, overlay) = try build(open: true)
        view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertFalse(overlay.popoverIsOpen)
        XCTAssertTrue(results.isEmpty)
        view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertTrue(results.isEmpty, "the first right click was the rule's press as well")
    }

    // MARK: a click outside

    private func stroke(_ overlay: CaptureOverlay, on id: DisplayID) {
        overlay.mouseDown(on: id, at: CGPoint(x: 150, y: 300), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 400, y: 330), flags: [])
        overlay.mouseUp(on: id)
    }

    func testControlTheSameGestureDrawsWhenNoPopoverIsOpen() throws {
        let (id, view, overlay) = try build(open: false)
        stroke(overlay, on: id)
        XCTAssertEqual(view.drawnShapes.count, 2, "the control: a Pen drag over the area is a stroke")
    }

    func testAClickOutsideClosesItAndDrawsNothing() throws {
        let (id, view, overlay) = try build(open: true)
        let before = try XCTUnwrap(overlay.chrome(on: id)?.palette)
        stroke(overlay, on: id)
        XCTAssertFalse(overlay.popoverIsOpen, "a click on the picture left the pop-over open")
        XCTAssertEqual(view.drawnShapes.count, 1, "the click that closed it also began a stroke")
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(overlay.chrome(on: id)?.palette, before, "the palette moved")
        // The next gesture is an ordinary one again.
        stroke(overlay, on: id)
        XCTAssertEqual(view.drawnShapes.count, 2, "after the pop-over closed, the Pen draws")
    }

    func testAClickOutsideTheAreaClosesItAndLeavesTheAreaAlone() throws {
        let (id, view, overlay) = try build(open: true)
        let before = try XCTUnwrap(overlay.chrome(on: id)?.palette)
        overlay.mouseDown(on: id, at: CGPoint(x: 800, y: 700), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 900, y: 760), flags: [])
        overlay.mouseUp(on: id)
        XCTAssertFalse(overlay.popoverIsOpen)
        XCTAssertEqual(overlay.chrome(on: id)?.palette, before, "the click outside the area moved or replaced it")
        XCTAssertEqual(view.drawnShapes.count, 1)
        XCTAssertTrue(results.isEmpty)
    }

    func testAClickOnThePopoverKeepsItOpen() throws {
        let (id, view, overlay) = try build(open: true)
        let popover = try XCTUnwrap(overlay.chrome(on: id)?.popover)
        let middle = CGPoint(x: popover.midX, y: popover.midY)
        overlay.mouseDown(on: id, at: middle, flags: [])
        overlay.mouseUp(on: id)
        XCTAssertTrue(overlay.popoverIsOpen, "a press on the pop-over's own body closed it")
        XCTAssertEqual(view.drawnShapes.count, 1, "the press went through to the picture")
        XCTAssertTrue(overlay.chrome(on: id)?.covers(middle) == true)
    }
}
