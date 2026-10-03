import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A press on the capsule that hits no cell does nothing; it does not reach the drag view under it, whose click is
/// «Edit».** The rim (4 pt) and the divider's strip before ✕ are on no cell: a hit test there answers the capsule's own
/// view, and outside the capsule's shape (the corner of its box) the drag view as before.
///
/// Two ways of reading it. The hit test names who answers (`testARimAndADividerPressAnswerTheCapsuleAndNotTheDragView`);
/// the presses below are sent through the window as events (`NSWindow.sendEvent`, the way AppKit routes a click), and what
/// they read is the effect a person sees: whether the editor was asked for. A shield that is gone is red there by an
/// edit that fired, not by a view that is missing.
@MainActor
final class TheCapsuleSwallowsEveryPressOnItsShapeTests: XCTestCase {

    private struct Capsule {
        let host: NSView
        let window: NSWindow
        let model: ShotToastModel
        /// The capsule's own box, from the cells and the inset round them: not read off the shield, so that a capsule with
        /// no shield is still aimed at where its rim is.
        let box: CGRect
        let shield: ShotCapsuleView?
        let cells: [CGRect]
        let picture: CGRect
        /// What the model was asked to do, by press.
        let counts: Counts
    }

    private final class Counts {
        var edit = 0, copy = 0, dismiss = 0
        var all: [Int] { [edit, copy, dismiss] }
    }

    /// A thumbnail with the capsule up: Edit, Copy, ✕ (no file, a held picture: nothing here may open Finder), or with a
    /// file too when asked, where Show in Finder is a cell that is not pressed.
    private func capsule(withFile: Bool = false) throws -> Capsule {
        let image = try ShotToastRig.picture(width: 1600, height: 900)
        let file = withFile ? try ShotToastRig.realFile(self) : nil
        let content = ShotToastModel.Content.picture(image, caption: "x", file: file)
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        model.hovering = true
        // What «Edit» opens on is read when the view draws: it is set before the first draw, or the capsule has no Edit cell.
        model.full = image
        model.reading = file.flatMap { FileShotWriter().reading(of: $0) }
        let size = NSHostingView(rootView: ShotToastView(model: model)).fittingSize
        let mounted = MountedRender(ShotToastView(model: model), width: size.width, height: size.height, appearance: .aqua)
        mounted.settle(20)
        let counts = Counts()
        model.edit = { counts.edit += 1 }
        model.copy = { counts.copy += 1 }
        model.dismiss = { counts.dismiss += 1 }
        let host = mounted.host
        let window = try XCTUnwrap(mounted.window)
        let drag = try XCTUnwrap(host.everyView(ofType: ShotDragView.self).first)
        let cells = host.everyView(named: "_FocusRingView").map { $0.convert($0.bounds, to: host) }.sorted { $0.minX < $1.minX }
        let row = try XCTUnwrap(cells.map(\.minY).min(), "no cell is drawn")
        let first = try XCTUnwrap(cells.first), last = try XCTUnwrap(cells.last)
        let box = CGRect(x: first.minX - ShotCapsule.inset, y: row - ShotCapsule.inset, width: last.maxX - first.minX + 2 * ShotCapsule.inset,
                         height: try XCTUnwrap(cells.map(\.maxY).max()) - row + 2 * ShotCapsule.inset)
        let shield = host.everyView(ofType: ShotCapsuleView.self).first
        return Capsule(host: host, window: window, model: model, box: box, shield: shield, cells: cells,
                       picture: drag.convert(drag.bounds, to: host), counts: counts)
    }

    /// A press and its release at a point of the host, sent through the window.
    private func click(_ c: Capsule, at point: NSPoint) throws {
        // SwiftUI takes a press only in a window that is ordered in: invisible, and far off every screen.
        c.window.alphaValue = 0
        c.window.ignoresMouseEvents = false
        c.window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
        c.window.orderFrontRegardless()
        defer { c.window.orderOut(nil) }
        c.window.layoutIfNeeded()
        let inWindow = c.host.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: c.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            c.window.sendEvent(event)
        }
    }

    private func hit(_ c: Capsule, _ point: NSPoint) -> NSView? { c.host.hitTest(c.host.convert(point, to: c.host.superview)) }

    func testARimAndADividerPressAnswerTheCapsuleAndNotTheDragView() throws {
        let c = try capsule(withFile: true)
        let close = try XCTUnwrap(c.cells.last)
        // The strip before ✕, a point left of it, at the divider's own height, and the rim at the capsule's left end.
        let strip = NSPoint(x: close.minX - 2, y: c.box.midY)
        XCTAssertTrue(hit(c, strip) is ShotCapsuleView, "a press 2 pt left of ✕ lands on \(String(describing: hit(c, strip)))")
        let rim = NSPoint(x: c.box.midX, y: c.box.minY + 1)
        XCTAssertTrue(hit(c, rim) is ShotCapsuleView, "a press on the capsule's top rim lands on \(String(describing: hit(c, rim)))")
        XCTAssertTrue(hit(c, NSPoint(x: c.box.minX + 1, y: c.box.midY)) is ShotCapsuleView, "the left end")
        // The box's corner is outside the capsule's shape: the picture's.
        XCTAssertTrue(hit(c, NSPoint(x: c.box.minX + 0.5, y: c.box.minY + 0.5)) is ShotDragView,
                      "the corner of the box, outside the shape, is the drag view's")
    }

    // MARK: What the presses do

    /// The control: the capsule holds the cells the presses below are aimed at.
    func testTheCapsuleHasEditCopyAndTheCloseCell() throws {
        let c = try capsule()
        XCTAssertEqual(c.cells.count, 3, "Edit, Copy, ✕: \(c.cells)")
        let shield = try XCTUnwrap(c.shield, "no capsule view in the tree")
        // The control for the box the presses are aimed by: it is the shield's own, within the layout's rounding.
        let own = shield.convert(shield.bounds, to: c.host)
        for (found, wanted) in [(own.minX, c.box.minX), (own.maxX, c.box.maxX), (own.minY, c.box.minY), (own.maxY, c.box.maxY)] {
            XCTAssertEqual(found, wanted, accuracy: 1, "the shield is \(own), the cells and the inset make \(c.box)")
        }
        XCTAssertEqual(c.box.width, ShotCapsule.width(cellCount: 3), accuracy: 0.5, "the box the presses are aimed by is the capsule's computed width")
    }

    /// **The press that did reach the drag view was «Edit»**: on the divider's strip, on the rim along the top and the
    /// bottom, on the capsule's two ends, and between two cells. None of them asks for the editor, or does anything else.
    func testAPressOnTheSeparatorTheRimAndTheGapsDoesNothingAtAll() throws {
        let c = try capsule()
        let close = try XCTUnwrap(c.cells.last)
        var points: [(String, NSPoint)] = [
            ("the strip before ✕", NSPoint(x: close.minX - 2, y: c.box.midY)),
            ("the divider's own line", NSPoint(x: close.minX - ShotCapsule.separatorGap - 0.5, y: c.box.midY)),
            ("the rim above the cells", NSPoint(x: c.box.midX, y: c.box.minY + 1)),
            ("the rim below the cells", NSPoint(x: c.box.midX, y: c.box.maxY - 1)),
            ("the left end", NSPoint(x: c.box.minX + 2, y: c.box.midY)),
            ("the right end", NSPoint(x: c.box.maxX - 2, y: c.box.midY)),
        ]
        for pair in zip(c.cells, c.cells.dropFirst()).prefix(1) {
            points.append(("the gap between two cells", NSPoint(x: (pair.0.maxX + pair.1.minX) / 2, y: c.box.midY)))
        }
        for (name, point) in points {
            let before = c.counts.all
            try click(c, at: point)
            XCTAssertEqual(c.counts.all, before, "a press on \(name) did something: edit/copy/dismiss \(c.counts.all)")
        }
        XCTAssertEqual(c.counts.all, [0, 0, 0])
    }

    /// The control that makes the one above mean something: the same press, sent the same way, on the picture away from
    /// the capsule is «Edit», once.
    func testAPressOnThePictureAwayFromTheCapsuleStillOpensTheEditor() throws {
        let c = try capsule()
        try click(c, at: NSPoint(x: c.picture.midX, y: c.picture.minY + 6))
        XCTAssertEqual(c.counts.edit, 1, "a press on the picture did not ask for the editor")
        XCTAssertEqual(c.counts.copy + c.counts.dismiss, 0)
        // The corner of the capsule's box, outside its shape, is the picture's too.
        try click(c, at: NSPoint(x: c.box.minX + 0.5, y: c.box.minY + 0.5))
        XCTAssertEqual(c.counts.edit, 2, "a press at the corner of the capsule's box is not on the picture")
    }

    /// Each cell still takes its own press, and only its own: the shield sits under the cells, not over them.
    func testAPressOnEachCellStillFiresThatCellAndOnlyThat() throws {
        let c = try capsule()
        XCTAssertEqual(c.cells.count, 3)
        for (index, expected) in [[1, 0, 0], [0, 1, 0], [0, 0, 1]].enumerated() {
            let fresh = try capsule()
            let cell = fresh.cells[index]
            try click(fresh, at: NSPoint(x: cell.midX, y: cell.midY))
            XCTAssertEqual(fresh.counts.all, expected, "cell \(index) (edit, copy, ✕): edit/copy/dismiss after its press")
        }
    }

    /// Show in Finder is a cell too, and is not pressed here (it would open Finder on this Mac): its centre answers
    /// neither the shield nor the picture's drag view, which is what a cell that takes its own press looks like.
    func testTheShowInFinderCellIsNeitherTheShieldNorThePicture() throws {
        let c = try capsule(withFile: true)
        XCTAssertEqual(c.cells.count, 4, "Edit, Copy, Show in Finder, ✕")
        let reveal = c.cells[2]
        let answered = hit(c, NSPoint(x: reveal.midX, y: reveal.midY))
        XCTAssertNotNil(answered)
        XCTAssertFalse(answered is ShotCapsuleView, "a press on Show in Finder is swallowed by the shield")
        XCTAssertFalse(answered is ShotDragView, "a press on Show in Finder reaches the picture, whose click is Edit")
    }
}
