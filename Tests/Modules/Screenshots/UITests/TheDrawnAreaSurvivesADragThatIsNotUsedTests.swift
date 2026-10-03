import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **On the panel's overlay the area that was drawn stays until a drag that is usable replaces it, and the shortcut's
/// overlay is as it was.** A click that never moved, a drag of less than a point, a press on a display the freeze does
/// not have, a mode trip, Esc: each ends in the one state that is true — the old area, or none — and what Capture takes
/// is that and not the half of a drag. On ⇧⌘4's overlay (`selectionOnly` false) a new press still takes the remembered
/// area away, as it always did.
@MainActor
final class TheDrawnAreaSurvivesADragThatIsNotUsedTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private let remembered = CGRect(x: 20, y: 30, width: 200, height: 150)

    private func opened(_ mode: PanelMode, fromMemory: Bool = false) async throws -> (PanelRig.Rig, CaptureOverlay) {
        let box = try PanelRig.rig(values: fromMemory ? [ScreenshotsSettings.Key.rememberSelection: true] : [:])
        boxes.append(box)
        if fromMemory { try XCTUnwrap(RememberedSelection(display: "UUID-0", rect: remembered)).write(to: box.store) }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(mode)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        return (box, try XCTUnwrap(box.held.overlay))
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)!
    }

    func testAClickWithNoDragAfterAnAreaFromTheRememberedSelectionKeepsIt() async throws {
        let (box, overlay) = try await opened(.area, fromMemory: true)
        XCTAssertEqual(overlay.preselection?.rect, remembered, "the harness' remembered selection did not land")
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "a stray click took the remembered area away")
        XCTAssertEqual(overlay.preselection?.rect, remembered)
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(PanelRig.size(of: box.disk.last), remembered.size, "Capture took something other than the area that was kept")
    }

    func testADragOfLessThanAPointAfterAnAreaKeepsIt() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseDragged(on: box.display, at: CGPoint(x: 700.4, y: 600.4), flags: [])
        XCTAssertFalse(box.controller.bar.model.hasTarget, "Capture is offered while a new drag is being drawn")
        overlay.mouseUp(on: box.display)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "a drag of 0.4 pt took the area away")
        XCTAssertEqual(overlay.preselection?.rect, PanelRig.area)
    }

    func testAUsableDragAfterAnAreaReplacesItAndAnUnusableOneAfterThatKeepsTheNewOne() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        let second = CGRect(x: 500, y: 400, width: 100, height: 80)
        PanelRig.drag(overlay, on: box.display, second)
        XCTAssertEqual(overlay.preselection?.rect, second)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 10, y: 10), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertEqual(overlay.preselection?.rect, second, "the click brought back the first area, not the one that replaced it")
    }

    /// A press on a display the freeze has not got: nothing is dragged, nothing is lost.
    func testAPressOnADisplayTheFreezeDoesNotHaveLeavesTheAreaAlone() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        let stranger = DisplayID(box.display.raw &+ 987_654)
        overlay.mouseDown(on: stranger, at: CGPoint(x: 5, y: 5), flags: [])
        overlay.mouseDragged(on: stranger, at: CGPoint(x: 90, y: 90), flags: [])
        overlay.mouseUp(on: stranger)
        XCTAssertEqual(overlay.preselection?.rect, PanelRig.area)
        XCTAssertTrue(box.controller.bar.model.hasTarget)
    }

    /// The same, on another real display where this Mac has one.
    func testAClickOnAnotherRealDisplayLeavesTheAreaAlone() async throws {
        let frames = try OverlayRig.frames(scale: 1)
        guard frames.count > 1 else { throw XCTSkip("one display on this Mac: a click on another one cannot be made") }
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        let other = frames[1].id
        overlay.mouseDown(on: other, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseUp(on: other)
        XCTAssertEqual(overlay.preselection?.rect, PanelRig.area, "a click on the other display took the area of this one")
        XCTAssertTrue(box.controller.bar.model.hasTarget)
    }

    func testEscAfterAFailedDragWithNothingDrawnEndsTheCaptureAndTakesNothing() async throws {
        let (box, overlay) = try await opened(.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertFalse(box.controller.bar.model.hasTarget, "a click made a target out of nothing")
        overlay.keyDown(key(53))
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertFalse(overlay.isOpen)
        XCTAssertEqual(box.disk.written, 0)
    }

    func testReturnAfterAFailedDragTakesTheAreaThatWasDrawn() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseUp(on: box.display)
        overlay.keyDown(key(36))
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(PanelRig.size(of: box.disk.last), PanelRig.area.size)
    }

    func testEscWhileANewDragIsHeldEndsTheCaptureAndTakesNothing() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseDragged(on: box.display, at: CGPoint(x: 800, y: 700), flags: [])
        overlay.keyDown(key(53))
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertFalse(overlay.isOpen)
    }

    /// A trip through Window while a new drag is held: the old area is gone for good, and the release that comes late
    /// does not bring it back.
    func testAModeTripWhileADragIsHeldDoesNotResurrectTheOldAreaOnTheLateRelease() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        box.controller.bar.model.choose(.window)
        box.controller.bar.model.choose(.area)
        overlay.mouseUp(on: box.display)
        XCTAssertFalse(box.controller.bar.model.hasTarget, "the area that the mode trip dropped came back on the release")
        XCTAssertNil(overlay.preselection)
    }

    /// A second press with no release in between must not lose the area the first one hid.
    func testASecondPressWithNoReleaseBetweenKeepsTheAreaTheFirstOneHid() async throws {
        let (box, overlay) = try await opened(.area)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.mouseDown(on: box.display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseDown(on: box.display, at: CGPoint(x: 710, y: 610), flags: [])
        overlay.mouseUp(on: box.display)
        XCTAssertEqual(overlay.preselection?.rect, PanelRig.area, "a second press lost the area the first had hidden")
    }

    // MARK: - The shortcut's overlay is as it was

    private func shortcutOverlay(preselection: CGRect?) throws -> (CaptureOverlay, DisplayID) {
        let frames = try OverlayRig.frames(scale: 1)
        let id = try XCTUnwrap(frames.first?.id)
        let overlay = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), mode: .area,
                                     preselection: preselection.map { (id, $0) }, store: nil) { _ in }
        XCTAssertTrue(overlay.build())
        return (overlay, id)
    }

    func testOnTheShortcutsOverlayAClickTakesTheRememberedAreaAwayAsItAlwaysDid() throws {
        let (overlay, display) = try shortcutOverlay(preselection: remembered)
        defer { overlay.close() }
        XCTAssertEqual(overlay.preselection?.rect, remembered)
        overlay.mouseDown(on: display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertNil(overlay.preselection, "the shortcut's overlay gave a click the area back: it is the panel's rule")
    }

    func testOnTheShortcutsOverlayAnUnusableDragTakesTheRememberedAreaAwayToo() throws {
        let (overlay, display) = try shortcutOverlay(preselection: remembered)
        defer { overlay.close() }
        overlay.mouseDown(on: display, at: CGPoint(x: 700, y: 600), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 700.3, y: 600.3), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertNil(overlay.preselection)
    }
}
