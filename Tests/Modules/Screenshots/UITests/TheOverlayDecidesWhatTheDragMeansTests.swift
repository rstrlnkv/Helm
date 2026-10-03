import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The overlay's state machine, driven by hand.** The panels are built and
/// never ordered in, so nothing appears on the screen of whoever runs this; the
/// views report what happened to them exactly as a mouse would, and each test
/// reads what the overlay decided.
///
/// Every test drives the main screen, with a synthetic frame of its real size;
/// any other screen on the Mac gets a frame too, because the overlay is built
/// over every screen or none. Every test asserts that the overlay *finished* before asserting what it
/// finished with — a result that never arrives must not read as "cancelled".
@MainActor
final class TheOverlayDecidesWhatTheDragMeansTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    /// A frozen frame for a screen, at `origin`, with the screen's real size and scale.
    private func frozen(_ screen: NSScreen, at origin: CGPoint) throws -> FrozenDisplay {
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return FrozenDisplay(id: DisplayID(number), frame: CGRect(origin: origin, size: size), scale: scale,
                             image: try XCTUnwrap(context.makeImage()))
    }

    /// The overlay covers every screen or none, so the freeze holds a frame for
    /// every screen there is. The main screen's frame starts at the origin and
    /// any other is parked far away from it, so a window in the main screen's
    /// own points can never be found on a neighbour.
    private func display() throws -> (id: DisplayID, frames: [FrozenDisplay]) {
        let main = try XCTUnwrap(NSScreen.main, "no screen, so nothing here can be built")
        let first = try frozen(main, at: .zero)
        var frames = [first]
        for (index, screen) in NSScreen.screens.enumerated() where screen != main {
            frames.append(try frozen(screen, at: CGPoint(x: 100_000 * CGFloat(index + 1), y: 0)))
        }
        return (first.id, frames)
    }

    /// `windows` are in the main display's own points, since its frame starts at the origin here.
    private func build(windows: [FrozenWindow] = []) throws -> DisplayID {
        let (id, frames) = try display()
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: windows)
        let overlay = CaptureOverlay(freeze: freeze) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(overlay.build(), "the overlay could not be built for a display that is on screen")
        self.overlay = overlay
        return id
    }

    private func key(_ code: UInt16, down: Bool = true, repeats: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: repeats, keyCode: code)!
    }

    /// A released area is the editor's now, and Return takes it.
    private func confirm() { overlay?.keyDown(key(36)) }

    private func finishedOnce(file: StaticString = #filePath, line: UInt = #line) -> OverlayResult? {
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)", file: file, line: line)
        return results.first
    }

    func testADragAndARelease() throws {
        let id = try build()
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(results.count, 0, "the release finished the press")
        confirm()
        guard case .edited(let display, let local, _, _)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(display, id)
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testAClickThatNeverMovedWaitsForARealSelection() throws {
        let id = try build()
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(results.count, 0, "a click with no drag captured something")
        overlay?.mouseDown(on: id, at: CGPoint(x: 10, y: 10), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 60, y: 40), flags: [])
        overlay?.mouseUp(on: id)
        confirm()
        guard case .edited? = finishedOnce() else { return XCTFail("\(results)") }
    }

    /// Through the view, with a real event: the wiring from the mouse to the
    /// overlay is what a mutation of the view would break.
    func testARightClickLeavesWithoutTheKeyboard() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                     timestamp: 0, windowNumber: 0, context: nil,
                                                     eventNumber: 0, clickCount: 1, pressure: 1))
        view.rightMouseDown(with: click)
        guard case .cancelled? = finishedOnce() else { return XCTFail("\(results)") }
    }

    func testEscapeCancels() throws {
        _ = try build()
        overlay?.keyDown(key(53))
        guard case .cancelled? = finishedOnce() else { return XCTFail("\(results)") }
    }

    func testEnterWithNothingSelectedIsTheWholeDisplayThePointerIsOn() throws {
        let id = try build()
        overlay?.mouseMoved(on: id, at: CGPoint(x: 400, y: 300))
        overlay?.keyDown(key(36))
        guard case .wholeDisplay(let display)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(display, id)
    }

    /// Return takes the screen the pointer is on and not the first one in the
    /// freeze — which is the main screen here, so on one screen the two are the
    /// same and the test above cannot tell them apart.
    func testEnterTakesTheScreenThePointerIsOnNotTheFirstInTheFreeze() throws {
        guard NSScreen.screens.count >= 2 else {
            throw XCTSkip("one screen: the pointer cannot be on a screen that is not the first")
        }
        let main = try build()
        let screen = try XCTUnwrap(NSScreen.screens.first { $0 != NSScreen.main })
        let other = DisplayID(try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32))
        XCTAssertNotEqual(other, main, "the second screen carries the main screen's number")
        overlay?.mouseMoved(on: other, at: CGPoint(x: 40, y: 30))
        overlay?.keyDown(key(36))
        guard case .wholeDisplay(let display)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(display, other, "Return took the first screen in the freeze, not the one the pointer is on")
    }

    func testEnterMidDragIsNotTheWholeDisplay() throws {
        let id = try build()
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.keyDown(key(36))
        XCTAssertEqual(results.count, 0, "Return during a drag took the whole screen")
    }

    /// Space switches to window mode; the window under the pointer is the one a
    /// click captures, and the frontmost wins where two overlap.
    func testSpaceThenAClickCapturesTheWindowUnderThePointer() throws {
        let id = try build(windows: [
            FrozenWindow(id: 11, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0),
            FrozenWindow(id: 22, frame: CGRect(x: 0, y: 0, width: 900, height: 700), layer: 0),
        ])
        overlay?.mouseMoved(on: id, at: CGPoint(x: 150, y: 150))
        overlay?.keyDown(key(49))
        overlay?.mouseMoved(on: id, at: CGPoint(x: 160, y: 160))
        overlay?.mouseDown(on: id, at: CGPoint(x: 160, y: 160), flags: [])
        guard case .window(let window, _)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(window, 11, "the window behind was captured")
    }

    func testAClickOnNoWindowInWindowModeCapturesNothing() throws {
        let id = try build(windows: [FrozenWindow(id: 11, frame: CGRect(x: 100, y: 100, width: 50, height: 50), layer: 0)])
        overlay?.keyDown(key(49))
        overlay?.mouseMoved(on: id, at: CGPoint(x: 800, y: 600))
        overlay?.mouseDown(on: id, at: CGPoint(x: 800, y: 600), flags: [])
        XCTAssertEqual(results.count, 0, "a click on empty desktop captured a window")
    }

    func testSpaceAgainLeavesWindowMode() throws {
        let id = try build(windows: [FrozenWindow(id: 11, frame: CGRect(x: 0, y: 0, width: 900, height: 700), layer: 0)])
        overlay?.keyDown(key(49))
        overlay?.keyDown(key(49))
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseUp(on: id)
        confirm()
        guard case .edited? = finishedOnce() else { return XCTFail("a second Space did not go back to areas: \(results)") }
    }

    func testSpaceWhileDraggingMovesTheSelectionAndKeepsItsSize() throws {
        let id = try build()
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 200, y: 160), flags: [])
        overlay?.keyDown(key(49))
        overlay?.mouseDragged(on: id, at: CGPoint(x: 260, y: 200), flags: [])
        overlay?.keyUp(key(49, down: false))
        overlay?.mouseUp(on: id)
        confirm()
        guard case .edited(_, let local, _, _)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(local, CGRect(x: 160, y: 140, width: 100, height: 60))
    }

    func testOptionGrowsFromTheCentre() throws {
        let id = try build()
        overlay?.mouseDown(on: id, at: CGPoint(x: 500, y: 300), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 600, y: 340), flags: [.option])
        overlay?.mouseUp(on: id)
        confirm()
        guard case .edited(_, let local, _, _)? = finishedOnce() else { return XCTFail("\(results)") }
        XCTAssertEqual(local, CGRect(x: 400, y: 260, width: 200, height: 80))
    }

    /// Two arrivals in one turn — a click and a key — finish once.
    func testTheOverlayFinishesOnlyOnce() throws {
        let id = try build()
        overlay?.keyDown(key(53))
        overlay?.keyDown(key(53))
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(results.count, 1)
    }

    func testADisplayChangingWhileItIsOpenCancels() throws {
        _ = try build()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // The observer is delivered on the main queue.
        let done = expectation(description: "the overlay heard the display change")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
        guard case .cancelled? = finishedOnce() else { return XCTFail("\(results)") }
    }

    func testClosingStopsListeningForDisplayChanges() throws {
        _ = try build()
        overlay?.close()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let done = expectation(description: "drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(results.count, 0, "a closed overlay still answered a display change")
    }
}
