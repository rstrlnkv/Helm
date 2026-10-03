import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **An area picked from the panel is a plain crop: no palette, no editor, whatever is pressed on the overlay.** And the
/// area shortcut, which shares the overlay, still opens the palette after the drag (the control that proves the flag is
/// the overlay's own and not leaked from one capture to the next).
@MainActor
final class TheAreaFromTheBarNeverOpensThePaletteTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func pickedArea(_ values: [String: Any] = [:], remembered: RememberedSelection? = nil) async throws -> (PanelRig.Rig, CaptureOverlay) {
        let box = try PanelRig.rig(values: values)
        boxes.append(box)
        remembered?.write(to: box.store)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        return (box, try XCTUnwrap(box.held.overlay))
    }

    private func noPalette(_ box: PanelRig.Rig, _ overlay: CaptureOverlay, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        for frame in (try? OverlayRig.frames()) ?? [] {
            XCTAssertNil(overlay.chrome(on: frame.id), "\(when): the palette's place is held on a display", file: file, line: line)
            XCTAssertFalse(overlay.view(for: frame.id)?.paletteIsShown ?? false, "\(when): the palette is shown", file: file, line: line)
        }
    }

    func testNoToolKeyNoUndoNoDeleteNoArrowBuildsAnEditorUnderAnAreaTheBarPicked() async throws {
        let (box, overlay) = try await pickedArea()
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        noPalette(box, overlay, "after the drag")
        // The editor's keys, read by their physical codes: r, e, a, p, t, h, b, l, ⌘Z, ⇧⌘Z, delete, ⌘C, ⌘S, arrows, tab, A.
        for (code, chars, flags): (UInt16, String, NSEvent.ModifierFlags) in
            [(15, "r", []), (14, "e", []), (0, "a", []), (35, "p", []), (17, "t", []), (4, "h", []), (11, "b", []), (37, "l", []),
             (6, "z", .command), (6, "z", [.command, .shift]), (51, "\u{7f}", []), (8, "c", .command), (1, "s", .command),
             (123, "\u{f702}", []), (124, "\u{f703}", .shift), (126, "\u{f700}", []), (125, "\u{f701}", .option), (48, "\t", []), (49, " ", [])] {
            overlay.keyDown(key(code, chars, flags: flags))
            noPalette(box, overlay, "after key \(code)")
        }
        XCTAssertTrue(overlay.isOpen, "a key finished the overlay")
        XCTAssertTrue(box.controller.bar.model.hasTarget, "a key lost the area")
        XCTAssertEqual(box.disk.written, 0, "a key delivered a shot")
        overlay.perform(.tool(.rectangle))
        overlay.perform(.exit(.confirm))
        noPalette(box, overlay, "after the editor's own door was knocked on")
        XCTAssertTrue(overlay.isOpen)
        XCTAssertEqual(box.disk.written, 0)
    }

    func testReturnAndCaptureTakeTheAreaAsAPlainCropWithNoLayers() async throws {
        let (box, overlay) = try await pickedArea()
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        overlay.keyDown(key(36, "\r"))
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(PanelRig.size(of: box.disk.last), PanelRig.area.size)
        XCTAssertEqual(box.screen.freezes, 1)
    }

    func testASecondDragReplacesTheAreaAndStillOpensNoPalette() async throws {
        let (box, overlay) = try await pickedArea()
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        PanelRig.drag(overlay, on: box.display, CGRect(x: 300, y: 300, width: 100, height: 120))
        noPalette(box, overlay, "after the second drag")
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(PanelRig.size(of: box.disk.last), CGSize(width: 100, height: 120), "the first area was taken, not the replacement")
    }

    func testARememberedAreaIsATargetAtOnceAndReturnTakesItWithNoPalette() async throws {
        let record = try XCTUnwrap(RememberedSelection(display: "UUID-0", rect: CGRect(x: 20, y: 30, width: 200, height: 150)))
        let (box, again) = try await pickedArea([ScreenshotsSettings.Key.rememberSelection: true], remembered: record)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "the remembered area is not offered to Capture at once")
        noPalette(box, again, "with a remembered area")
        again.keyDown(key(36, "\r"))
        await waitUntil("the shot was written") { box.disk.written == 1 }
        XCTAssertEqual(PanelRig.size(of: box.disk.last), CGSize(width: 200, height: 150))
    }

    func testTheShortcutStillOpensThePaletteAfterTheDragAndAfterAPanelPickBeforeIt() async throws {
        let (box, overlay) = try await pickedArea()
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await waitUntil("the machine was freed") { box.disk.written == 1 && !box.controller.isBusy }
        box.held.overlay = nil
        box.controller.begin(.area)
        await waitUntil("the shortcut's overlay opened") { box.held.overlay != nil }
        let shortcut = try XCTUnwrap(box.held.overlay)
        XCTAssertFalse(shortcut.selectionOnly, "the panel's flag leaked into the shortcut's overlay")
        PanelRig.drag(shortcut, on: box.display, PanelRig.area)
        XCTAssertNotNil(shortcut.chrome(on: box.display), "⇧⌘4 no longer opens the palette after the drag")
        XCTAssertTrue(try XCTUnwrap(shortcut.view(for: box.display)).paletteIsShown)
    }

    func testTheShortcutOpenedFirstAndThePanelAfterItAreTwoOverlaysNotOne() async throws {
        let box = try PanelRig.rig()
        boxes.append(box)
        box.controller.begin(.area)
        await waitUntil("the shortcut's overlay opened") { box.held.overlay != nil }
        let shortcut = try XCTUnwrap(box.held.overlay)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await grace(0.2)
        XCTAssertTrue(box.held.overlay === shortcut, "a second overlay was opened over the shortcut's")
        XCTAssertEqual(box.screen.freezes, 1, "the screen was frozen over an overlay")
        XCTAssertFalse(shortcut.selectionOnly)
    }
}
