import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A pointer that rests on a small shot keeps the capsule up; the capsule's own coming up does not take it away.**
/// The owner's report: on a shot that is short in height the capsule's buttons never settle, they appear and fade in a
/// loop. On a shot at least `ShotCapsule.reach` high and wide enough the capsule stands inside the picture and the
/// hover view (`ShotDragView`) keeps its rect; on a smaller one the view is made larger when the capsule comes up
/// (`ShotToast.picture`, the `zone`) and smaller when it goes, every frame of the animation between, and each change
/// of its geometry has AppKit call `updateTrackingAreas`, which tears the tracking area down and builds a new one
/// (`ShotDragView.updateTrackingAreas`) under a pointer that has not moved.
///
/// **What this drives and what it stands in for.** The pointer's way in is the real one: `ShotDragView.mouseEntered`
/// into `onHover` into `ShotToastModel.pointer(over:shot:view:)` into the toast's `setHover`, the model and the clock's
/// holds. The window server is not here (a view in a window nobody sees is never given a tracking area, measured:
/// `trackingAreas` stays empty through the whole animation), so the test does what AppKit does on a geometry change,
/// which is to call `updateTrackingAreas` on the view whose frame changed, and says what it assumes of AppKit's answer:
/// **inferred, not measured, parked for a pointer on a real window (`package-dev`)**: a tracking area removed under a
/// pointer that is inside it reports an exit, and its replacement reports an enter only when the pointer next moves.
/// The first assertion does not lean on the assumption: a tracking area that is rebuilt while the capsule comes up is
/// the fault, whatever AppKit then says. The second does.
///
/// A shot that stays inside the capsule's room (`testATallShotAndATallPileAreTheControl`) goes through the same driver
/// and is green: the driver does not call anything unless a frame changed.
///
/// Total failure of the subject prints: «the hover view's tracking area was rebuilt N times», «the pointer reported
/// [true, false]», «the capsule is not on the screen».
@MainActor
final class TheCapsuleStaysUpOverAShortShotTests: XCTestCase {

    private var toasts: [ShotToast] = []
    private var mounts: [MountedRender] = []
    private let clock = StepClock()

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        for mount in mounts { mount.drop() }
        mounts = []
        clock.finish()
        super.tearDown()
    }

    /// What one run of the capsule's coming up under a pointer that does not move saw.
    private struct Watched {
        var hovers: [Bool] = []
        var rebuilds = 0
        var outside: [Int] = []
        var cellsAtEnd = 0
        var hoveringAtEnd = false
        var heldAtEnd = false
        var areasAtStart = 0
    }

    /// The pointer's way in is `mouseEntered`; then `turns` turns of the run loop, after each of which the view whose
    /// frame changed is given the `updateTrackingAreas` AppKit gives it.
    private func rest(on shots: [(width: Int, height: Int)], turns: Int = 60, row: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) throws -> Watched {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        for shot in shots {
            toast.showDone(try ShotToastRig.picture(width: shot.width, height: shot.height), caption: "x", file: nil)
        }
        if row { toast.unfold() }
        let size = NSHostingView(rootView: ShotToastView(model: toast.model)).fittingSize
        let mount = MountedRender(ShotToastView(model: toast.model), width: size.width, height: size.height, appearance: .aqua)
        mounts.append(mount)
        mount.settle(10)
        let host = mount.host
        // In the row the pointer rests on the first of the row's views; the capsule follows `focus`, not `hovering`.
        let drag = try XCTUnwrap(row ? host.everyView(ofType: ShotDragView.self).first : toast.model.anchor as? ShotDragView,
                                 "no hover view to rest on", file: file, line: line)
        XCTAssertFalse(toast.model.hovering, "the control: no pointer yet", file: file, line: line)

        var watched = Watched()
        let reported = drag.onHover
        drag.onHover = { over in
            watched.hovers.append(over)
            reported(over)
        }
        // As AppKit does when the view comes on a window: one area, before the pointer is anywhere.
        drag.updateTrackingAreas()
        watched.areasAtStart = drag.trackingAreas.count
        var frame = drag.convert(drag.bounds, to: host)
        // The pointer rests on the middle of the picture, the one place that is the picture on every shot.
        let picture = drag.pictureFrame
        let pointer = drag.convert(NSPoint(x: picture.midX, y: picture.midY), to: host)
        let number = mount.window?.windowNumber ?? 0
        let entering = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                            windowNumber: number, context: nil, eventNumber: 0,
                                                            trackingNumber: 0, userData: nil))
        let leaving = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                                           windowNumber: number, context: nil, eventNumber: 0,
                                                           trackingNumber: 0, userData: nil))
        drag.mouseEntered(with: entering)

        for turn in 0..<turns {
            mount.settle(1)
            let now = drag.convert(drag.bounds, to: host)
            if !now.insetBy(dx: -0.01, dy: -0.01).contains(pointer) { watched.outside.append(turn) }
            guard now != frame else { continue }
            frame = now
            let before = drag.trackingAreas.first
            drag.updateTrackingAreas()
            guard let after = drag.trackingAreas.first, after !== before else { continue }
            watched.rebuilds += 1
            // Inferred, not measured: the area the pointer was inside is gone, and says so.
            if before != nil { drag.mouseExited(with: leaving) }
        }
        watched.cellsAtEnd = host.everyView(named: "_FocusRingView").count
        watched.hoveringAtEnd = row ? toast.model.focus != nil : toast.model.hovering
        watched.heldAtEnd = row ? toast.model.unfolded : toast.holds.contains(.pointer)
        return watched
    }

    /// The same claims for every case, in the words of what went wrong.
    private func assertStays(_ watched: Watched, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(watched.areasAtStart, 1, "\(name): the control: AppKit's first call built one tracking area", file: file, line: line)
        XCTAssertTrue(watched.outside.isEmpty,
                      "\(name): the pointer on the picture was outside the hover view on turns \(watched.outside)", file: file, line: line)
        XCTAssertEqual(watched.rebuilds, 0,
                       "\(name): the hover view's tracking area was rebuilt \(watched.rebuilds) times while the capsule came up: each rebuild is an exit for a pointer that did not move",
                       file: file, line: line)
        XCTAssertEqual(watched.hovers, [true],
                       "\(name): the pointer reported \(watched.hovers) (true is the enter; any false is the exit that takes the capsule from under it)",
                       file: file, line: line)
        XCTAssertTrue(watched.hoveringAtEnd, "\(name): the pointer is on the shot and the model says it is not", file: file, line: line)
        XCTAssertTrue(watched.heldAtEnd, "\(name): the pointer is on the shot and the lifetime is not held by it", file: file, line: line)
        XCTAssertGreaterThanOrEqual(watched.cellsAtEnd, 2,
                                    "\(name): the capsule is not on the screen (\(watched.cellsAtEnd) cells; Copy and ✕ at the least)",
                                    file: file, line: line)
    }

    // MARK: Cases

    /// A short, wide shot: 1600×100 stands 200×12.5, which is lower than the capsule's `reach`.
    func testAShortWideShot() throws {
        for (width, height) in [(1600, 100), (800, 50), (300, 60)] {
            let shot = ShotThumbnail.fitted(pixels: CGSize(width: width, height: height))
            XCTAssertLessThan(shot.height, ShotCapsule.reach, "the control: \(width)×\(height) is lower than the capsule")
            XCTAssertGreaterThan(shot.width, ShotCapsule.widest, "the control: \(width)×\(height) is wider than the capsule")
            assertStays(try rest(on: [(width, height)]), "\(width)×\(height)")
        }
    }

    /// A tiny shot: narrower and lower than the capsule, so the hover view grows both ways.
    func testATinyShot() throws {
        for (width, height) in [(40, 30), (1, 1), (60, 20)] {
            assertStays(try rest(on: [(width, height)]), "\(width)×\(height)")
        }
    }

    /// The stack: three shots folded, the newest of them short. The capsule on a pile is the group's.
    func testAPileOfShortShots() throws {
        assertStays(try rest(on: [(1600, 100), (1600, 100), (1600, 100)]), "a pile of three 1600×100")
        assertStays(try rest(on: [(1600, 900), (800, 400), (1600, 100)]), "a pile whose newest is 1600×100 on two taller ones")
    }

    /// The control: a shot and a pile whose newest holds the capsule inside its picture. Green on the code as it is;
    /// a fix that rebuilds the area for these goes red.
    func testATallShotAndATallPileAreTheControl() throws {
        assertStays(try rest(on: [(1600, 900)]), "1600×900")
        assertStays(try rest(on: [(1600, 900), (1600, 900), (1600, 900)]), "a pile of three 1600×900")
    }

    /// The unfolded row, where `focus` replaces `hovering` as what raises the capsule: the same shots, the same rest.
    func testTheRowOfShortShots() throws {
        assertStays(try rest(on: [(1600, 100), (1600, 100), (1600, 100)], row: true), "a row of three 1600×100")
        assertStays(try rest(on: [(40, 30), (40, 30)], row: true), "a row of two 40×30")
    }

    /// What the one surviving tracking area must still be: the same object after every change of the view's frame
    /// (a fix that rebuilds it is the defect), and one that follows the frame (`.inVisibleRect`, no rect of its own),
    /// since a fixed rect would be the old size's and the pointer would be inside the view and outside the area.
    func testTheOneAreaIsTheSameAndFollowsTheFrame() throws {
        let drag = ShotDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 12))
        drag.updateTrackingAreas()
        let area = try XCTUnwrap(drag.trackingAreas.first, "the first call built no area")
        for size in [NSSize(width: 200, height: 94), NSSize(width: 40, height: 30), NSSize(width: 300, height: 12)] {
            drag.setFrameSize(size)
            drag.updateTrackingAreas()
            XCTAssertEqual(drag.trackingAreas.count, 1, "\(size): one area at all times")
            XCTAssertTrue(drag.trackingAreas.first === area, "\(size): the area was replaced by a new one")
        }
        XCTAssertTrue(area.options.contains(.inVisibleRect), "the area does not follow the view's rect")
        XCTAssertEqual(area.rect, .zero, "the area carries a rect of its own, which is the old frame's")
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited) && area.options.contains(.activeAlways),
                      "the area lost the options that report enter and exit with no window state")
        XCTAssertTrue(area.owner === drag, "the area's owner is not the view")
    }
}
