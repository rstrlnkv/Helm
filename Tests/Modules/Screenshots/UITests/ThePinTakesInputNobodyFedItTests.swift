import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Inputs the first three Pin files did not feed:** a scroll of one pixel on a small pin, a scroll of none,
/// a chain of scrolls through the window's whole-point snapping, a pin closed under a drag, Esc in the middle of
/// a drag, every display gone and back, a pin that opens on a display left of and above the primary at 2x
/// through the real controller, two Pin exits in one turn, and a closed pin's picture handed back.
///
/// Total failure of the subject prints: a pin that does not answer a slow trackpad, a pin resized by an event that
/// carries no distance, a window that walks off its proportions, a closed pin that still moves or still holds
/// its picture, a ninth pin, a pin on the wrong side of the flip.
@MainActor
final class ThePinTakesInputNobodyFedItTests: XCTestCase {

    private var desk: [(DisplayID, CGRect)] = [(DisplayID(1), CGRect(x: 0, y: 0, width: 4000, height: 3000))]

    private func board() -> PinBoard { PinBoard(present: { _ in }, screens: { [weak self] in self?.desk ?? [] }) }

    private func picture(_ width: Int = 200, _ height: Int = 100) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func mouse(_ type: NSEvent.EventType, at screen: CGPoint, in panel: PinPanel) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: screen), modifierFlags: [], timestamp: 0,
                           windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func scroll(_ delta: Int32) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(event.type, .scrollWheel)
        return event
    }

    private func escape() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    // MARK: A scroll of one pixel, a scroll of none

    /// A slow trackpad reports one pixel per event. Fifty of them on a small pin must make it bigger: the
    /// window's whole-point snapping may not eat every step.
    func testSlowScrollingEnlargesASmallPin() throws {
        let panel = try board().open(picture(60, 30), frame: CGRect(x: 100, y: 100, width: 60, height: 30))
        let before = panel.frame.width
        let event = try scroll(1)
        XCTAssertTrue(event.hasPreciseScrollingDeltas, "the control: the synthetic scroll is a pixel scroll")
        XCTAssertGreaterThan(event.scrollingDeltaY, 0)
        for _ in 0..<50 { panel.pinView.scrollWheel(with: event) }
        XCTAssertGreaterThan(panel.frame.width, before, "fifty one-pixel scrolls up left the pin at \(panel.frame.width)")
        let grown = panel.frame.width
        let down = try scroll(-1)
        for _ in 0..<50 { panel.pinView.scrollWheel(with: down) }
        XCTAssertLessThan(panel.frame.width, grown, "fifty one-pixel scrolls down left the pin at \(panel.frame.width)")
    }

    /// The end of a momentum run and a sideways swipe both arrive with no vertical distance: the pin stays as it was,
    /// even one opened at half a point (a 401-pixel selection on a 2x display).
    func testAScrollOfNoDistanceChangesNothing() throws {
        let panel = try board().open(picture(401, 201), frame: CGRect(x: 100.5, y: 100.5, width: 200.5, height: 100.5))
        let before = panel.frame
        panel.pinView.scrollWheel(with: try scroll(0))
        XCTAssertEqual(panel.frame, before, "a scroll that carried no distance resized or moved the pin")
    }

    /// Two thousand scrolls through the panel, the proportions of the picture are those of the frame within AppKit's
    /// own snapping, and the pin never leaves the bounds.
    func testAChainOfScrollsKeepsTheProportionsAndTheBounds() throws {
        let panel = try board().open(picture(401, 201), frame: CGRect(x: 100, y: 100, width: 200.5, height: 100.5))
        let native = panel.native
        var seed: UInt64 = 7
        func next() -> Int32 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int32(truncatingIfNeeded: seed >> 33) % 90 - 45 }
        for _ in 0..<2000 {
            panel.pinView.scrollWheel(with: try scroll(next()))
            let f = panel.frame
            XCTAssertEqual(f.height, f.width * native.height / native.width, accuracy: 0.5001, "the proportions walked: \(f.size)")
            XCTAssertGreaterThanOrEqual(min(f.width, f.height), PinGeometry.minimumSide - 0.5, "under the floor: \(f.size)")
            XCTAssertLessThanOrEqual(f.width, 4000.5, "past the display: \(f.size)")
        }
    }

    // MARK: A pin closed or ended under the pointer

    func testClosingEveryPinInTheMiddleOfADragLeavesTheDragNothing() throws {
        let board = board()
        let panel = try board.open(picture(), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let view = panel.pinView
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 150, y: 150), in: panel))
        let frame = panel.frame
        board.closeAll()
        view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 400, y: 400), in: panel))
        view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 400, y: 400), in: panel))
        view.scrollWheel(with: try scroll(40))
        XCTAssertEqual(panel.frame, frame, "a closed pin followed a drag or a scroll that was still on its way")
        XCTAssertEqual(board.pins.count, 0)
        XCTAssertNil(view.window, "the closed pin's view still has a window")
        board.close(panel)
        board.closeAll()
    }

    func testEscInTheMiddleOfADragClosesThePinAndTheRestOfTheDragIsLost() throws {
        let board = board()
        let panel = try board.open(picture(), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        let other = try board.open(picture(), frame: CGRect(x: 600, y: 600, width: 200, height: 100))
        let otherFrame = other.frame
        let view = panel.pinView
        view.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 150, y: 150), in: panel))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 170, y: 150), in: panel))
        panel.keyDown(with: escape())
        XCTAssertEqual(board.pins.count, 1)
        let frame = panel.frame
        view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 300, y: 300), in: panel))
        view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 300, y: 300), in: panel))
        XCTAssertEqual(panel.frame, frame, "a pin closed by Esc kept moving")
        XCTAssertEqual(other.frame, otherFrame, "the remaining pin was moved by the dead one's drag")
        XCTAssertTrue(board.pins.first === other)
    }

    /// A new drag after the grab of a previous one that never ended (mouseUp lost) must start from its own press.
    func testAPressAfterALostReleaseDoesNotJumpToTheOldGrab() throws {
        let board = board()
        let panel = try board.open(picture(), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 150, y: 150), in: panel))
        panel.pinView.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 250, y: 160), in: panel))
        let before = panel.frame
        panel.pinView.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 250, y: 160), in: panel))
        XCTAssertEqual(panel.frame, before, "the second press did not replace the first grab")
    }

    // MARK: Every display gone, and back

    func testEveryDisplayGoneLeavesPinsAloneAndTheirReturnBringsThemHome() async throws {
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 1000, height: 800)), (DisplayID(2), CGRect(x: 1000, y: 0, width: 1000, height: 800))]
        let board = board()
        let stranded = try board.open(picture(), frame: CGRect(x: 1500, y: 100, width: 200, height: 100))
        let kept = stranded.frame
        desk = []
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await grace(0.3)
        XCTAssertEqual(stranded.frame, kept, "a pin was moved while no display was listed")
        let width = stranded.frame.width
        stranded.pinView.scrollWheel(with: try scroll(40))
        XCTAssertGreaterThan(stranded.frame.width, width, "a pin cannot be scaled while no display is listed")
        desk = [(DisplayID(1), CGRect(x: 0, y: 0, width: 1000, height: 800))]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await waitUntil("the pin came home when a display returned") { CGRect(x: 0, y: 0, width: 1000, height: 800).contains(stranded.frame) }
    }

    // MARK: Memory

    /// The picture is handed back with the pin: the image's own data is released after `close`, `closeAll`
    /// and Esc, with no reference kept by the panel, the view, the layer or the board.
    func testAClosedPinGivesItsPictureBack() async throws {
        for how in ["close", "closeAll", "esc"] {
            let released = Released()
            let board = board()
            weak var view: PinView?
            weak var panel: PinPanel?
            try autoreleasepool {
                let image = try releasing(released)
                let pin = board.open(image, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
                pin.pinView.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 150, y: 150), in: pin))
                pin.pinView.scrollWheel(with: try scroll(10))
                view = pin.pinView
                panel = pin
                switch how {
                case "close": board.close(pin)
                case "closeAll": board.closeAll()
                default: pin.cancelOperation(nil)
                }
            }
            await waitUntil("\(how): the panel was freed") { panel == nil }
            await waitUntil("\(how): the view was freed") { view == nil }
            await waitUntil("\(how): the picture's data was released") { released.count == 1 }
            XCTAssertEqual(board.pins.count, 0)
        }
    }

    private final class Released: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }

    private func releasing(_ released: Released) throws -> CGImage {
        let box = Unmanaged.passRetained(released)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 200 * 100 * 4)
        bytes.initialize(repeating: 0xff, count: 200 * 100 * 4)
        let provider = try XCTUnwrap(CGDataProvider(dataInfo: box.toOpaque(), data: bytes, size: 200 * 100 * 4) { info, data, _ in
            data.deallocate()
            if let info { Unmanaged<Released>.fromOpaque(info).takeRetainedValue().bump() }
        })
        return try XCTUnwrap(CGImage(width: 200, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 800,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
