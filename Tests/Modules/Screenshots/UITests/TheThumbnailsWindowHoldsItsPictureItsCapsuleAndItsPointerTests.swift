import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The thumbnail's window is the picture, the room its shadow is drawn in, and room for the capsule; the pointer's
/// zone covers what the pointer is meant to reach.** Read off the rendered tree of the view at the size the panel is
/// given (`fittingSize`, which is what `ShotToast.place` sets): the drag view is the picture's own rect and the
/// hover's, the focus-ring views are the capsule's cells.
///
/// Where the window stands on a screen is `place`'s, which reads `NSEvent.mouseLocation` and `NSScreen` and has no
/// seam; a panel is not put on the owner's screen here. What is read is the part of it that is a fact of the view: the
/// picture's ring stands `ShotToast.shadowRoom` from the window's lower and right edges, so `place`'s 20 pt less that
/// room puts the ring 20 pt from the screen's edges. Not measured: `place` itself, the shadow's pixels, whether the
/// transparent room passes a click to the window below (a window of `.borderless`, `isOpaque = false`, with no
/// `ignoresMouseEvents`: AppKit decides on the window server's alpha, which an offscreen host does not give).
@MainActor
final class TheThumbnailsWindowHoldsItsPictureItsCapsuleAndItsPointerTests: XCTestCase {

    private static let ring: CGFloat = 3

    /// The rendered view at the size the panel is given, with the pointer over or not.
    private struct Laid {
        let host: NSView
        let size: CGSize
        let picture: CGRect
        let cells: [CGRect]
        let mount: MountedRender
        let model: ShotToastModel
    }

    private func laid(_ width: Int, _ height: Int, hovering: Bool, file: URL? = nil) throws -> Laid {
        let image = try ShotToastRig.picture(width: width, height: height)
        let content = ShotToastModel.Content.picture(image, caption: "x", file: file)
        let probe = ShotToastModel()
        probe.content = content
        probe.shown = true
        probe.hovering = hovering
        let size = NSHostingView(rootView: ShotToastView(model: probe)).fittingSize
        let rendered = ShotToastRig.mount(content, hovering: hovering, width: size.width, height: size.height)
        let host = rendered.mount.host
        let drag = try XCTUnwrap(host.everyView(ofType: ShotDragView.self).first, "\(width)×\(height): no drag view in the tree")
        let cells = host.everyView(named: "_FocusRingView").map { $0.convert($0.bounds, to: host) }
        return Laid(host: host, size: size, picture: drag.convert(drag.bounds, to: host), cells: cells,
                    mount: rendered.mount, model: rendered.model)
    }

    /// The hosting view is flipped (measured): y grows downward, so `top` is the smaller y.
    private func offsets(_ laid: Laid) -> (left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat) {
        let ring = laid.picture.insetBy(dx: -Self.ring, dy: -Self.ring)
        let bounds = laid.host.bounds
        return (ring.minX - bounds.minX, bounds.maxX - ring.maxX, bounds.maxY - ring.maxY, ring.minY - bounds.minY)
    }

    // MARK: The picture and its room

    /// A shot wider than the capsule: the window is the ring plus the shadow's room, evenly, so that `place`'s inset
    /// makes the ring stand 20 pt from the screen's lower and right edges.
    func testAShotWiderThanTheCapsuleStandsInItsRoomOnEverySide() throws {
        for (width, height) in [(1600, 900), (200, 126), (10_000, 100), (400, 300)] {
            let laid = try laid(width, height, hovering: false)
            let fitted = ShotThumbnail.fitted(pixels: CGSize(width: width, height: height))
            XCTAssertEqual(laid.picture.width, fitted.width, accuracy: 0.5, "\(width)×\(height): the picture is not the fitted size")
            XCTAssertEqual(laid.picture.height, fitted.height, accuracy: 0.5, "\(width)×\(height)")
            let room = offsets(laid)
            let expected = ShotToast.shadowRoom
            for (side, value) in [("left", room.left), ("right", room.right), ("bottom", room.bottom), ("top", room.top)] {
                XCTAssertEqual(value, expected, accuracy: 1, "\(width)×\(height): the ring stands \(value) pt from the window's \(side) edge, not \(expected)")
            }
            // The panel's size is the view's fitting size, which AppKit rounds up to whole points.
            XCTAssertEqual(laid.size.width, fitted.width + 2 * Self.ring + 2 * expected, accuracy: 1)
            XCTAssertEqual(laid.size.height, fitted.height + 2 * Self.ring + 2 * expected, accuracy: 1)
        }
    }

    /// A shot narrower than the capsule: the window is at least as wide as the capsule's widest, and the ring is still
    /// the picture's size, not stretched to the capsule.
    func testANarrowShotsWindowIsAtLeastTheCapsulesWidestAndItsRingIsStillThePictures() throws {
        for (width, height) in [(40, 30), (1, 1), (60, 400), (100, 20), (300, 1200), (900, 1600)] {
            let laid = try laid(width, height, hovering: false)
            XCTAssertGreaterThanOrEqual(laid.size.width, ShotCapsule.widest, "\(width)×\(height): the window is narrower than its capsule")
            let fitted = ShotThumbnail.fitted(pixels: CGSize(width: width, height: height))
            XCTAssertEqual(laid.picture.width, fitted.width, accuracy: 0.5, "\(width)×\(height): the ring is not the picture's width")
            XCTAssertEqual(laid.picture.height, fitted.height, accuracy: 0.5, "\(width)×\(height)")
            XCTAssertLessThan(laid.picture.width, ShotCapsule.widest, "the control: this shot is narrower than its capsule")
        }
    }

    /// **A defect of stage 3, handed to engineer red and repaired in stage 4; this holds it repaired.** `place` puts the window's right and lower edges
    /// `shadowRoom - 20` past the screen's visible corner on the one assumption that the ring stands `shadowRoom` from
    /// them; on a shot narrower than the capsule the picture is centred in the wider window (`.frame(minWidth:)`), so
    /// its ring stands further from the right edge and the picture is not 20 pt from the screen's edge.
    func testANarrowShotsRingStandsTheSameRoomFromTheWindowsRightEdge() throws {
        for (width, height) in [(40, 30), (60, 400), (300, 1200), (900, 1600)] {
            let laid = try laid(width, height, hovering: false)
            XCTAssertEqual(offsets(laid).right, ShotToast.shadowRoom, accuracy: 1,
                           "\(width)×\(height): the ring stands \(offsets(laid).right) pt from the window's right edge, not \(ShotToast.shadowRoom): the picture is not 20 pt from the screen's edge")
        }
    }

    // MARK: The capsule

    /// The capsule's width as the cells draw it, outer edge of the first to outer edge of the last, plus the capsule's
    /// own inset at each end: the computed `ShotCapsule.width(cellCount:)` against what the layout does with the
    /// divider (the assumption «a divider in the row takes one point» is measured here, not taken).
    private func capsuleWidth(_ laid: Laid) throws -> CGFloat {
        let first = try XCTUnwrap(laid.cells.map(\.minX).min(), "no cell is drawn")
        let last = try XCTUnwrap(laid.cells.map(\.maxX).max())
        return last - first + 2 * ShotCapsule.inset
    }

    func testTheRenderedCapsuleIsAsWideAsTheComputedOneForTwoAndThreeCells() throws {
        let file = try ShotToastRig.realFile(self)
        let two = try laid(1600, 900, hovering: true, file: nil)
        let three = try laid(1600, 900, hovering: true, file: file)
        XCTAssertEqual(two.cells.count, 2, "the control: Copy and ✕")
        XCTAssertEqual(three.cells.count, 3, "the control: Copy, Show in Finder and ✕")
        XCTAssertEqual(try capsuleWidth(two), ShotCapsule.width(cellCount: 2), accuracy: 0.5, "two cells")
        XCTAssertEqual(try capsuleWidth(three), ShotCapsule.width(cellCount: 3), accuracy: 0.5, "three cells")
        XCTAssertEqual(try capsuleWidth(three) - (try capsuleWidth(two)), HelmSpace.s7 + ShotCapsule.gap, accuracy: 0.5,
                       "one more cell is not a cell (`HelmSpace.s7`) and the gap (`ShotCapsule.gap`) before it")
    }

    /// The room the window keeps is the widest list the capsule can have: with Edit on offer it is Edit, Copy, Show in
    /// Finder and ✕, and one more while the entry offers the Pin. Asked of every list the view can draw (a file or none,
    /// an Edit or none), so that a cell added to the list and not to the room is red here and not clipped on a screen.
    func testTheWidestIsNoNarrowerThanAnyListTheCapsuleCanHave() {
        XCTAssertFalse(PinEntry.isOffered, "the control: this file is about v1; with the pin offered `widest` has one more cell")
        for hasFile in [false, true] {
            for canEdit in [false, true] {
                for pinOffered in [false, true] where pinOffered == PinEntry.isOffered {
                    let cells = ShotCapsule.cells(hasFile: hasFile, canEdit: canEdit, pinOffered: pinOffered)
                    XCTAssertLessThanOrEqual(ShotCapsule.width(cellCount: cells.count), ShotCapsule.widest,
                                             "file \(hasFile), edit \(canEdit): \(cells) is wider than the room kept")
                }
            }
        }
        XCTAssertEqual(ShotCapsule.cells(hasFile: true, canEdit: true, pinOffered: false).count, 4, "Edit, Copy, Show in Finder, ✕")
        XCTAssertEqual(ShotCapsule.widest, ShotCapsule.width(cellCount: 4), "the room is the widest list's, not a cell wider")
        // The divider's one point is the constant's own, private: the difference between two lists is what names the rest.
        XCTAssertEqual(ShotCapsule.width(cellCount: 4) - ShotCapsule.width(cellCount: 3), HelmSpace.s7 + ShotCapsule.gap,
                       "a fourth cell is a cell and the gap before it")
        XCTAssertEqual(ShotCapsule.width(cellCount: 4),
                       4 * HelmSpace.s7 + 3 * ShotCapsule.gap + 1 + 2 * ShotCapsule.separatorGap + 2 * ShotCapsule.inset,
                       "four cells, three gaps, the divider's point, the two separator gaps, the two insets")
    }

    /// The capsule stands inside the window on every shot, tiny ones included (it is not clipped by its own panel).
    func testTheCapsuleIsInsideTheWindowOnEveryShot() throws {
        let file = try ShotToastRig.realFile(self)
        for (width, height) in [(1600, 900), (40, 30), (1, 1), (60, 400), (100, 20), (300, 1200)] {
            let laid = try laid(width, height, hovering: true, file: file)
            XCTAssertEqual(laid.cells.count, 3, "\(width)×\(height): the capsule is not drawn")
            for cell in laid.cells {
                XCTAssertTrue(laid.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(cell), "\(width)×\(height): a cell \(cell) is outside the window \(laid.host.bounds)")
            }
        }
    }

    // MARK: The pointer

    /// **The hover zone is the drag view, which is the picture; the capsule must be inside it, or the pointer on a
    /// cell is outside the picture and the capsule goes from under it.** The pointer's exit is not measured here; this
    /// reads the geometry that decides whether one would come: every cell inside the picture's rect.
    func testEveryCellOfTheCapsuleIsInsideTheHoverZoneOfAShotThatIsWideEnough() throws {
        let file = try ShotToastRig.realFile(self)
        for (width, height) in [(1600, 900), (200, 126), (160, 100), (400, 300), (101, 44)] {
            let laid = try laid(width, height, hovering: true, file: file)
            XCTAssertEqual(laid.cells.count, 3, "\(width)×\(height): the capsule is not drawn")
            for cell in laid.cells {
                XCTAssertTrue(laid.picture.insetBy(dx: -0.5, dy: -0.5).contains(cell),
                              "\(width)×\(height): the cell \(cell) is outside the hover zone \(laid.picture)")
            }
        }
    }

    /// **A shot narrower than the capsule's cells (`ShotCapsule.width(cellCount:)`: every portrait taller than that
    /// many times its width, 900×1600 among them) or shorter than the capsule's `ShotCapsule.reach` (a strip such as
    /// 1600×100, which stands 200×12.5) has a hover zone smaller than the capsule if the window is the picture's alone**:
    /// the window keeps the capsule's room, and this holds every cell inside the zone. The part of the capsule outside the picture
    /// is outside `ShotDragView`, whose tracking area is the only thing that reports the pointer, so a pointer moving
    /// from the picture onto an outer cell leaves the zone (an exit, then `hovering = false` and the capsule is
    /// removed from under it). The exit itself is not measured; the rects are.
    func testEveryCellOfTheCapsuleIsInsideTheHoverZoneOfANarrowOrAShortShotToo() throws {
        let file = try ShotToastRig.realFile(self)
        for (width, height) in [(40, 30), (1, 1), (60, 400), (300, 1200), (900, 1600), (90, 90), (100, 20), (110, 30), (1600, 100)] {
            let laid = try laid(width, height, hovering: true, file: file)
            XCTAssertEqual(laid.cells.count, 3, "\(width)×\(height): the capsule is not drawn")
            for cell in laid.cells {
                XCTAssertTrue(laid.picture.insetBy(dx: -0.5, dy: -0.5).contains(cell),
                              "\(width)×\(height): the cell \(cell) is outside the hover zone \(laid.picture)")
            }
        }
    }

    // MARK: The transparent room

    /// What a point of the window answers to a hit test, in the room round the picture, on the picture and on a cell.
    /// A hosting view answers a point where no SwiftUI content is with nothing, or with itself: either way it is not
    /// the drag view, and a click there does not open the shot.
    func testThePictureIsHitAndTheRoomRoundItIsNotTheDragView() throws {
        let laid = try laid(1600, 900, hovering: false)
        let superview = laid.host.superview
        func hit(_ point: NSPoint) -> NSView? { laid.host.hitTest(laid.host.convert(point, to: superview)) }
        let inPicture = hit(NSPoint(x: laid.picture.midX, y: laid.picture.midY))
        XCTAssertTrue(inPicture is ShotDragView, "the picture's own point is \(String(describing: inPicture)), not the drag view")
        let room = [NSPoint(x: 5, y: 5), NSPoint(x: laid.size.width / 2, y: 10), NSPoint(x: laid.picture.minX - 10, y: laid.picture.midY),
                    NSPoint(x: laid.picture.midX, y: laid.picture.maxY + 10)]
        for point in room {
            XCTAssertFalse(hit(point) is ShotDragView, "a click at \(point), in the shadow's room, lands on the picture's drag view")
        }
    }
}
