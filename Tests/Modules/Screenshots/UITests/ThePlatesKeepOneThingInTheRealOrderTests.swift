import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **One plate by the pointer, in the order a person produces the scenes.**
/// `ThePlatesSayOneThingByThePointerTests` applies each scene to a fresh view,
/// so the plate a scene must *hide* was never shown in the first place and the
/// hiding is not exercised: with the line that hides the coordinates during a
/// drag deleted, all five of its cases stay green. A drag always begins with the
/// pointer moving over the frame, and ends — released as a click or cancelled —
/// with the pointer alone again, so both plates have been up by the time the
/// other one is asked for.
///
/// A view is built over a synthetic frame and never ordered in: nothing here
/// reaches a screen.
@MainActor
final class ThePlatesKeepOneThingInTheRealOrderTests: XCTestCase {

    private func view() throws -> OverlayView {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frame = FrozenDisplay(id: DisplayID(0xDEAD_BEEF), frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                  scale: 2, image: try XCTUnwrap(context.makeImage()))
        let overlay = CaptureOverlay(freeze: Freeze(displays: [.image(frame)], windows: [])) { _ in }
        return OverlayView(frozen: frame, overlay: overlay)
    }

    /// Pointer first, then the drag opens: the size replaces the coordinates.
    func testADragThatFollowsAPointerShowsOnlyTheSize() throws {
        let view = try view()
        var scene = OverlayScene()
        scene.pointer = CGPoint(x: 100, y: 100)
        view.apply(scene)
        XCTAssertEqual(view.visiblePlates.map(\.string), ["100, 100"], "the subject: the coordinates were up")
        scene.pointer = CGPoint(x: 700, y: 520)
        scene.selection = CGRect(x: 100, y: 100, width: 600, height: 420)
        view.apply(scene)
        XCTAssertEqual(view.visiblePlates.map(\.string), ["1200 × 840"],
                       "the coordinates stayed up under the size")
    }

    /// The drag goes away and the pointer is alone again: the coordinates
    /// replace the size.
    func testAPointerThatFollowsADragShowsOnlyTheCoordinates() throws {
        let view = try view()
        var scene = OverlayScene()
        scene.pointer = CGPoint(x: 700, y: 520)
        scene.selection = CGRect(x: 100, y: 100, width: 600, height: 420)
        view.apply(scene)
        XCTAssertEqual(view.visiblePlates.map(\.string), ["1200 × 840"], "the subject: the size was up")
        scene.selection = nil
        scene.pointer = CGPoint(x: 300, y: 200)
        view.apply(scene)
        XCTAssertEqual(view.visiblePlates.map(\.string), ["300, 200"],
                       "the size stayed up beside the coordinates")
    }
}
