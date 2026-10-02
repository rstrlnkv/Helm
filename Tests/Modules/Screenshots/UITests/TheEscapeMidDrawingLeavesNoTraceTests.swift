import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Esc and the right click mid-drawing are one door and drop the stroke under the pointer:** the
/// release that follows makes no layer, the bars come back, and the Esc question is asked and
/// answered as the rule says afterwards.
@MainActor
final class TheEscapeMidDrawingLeavesNoTraceTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func build() throws -> (DisplayID, OverlayView) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 1,
                                   image: try XCTUnwrap(context.makeImage()))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []), store: nil) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        let view = try XCTUnwrap(built.view(for: id))
        // One finished rectangle so that the Esc question has something to ask about.
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.line))
        return (id, view)
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private func startLine(_ id: DisplayID) {
        overlay?.mouseDown(on: id, at: CGPoint(x: 120, y: 330), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 400, y: 360), flags: [])
    }

    private func assertDropped(_ id: DisplayID, _ view: OverlayView, _ why: String) {
        XCTAssertTrue(results.isEmpty, "\(why): it closed the editor \(results)")
        XCTAssertNotNil(overlay?.chrome(on: id), "\(why): the bars did not come back at the drop")
        overlay?.mouseUp(on: id)
        XCTAssertEqual(view.drawnShapes.count, 1, "\(why): the release made a layer")
        XCTAssertNotNil(overlay?.chrome(on: id), "\(why): the bars did not come back")
        XCTAssertTrue(view.visiblePlates.isEmpty, "\(why): the drop asked the question")
    }

    func testEscMidDrawingDropsTheStrokeThroughTheOverlay() throws {
        let (id, view) = try build()
        startLine(id)
        XCTAssertEqual(view.drawnShapes.count, 2, "nothing was being drawn, so the drop says nothing")
        overlay?.keyDown(key(53))
        XCTAssertEqual(view.drawnShapes.count, 1, "the draft stayed on the screen")
        assertDropped(id, view, "Esc")
    }

    func testRightClickMidDrawingTakesTheSameDoor() throws {
        let (id, view) = try build()
        startLine(id)
        XCTAssertEqual(view.drawnShapes.count, 2)
        view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                     timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                     clickCount: 1, pressure: 1)!)
        XCTAssertEqual(view.drawnShapes.count, 1, "the draft stayed on the screen")
        assertDropped(id, view, "right click")
    }

    /// The question was armed before the drawing began: a drawing's start withdraws it, so the Esc
    /// that drops the stroke neither closes on the old question nor asks a new one.
    func testEscMidDrawingAfterTheQuestionWasArmedDoesNotCloseNorAsk() throws {
        let (id, view) = try build()
        overlay?.keyDown(key(53)) // asks
        XCTAssertEqual(view.visiblePlates.count, 1, "the first Esc did not ask, so the case below says nothing")
        startLine(id)
        XCTAssertTrue(view.visiblePlates.isEmpty, "starting a drawing left the question up")
        overlay?.keyDown(key(53))
        assertDropped(id, view, "Esc after an armed question")
        // The first Esc after the drop asks (the drawing withdrew the old question)...
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "the Esc after the drop closed on a stale question")
        XCTAssertEqual(view.visiblePlates.count, 1, "the Esc after the drop did not ask")
        // ...and the next closes.
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first else { return XCTFail("the second Esc did not close: \(results)") }
    }

    func testASecondEscAfterTheDropAsksAndTheThirdCloses() throws {
        let (id, view) = try build()
        startLine(id)
        overlay?.keyDown(key(53))
        assertDropped(id, view, "Esc")
        overlay?.keyDown(key(53))
        XCTAssertEqual(view.visiblePlates.count, 1, "the Esc after the drop did not ask")
        XCTAssertTrue(results.isEmpty)
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first else { return XCTFail("did not close: \(results)") }
    }
}
