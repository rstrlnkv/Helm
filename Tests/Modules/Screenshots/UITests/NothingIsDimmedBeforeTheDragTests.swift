import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The screen is dimmed only once there is a selection, and a window pick is never dimmed.** The dim is
/// the selection's, so it comes with the first point a drag has moved over, an edited area or a remembered one,
/// and with none of them the frame is as the person left it. In window mode the window under the pointer is
/// filled with the accent and nothing else is touched.
///
/// Every claim has its control in the same test: the dim that is absent here is present one step later, so
/// "not drawn" is read from a view that is able to draw it.
@MainActor
final class NothingIsDimmedBeforeTheDragTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func open(mode: CaptureOverlay.Mode = .area, preselection: CGRect? = nil,
                      windows: [FrozenWindow] = []) throws -> (display: DisplayID, views: [OverlayView]) {
        overlay?.close()
        let frames = try OverlayRig.frames()
        let id = try XCTUnwrap(frames.first?.id)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: windows), mode: mode,
                                   preselection: preselection.map { (id, $0) }) { [weak self] in self?.results.append($0) }
        overlay = built
        XCTAssertTrue(built.build())
        let views = try frames.map { try XCTUnwrap(built.view(for: $0.id)) }
        return (id, views)
    }

    func testNothingIsDimmedWhenTheOverlayOpensOrThePointerMoves() throws {
        let (display, views) = try open()
        XCTAssertFalse(views.contains { $0.dimIsDrawn }, "dimmed on opening")
        overlay?.mouseMoved(on: display, at: CGPoint(x: 400, y: 300))
        XCTAssertFalse(views.contains { $0.dimIsDrawn }, "dimmed by a pointer that is only moving")
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 300), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 460, y: 340), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "the control: a drag that has moved dims")
    }

    /// A press is not a drag: nothing has moved, so there is no selection to light and none to dim around.
    func testAPressThatHasNotMovedDimsNothingAndNeitherDoesItsRelease() throws {
        let (display, views) = try open()
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 300), flags: [])
        XCTAssertFalse(views[0].dimIsDrawn, "dimmed by the press")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 400, y: 300), flags: [])
        XCTAssertFalse(views[0].dimIsDrawn, "dimmed by a drag event that did not move")
        overlay?.mouseUp(on: display)
        XCTAssertFalse(views[0].dimIsDrawn, "a click that never moved left a dim behind")
        XCTAssertTrue(results.isEmpty, "a click is not a result")
    }

    func testTheFirstPointOfTheDragDimsAndTheReleasedAreaKeepsTheDim() throws {
        let (display, views) = try open()
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 300), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 401, y: 301), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "one point of drag is a selection")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 600, y: 500), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertNotNil(views[0].areaSizePlate, "the subject: the area is being edited")
        XCTAssertTrue(views[0].dimIsDrawn, "the edited area is not dimmed around")
    }

    func testARememberedAreaIsDimmedAroundFromTheStart() throws {
        let (_, remembered) = try open(preselection: CGRect(x: 100, y: 100, width: 300, height: 200))
        XCTAssertTrue(remembered[0].dimIsDrawn)
        let (_, none) = try open()
        XCTAssertFalse(none[0].dimIsDrawn, "the control: the same overlay with no remembered area is not dimmed")
    }

    func testOnlyTheDisplayOfTheSelectionIsDimmed() throws {
        let (display, views) = try open()
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 300), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "the subject")
        for other in views.dropFirst() { XCTAssertFalse(other.dimIsDrawn, "a display with no selection was dimmed") }
    }

    func testAWindowPickIsNeverDimmedAndTheWindowIsFilledByItsOwnRectangle() throws {
        let window = FrozenWindow(id: 11, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        let (display, views) = try open(mode: .window, windows: [window])
        overlay?.mouseMoved(on: display, at: CGPoint(x: 150, y: 150))
        // The fill is in the layer's own space, which runs from the bottom of the (real screen's) view.
        XCTAssertEqual(views[0].windowFill, CGRect(x: 100, y: views[0].bounds.height - 300, width: 300, height: 200),
                       "the subject: the window is lit")
        XCTAssertFalse(views[0].dimIsDrawn, "a window pick was dimmed")
        overlay?.mouseMoved(on: display, at: CGPoint(x: 900, y: 700))
        XCTAssertNil(views[0].windowFill, "the control: off the window nothing is lit")
        XCTAssertFalse(views[0].dimIsDrawn)
    }

    /// The rule at the view, where the overlay's own state cannot reach it: a window-mode scene that carries a
    /// selection anyway (nothing in the overlay makes one today) is still not dimmed, and the same scene in the
    /// area mode is. Without the second half the first would pass on a view that never dims.
    func testASceneInWindowModeIsNotDimmedEvenWithASelectionInIt() throws {
        let (_, views) = try open()
        var scene = OverlayScene()
        scene.selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        views[0].apply(scene)
        XCTAssertTrue(views[0].dimIsDrawn, "the control: the same selection in the area mode is dimmed around")
        scene.windowMode = true
        views[0].apply(scene)
        XCTAssertFalse(views[0].dimIsDrawn, "a window-mode scene was dimmed")
    }

    /// In window mode a press and a drag are the pick's own; they never make a selection.
    func testAWindowPickStaysUndimmedThroughAPressAndADragWithNoWindowUnderIt() throws {
        let (display, views) = try open(mode: .window)
        overlay?.mouseMoved(on: display, at: CGPoint(x: 150, y: 150))
        overlay?.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 400, y: 400), flags: [])
        XCTAssertFalse(views[0].dimIsDrawn)
        XCTAssertTrue(results.isEmpty, "the subject: nothing was picked")
    }

    /// The area is released and edited, and the person presses outside it with no tool: a new drag starts, which
    /// replaces the area only when it turns out to be one. Until it has moved the old area is still the
    /// selection, so the dim around it stays (the dim stays until the shot or Esc).
    func testAPressOutsideTheEditedAreaKeepsTheDimUntilTheNewDragHasMoved() throws {
        let (display, views) = try open()
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(views[0].dimIsDrawn, "the subject: an edited area is dimmed around")
        overlay?.mouseDown(on: display, at: CGPoint(x: 700, y: 600), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "a press outside the area took the dim off before any drag")
        overlay?.mouseUp(on: display)
        XCTAssertTrue(views[0].dimIsDrawn, "a click outside the area, which keeps it, left the screen undimmed")
    }

    /// The pointer that went out and came back onto the press point in a first drag: the drag has moved, so the
    /// dim holds on the empty rectangle it left. The control is the press with no movement on the same screen,
    /// which dims nothing; both through the same events, so the one thing that differs is the trip.
    func testAFirstDragThatReturnsOntoThePressPointKeepsTheDim() throws {
        let (display, views) = try open()
        let press = CGPoint(x: 400, y: 300)
        overlay?.mouseDown(on: display, at: press, flags: [])
        overlay?.mouseDragged(on: display, at: press, flags: [])
        XCTAssertFalse(views[0].dimIsDrawn, "the control: a drag that has not moved dims nothing")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 460, y: 340), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "the subject: the drag has moved")
        overlay?.mouseDragged(on: display, at: press, flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "the pointer came back onto the press point and took the dim off")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 405, y: 300), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn)
        overlay?.mouseDragged(on: display, at: press, flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "a second return took the dim off")
    }

    /// A press and release with no movement, on a screen with no selection, dims nothing before, at and after
    /// the release, and a later real drag on the same overlay dims (the flag of the first press is not left up).
    func testAPressReleaseWithNoMovementOnAScreenWithNoSelectionDimsNothingAndLeavesNoFlagBehind() throws {
        let (display, views) = try open()
        let press = CGPoint(x: 400, y: 300)
        overlay?.mouseDown(on: display, at: press, flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertFalse(views[0].dimIsDrawn, "a click dimmed the screen")
        overlay?.mouseDown(on: display, at: press, flags: [])
        XCTAssertFalse(views[0].dimIsDrawn, "the next press dimmed the screen")
        overlay?.mouseUp(on: display)
        XCTAssertFalse(views[0].dimIsDrawn)
        overlay?.mouseDown(on: display, at: press, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 440, y: 340), flags: [])
        XCTAssertTrue(views[0].dimIsDrawn, "the control: a real drag on the same overlay dims")
    }

    /// A returned first drag that is then released has no area to edit; what the screen does then is the
    /// press-release rule, not a left-over dim around nothing.
    func testAFirstDragThatReturnedAndIsReleasedLeavesNoAreaAndNoDimAround() throws {
        let (display, views) = try open()
        let press = CGPoint(x: 400, y: 300)
        overlay?.mouseDown(on: display, at: press, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 460, y: 340), flags: [])
        overlay?.mouseDragged(on: display, at: press, flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertNil(views[0].areaSizePlate, "an empty drag became an area")
        XCTAssertFalse(views[0].dimIsDrawn, "the release of a drag that came back left a dim round nothing")
        XCTAssertTrue(results.isEmpty)
    }
}
