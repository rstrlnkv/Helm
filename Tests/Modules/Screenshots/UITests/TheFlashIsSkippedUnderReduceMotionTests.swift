import AppKit
import XCTest
import HelmUI
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A shot that is taken ends in a flash and the overlay closes after it; under Reduce Motion there is no flash
/// and the overlay closes at once.** Motion is not measured here: what is asserted is the decision (`flashed`,
/// `leaving`, `isOpen`) and what the overlay does with input while it waits. The setting is the Mac's, so each
/// test hands the overlay its own answer through `reducesMotion`.
///
/// Only a shot that was taken flashes: a cancel, a whole display and a pin have no shape to light, and a window
/// result the overlay is not holding a window for has none either. Each of those has the flashing result as its
/// control in the same file, so "closed at once" is read from an overlay that would have waited.
@MainActor
final class TheFlashIsSkippedUnderReduceMotionTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    /// An edited area on the first display; the way the controller takes a result is the way it is taken here: the
    /// overlay is closed `after` it.
    private func editing(reduce: Bool) throws -> (display: DisplayID, view: OverlayView) {
        overlay?.close()
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] result in
            self?.results.append(result)
            self?.overlay?.close(after: result)
        }
        overlay = rig.overlay
        rig.overlay.reducesMotion = { reduce }
        return (rig.display, rig.view)
    }

    private func windowOverlay(reduce: Bool, hover: CGPoint?) throws -> (display: DisplayID, view: OverlayView) {
        overlay?.close()
        let frames = try OverlayRig.frames()
        let id = try XCTUnwrap(frames.first?.id)
        let window = FrozenWindow(id: 11, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: [window]), mode: .window) { [weak self] result in
            self?.results.append(result)
            self?.overlay?.close(after: result)
        }
        overlay = built
        built.reducesMotion = { reduce }
        XCTAssertTrue(built.build())
        // Nothing hovered means a pointer on no window, wherever the Mac's own pointer happens to be.
        built.mouseMoved(on: id, at: hover ?? CGPoint(x: 900, y: 700))
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    /// Waits, bounded, until the overlay has closed itself, and asserts that it did.
    private func closesItself(_ what: String) async {
        for _ in 0..<60 where overlay?.isOpen == true { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(overlay?.isOpen, false, "never closed: \(what)")
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    // MARK: The decision

    func testTheDecisionIsTheNegationOfReduceMotion() {
        XCTAssertTrue(HelmMotion.flashes(reduceMotion: false))
        XCTAssertFalse(HelmMotion.flashes(reduceMotion: true))
    }

    func testUnderReduceMotionTheOverlayClosesAtOnceWithNothingFlashed() throws {
        let (display, view) = try editing(reduce: true)
        XCTAssertTrue(try XCTUnwrap(overlay).isOpen, "the subject: it is open before the shot")
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(overlay?.isOpen, false, "waited for a flash under Reduce Motion")
        XCTAssertEqual(overlay?.leaving, false)
        XCTAssertTrue(overlay?.flashed.isEmpty == true, "a flash was recorded under Reduce Motion: \(String(describing: overlay?.flashed))")
        XCTAssertNil(view.flashedRect)
        _ = display
    }

    func testWithMotionTheShotFlashesTheAreaAndTheOverlayClosesAfterIt() async throws {
        let (display, view) = try editing(reduce: false)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(overlay?.isOpen, true, "closed before the flash")
        XCTAssertEqual(overlay?.leaving, true)
        XCTAssertEqual(overlay?.flashed, [display: area], "the flash lights the area that was shot")
        XCTAssertEqual(view.flashedRect, area, "the layer lit is not the area, in the display's top-left points")
        await closesItself("after the flash")
        XCTAssertEqual(overlay?.leaving, false)
    }

    // MARK: Results that have nothing to flash

    func testACancelAWholeDisplayAndAPinCloseAtOnceEvenWithMotion() throws {
        let (display, _) = try editing(reduce: false)
        for result in [OverlayResult.cancelled, .wholeDisplay(display), .edited(display: display, local: area, layers: [], exit: .pin)] {
            overlay?.close(after: result)
            XCTAssertEqual(overlay?.isOpen, false, "\(result) waited for a flash")
            XCTAssertEqual(overlay?.leaving, false, "\(result)")
            overlay?.close()
            let (_, _) = try editing(reduce: false)
        }
        // The control: the same overlay and the same switch, the shot that does flash.
        overlay?.close(after: .edited(display: display, local: area, layers: [], exit: .confirm))
        XCTAssertEqual(overlay?.leaving, true, "the control did not flash, so the three closed at once for no reason")
    }

    func testAnEscThatCancelsClosesAtOnceWithMotion() throws {
        _ = try editing(reduce: false)
        overlay?.keyDown(key(53))
        XCTAssertEqual(results.count, 1, "the subject: Esc ended the capture")
        guard case .cancelled? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(overlay?.isOpen, false)
    }

    // MARK: A window

    func testAWindowFlashesInItsOwnPartOfTheDisplay() async throws {
        let (display, view) = try windowOverlay(reduce: false, hover: CGPoint(x: 150, y: 150))
        overlay?.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        guard case .window(11, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(overlay?.leaving, true)
        XCTAssertEqual(overlay?.flashed, [display: CGRect(x: 100, y: 100, width: 300, height: 200)])
        XCTAssertEqual(view.flashedRect, CGRect(x: 100, y: 100, width: 300, height: 200))
        await closesItself("a window's flash")
    }

    func testAWindowUnderReduceMotionClosesAtOnce() throws {
        let (display, _) = try windowOverlay(reduce: true, hover: CGPoint(x: 150, y: 150))
        overlay?.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        XCTAssertEqual(results.count, 1, "the subject")
        XCTAssertEqual(overlay?.isOpen, false)
        XCTAssertTrue(overlay?.flashed.isEmpty == true)
    }

    /// The result names a window the overlay is not holding: nothing hovered, or another one. There is no shape
    /// to flash, and the overlay must not wait for a flash that was never drawn.
    func testAWindowResultWithNothingHoveredOrAnotherWindowHoveredClosesAtOnce() throws {
        let (display, _) = try windowOverlay(reduce: false, hover: nil)
        overlay?.close(after: .window(11, shadow: true))
        XCTAssertEqual(overlay?.isOpen, false, "waited for a flash of a window nobody hovered")
        XCTAssertEqual(overlay?.leaving, false)
        let (_, _) = try windowOverlay(reduce: false, hover: CGPoint(x: 150, y: 150))
        overlay?.close(after: .window(99, shadow: true))
        XCTAssertEqual(overlay?.isOpen, false, "waited for a flash of a window other than the hovered one")
        // The control: the hovered one does flash.
        let (_, _) = try windowOverlay(reduce: false, hover: CGPoint(x: 150, y: 150))
        overlay?.close(after: .window(11, shadow: true))
        XCTAssertEqual(overlay?.leaving, true)
        _ = display
    }

    // MARK: What the overlay does while it waits

    /// Esc asks a question of an edited area that has layers, and the question is a plate. While the overlay is
    /// leaving, the same key reaching the view is dropped: nothing is asked of a capture that is over.
    func testTheViewIsDeafWhileTheFlashIsUp() throws {
        let (display, view) = try editing(reduce: false)
        OverlayRig.drawAndSelect(in: overlay, on: display)
        overlay?.keyDown(key(53)) // lets go of the object
        // The control: before the shot the second Esc asks, and a plate says so.
        overlay?.keyDown(key(53))
        XCTAssertEqual(view.visiblePlates.count, 1, "the subject: the question stands")
        overlay?.keyDown(key(124)) // an arrow withdraws it
        XCTAssertTrue(view.visiblePlates.isEmpty)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(overlay?.leaving, true, "the subject: the flash is up")
        view.keyDown(with: key(53))
        view.keyDown(with: key(53))
        XCTAssertTrue(view.visiblePlates.isEmpty, "Esc reached the overlay that is leaving")
    }

    /// A click in the flash must not fall through to what is under the overlay: the panel is still a window that takes it.
    func testThePanelStillTakesTheMouseWhileTheFlashIsUp() throws {
        let (_, view) = try editing(reduce: false)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(overlay?.leaving, true, "the subject")
        XCTAssertEqual(view.window?.ignoresMouseEvents, false, "clicks go through the panel to the windows below")
    }

    // MARK: Twice, and in the wrong order

    func testTheFlashAskedTwiceStillClosesOnceAndAfterwardsNothingIsLeft() async throws {
        let (display, _) = try editing(reduce: false)
        let result = OverlayResult.edited(display: display, local: area, layers: [], exit: .confirm)
        overlay?.close(after: result)
        overlay?.close(after: result)
        XCTAssertEqual(overlay?.leaving, true, "the subject")
        await closesItself("a flash asked twice")
        XCTAssertEqual(overlay?.leaving, false)
        try await Task.sleep(nanoseconds: 400_000_000) // the second timer fires on a closed overlay
        XCTAssertEqual(overlay?.isOpen, false)
    }

    func testACloseDuringTheFlashClosesNowAndTheTimerFindsNothingToDo() async throws {
        let (display, _) = try editing(reduce: false)
        overlay?.close(after: .edited(display: display, local: area, layers: [], exit: .confirm))
        XCTAssertEqual(overlay?.leaving, true, "the subject")
        overlay?.close()
        XCTAssertEqual(overlay?.isOpen, false)
        XCTAssertEqual(overlay?.leaving, false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(overlay?.isOpen, false)
        XCTAssertEqual(overlay?.leaving, false)
    }

    /// A result that arrives while the flash is up has nobody to be delivered to: the first one was the only one.
    func testAResultArrivingWhileLeavingIsNotDeliveredAgain() throws {
        let (display, _) = try editing(reduce: false)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(overlay?.leaving, true, "the subject")
        overlay?.finish(.cancelled)
        overlay?.perform(.exit(.copy))
        overlay?.keyDown(key(53))
        overlay?.mouseDown(on: display, at: CGPoint(x: 50, y: 50), flags: [])
        XCTAssertEqual(results.count, 1, "a second result was delivered: \(results)")
    }

    /// `close(after:)` on an overlay that is already closed lights nothing: it must not claim a flash that has
    /// no panel to be on.
    func testAFlashAskedOfAClosedOverlayIsNoFlash() throws {
        let (display, _) = try editing(reduce: false)
        overlay?.close()
        overlay?.close(after: .edited(display: display, local: area, layers: [], exit: .confirm))
        XCTAssertEqual(overlay?.isOpen, false)
        XCTAssertEqual(overlay?.leaving, false, "a closed overlay is waiting for a flash")
        XCTAssertTrue(overlay?.flashed.isEmpty == true, "a closed overlay recorded a flash: \(String(describing: overlay?.flashed))")
    }
}
