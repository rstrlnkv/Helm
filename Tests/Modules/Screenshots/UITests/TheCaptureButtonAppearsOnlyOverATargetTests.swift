import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Capture is drawn only where it would take something.** Screen mode always; Window mode while the pointer is over a
/// window of the overlay; Area mode while an area is drawn or remembered. And the way it goes away: a drag begun, a
/// window left, a mode changed, the shot taken, the overlay ended by any door. With an overlay open and nothing to take,
/// Capture does nothing and Return on the panel does nothing; with no overlay open, either one opens it.
@MainActor
final class TheCaptureButtonAppearsOnlyOverATargetTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func opened(_ mode: PanelMode, values: [String: Any] = [:], remembered: RememberedSelection? = nil) async throws -> (PanelRig.Rig, CaptureOverlay) {
        let box = try PanelRig.rig(values: values)
        boxes.append(box)
        remembered?.write(to: box.store)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(mode)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        return (box, try XCTUnwrap(box.held.overlay))
    }

    func testTheTruthTableOfWhatCaptureIsDrawnFor() {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        for mode in [PanelMode.screen, .window, .area] {
            for target in [false, true] {
                model.choose(mode)
                model.hasTarget = target
                XCTAssertEqual(model.showsCapture, mode == .screen || target, "\(mode) with target \(target)")
            }
        }
    }

    func testADragInProgressIsNoTargetAndTheReleaseMakesOne() async throws {
        let (box, overlay) = try await opened(.area)
        XCTAssertFalse(box.controller.bar.model.showsCapture)
        overlay.mouseDown(on: box.display, at: PanelRig.area.origin, flags: [])
        overlay.mouseDragged(on: box.display, at: CGPoint(x: PanelRig.area.maxX, y: PanelRig.area.maxY), flags: [])
        XCTAssertFalse(box.controller.bar.model.showsCapture, "Capture is offered while the area is still being drawn")
        overlay.mouseUp(on: box.display)
        XCTAssertTrue(box.controller.bar.model.showsCapture)
    }

    /// A click that never moved is not a selection. It must not take the area that was drawn with it: the area stays as
    /// drawn until a new drag replaces it (`CaptureOverlay.selectionOnly`).
    func testAClickWithNoDragLeavesTheAreaThatWasDrawn() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        XCTAssertTrue(box.controller.bar.model.hasTarget)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "a stray click took the drawn area away from Capture")
        XCTAssertNotNil(overlay.preselection)
    }

    func testAnUnusableDragIsNoTarget() async throws {
        let (box, overlay) = try await opened(.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseDragged(on: box.display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertFalse(box.controller.bar.model.hasTarget)
        box.controller.capture(from: .area)
        await grace(0.15)
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertTrue(overlay.isOpen, "Capture over no target closed the overlay")
        XCTAssertTrue(box.controller.isBusy)
    }

    func testCaptureWithNoTargetDoesNothingInEitherModeAndReturnTooAndTheOverlayStaysUp() async throws {
        for mode in [PanelMode.area, .window] {
            let (box, overlay) = try await opened(mode)
            box.controller.capture(from: mode)
            overlay.keyDown(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                             characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
            await grace(0.15)
            XCTAssertEqual(box.disk.written, 0, "\(mode): a shot of nothing")
            XCTAssertTrue(overlay.isOpen, "\(mode): the overlay went")
            XCTAssertEqual(box.screen.freezes, 1, "\(mode): another freeze")
        }
    }

    func testTheOtherModesTargetIsDroppedAndDoesNotComeBack() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.bar.model.choose(.window)
        XCTAssertFalse(box.controller.bar.model.hasTarget)
        box.controller.bar.model.choose(.area)
        XCTAssertFalse(box.controller.bar.model.hasTarget, "the area came back by itself after a trip through Window")
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertFalse(box.controller.bar.model.hasTarget, "a window under the pointer is a target in Area mode")
    }

    func testAWindowTargetIsLostWhenThePointerLeavesAndWhenTheModeChanges() async throws {
        let (box, overlay) = try await opened(.window)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(box.controller.bar.model.hasTarget)
        box.controller.bar.model.choose(.area)
        XCTAssertFalse(box.controller.bar.model.hasTarget, "the window stayed a target in Area mode")
        box.controller.bar.model.choose(.window)
        XCTAssertFalse(box.controller.bar.model.hasTarget, "the window came back without the pointer")
    }

    func testARememberedAreaIsATargetFromTheStartOnlyInAreaModeAndOnlyWhereItFits() async throws {
        let record = try XCTUnwrap(RememberedSelection(display: "UUID-0", rect: CGRect(x: 20, y: 30, width: 200, height: 150)))
        let remember: [String: Any] = [ScreenshotsSettings.Key.rememberSelection: true]
        let (box, _) = try await opened(.area, values: remember, remembered: record)
        XCTAssertTrue(box.controller.bar.model.hasTarget)
        let (window, _) = try await opened(.window, values: remember, remembered: record)
        XCTAssertFalse(window.controller.bar.model.hasTarget, "a remembered area is a target in Window mode")
        let elsewhere = try XCTUnwrap(RememberedSelection(display: "UNPLUGGED", rect: CGRect(x: 20, y: 30, width: 200, height: 150)))
        let (gone, _) = try await opened(.area, values: remember, remembered: elsewhere)
        XCTAssertFalse(gone.controller.bar.model.hasTarget, "an area of a display that is gone is a target")
        let off = try await opened(.area, values: [ScreenshotsSettings.Key.rememberSelection: false], remembered: record)
        XCTAssertFalse(off.0.controller.bar.model.hasTarget, "the memory is off and the area is a target")
    }

    func testEveryDoorOutTakesTheTargetAway() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.rightMouseDown()
        XCTAssertFalse(box.controller.bar.model.hasTarget, "Esc left Capture offered")
        let (second, secondOverlay) = try await opened(.area)
        PanelRig.drag(secondOverlay, on: second.display, PanelRig.area)
        second.controller.bar.model.cancel()
        XCTAssertFalse(second.controller.bar.model.hasTarget, "✕ left Capture offered")
        let (third, thirdOverlay) = try await opened(.area)
        PanelRig.drag(thirdOverlay, on: third.display, PanelRig.area)
        third.controller.bar.model.choose(.screen)
        XCTAssertFalse(third.controller.bar.model.hasTarget, "Screen mode kept the area as a target")
        XCTAssertTrue(third.controller.bar.model.showsCapture)
        let (fourth, fourthOverlay) = try await opened(.area)
        PanelRig.drag(fourthOverlay, on: fourth.display, PanelRig.area)
        fourth.controller.teardown()
        XCTAssertFalse(fourth.controller.bar.model.hasTarget, "the module's end left Capture offered")
    }
}
