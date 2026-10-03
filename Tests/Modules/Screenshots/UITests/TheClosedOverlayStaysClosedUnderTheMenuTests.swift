import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **What closing the overlay ends, seen from the ⋯ menu:** a pick chosen from a menu made before the close writes
/// nothing to the editor's memory (`close()` clears `edit`), and a menu open at the close stops tracking (`close()` cancels
/// it) instead of outliving the overlay.
@MainActor
final class TheClosedOverlayStaysClosedUnderTheMenuTests: XCTestCase {

    private var results: [OverlayResult] = []

    private func build(store: NamespacedStore) throws -> CaptureOverlay {
        let frames = try OverlayRig.frames(scale: 1)
        let overlay = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(overlay.build())
        let display = try XCTUnwrap(frames.first?.id)
        overlay.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: display)
        return overlay
    }

    private func memory() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    private func choose(_ title: String, in menu: NSMenu) throws {
        menu.delegate?.menuNeedsUpdate?(menu)
        func flat(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(flat) ?? []) } }
        let item = try XCTUnwrap(flat(menu).first { $0.title == title }, "no item «\(title)»")
        let parent = try XCTUnwrap(item.menu)
        parent.performActionForItem(at: parent.index(of: item))
    }

    /// The control: a tool chosen from a live overlay's menu is remembered. After the close nothing is.
    func testAPickAfterTheCloseIsNotRemembered() throws {
        AppLanguage.override = .en
        defer { AppLanguage.override = nil }
        let live = memory()
        let liveOverlay = try build(store: live)
        defer { liveOverlay.close() }
        try choose(ScStr.tool(.rectangle), in: EditorMenu.make(for: liveOverlay.bars))
        XCTAssertEqual(EditorMemory.read(live).tool, .rectangle, "the control: a pick on a live overlay is remembered")

        for title in [ScStr.tool(.rectangle), ScStr.select, ScStr.fill] {
            let store = memory()
            let overlay = try build(store: store)
            let menu = EditorMenu.make(for: overlay.bars)
            overlay.close()
            try choose(title, in: menu)
            XCTAssertNil(EditorMemory.read(store).tool, "«\(title)» chosen after the close wrote the tool to memory")
            XCTAssertEqual(EditorMemory.read(store).style(for: .rectangle), .standard, "«\(title)» chosen after the close wrote the style to memory")
            XCTAssertTrue(results.isEmpty)
        }
        // Thickness and fill sent through the bars go through the same door.
        let store = memory()
        let overlay = try build(store: store)
        overlay.close()
        overlay.bars.perform(.thickness(.thick))
        overlay.bars.perform(.toggleFill)
        XCTAssertEqual(EditorMemory.read(store).style(for: .rectangle), .standard, "a pick after the close was remembered")
    }

    /// `close()` clears the owner too: the doors that do not go through `edit` (Esc asks `escapeAsked`, Return takes the
    /// whole display) finish with `onFinish`, and a closed overlay has none to call.
    func testEscAndReturnAfterTheCloseDeliverNothing() throws {
        for code: UInt16 in [53, 36, 76] {
            results = []
            let overlay = try build(store: memory())
            overlay.close()
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                       context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            overlay.keyDown(event)
            XCTAssertTrue(results.isEmpty, "key \(code) after the close reached the owner: \(results)")
        }
    }

    /// The overlay is closed while ⋯'s menu is tracking: `popUp` must come back by itself. A timer in the common modes (it
    /// fires inside the menu's own loop) closes the overlay; a later one is the rescue, which ends the loop with an Esc
    /// and marks that the close alone did not.
    func testTheCloseEndsTheTrackingOfAnOpenMenu() throws {
        let overlay = try build(store: memory())
        var closed = false
        var rescued = false
        let closer = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated { closed = true; overlay.close() }
        }
        let rescue = Timer(timeInterval: 3, repeats: false) { _ in
            MainActor.assumeIsolated {
                rescued = true
                for down in [true, false] {
                    if let esc = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                  isARepeat: false, keyCode: 53) { NSApp.postEvent(esc, atStart: true) }
                }
            }
        }
        RunLoop.main.add(closer, forMode: .common)
        RunLoop.main.add(rescue, forMode: .common)
        overlay.bars.openMenu()
        closer.invalidate(); rescue.invalidate()
        XCTAssertTrue(closed, "the menu never ran its loop: the timer did not fire inside popUp")
        XCTAssertFalse(rescued, "the menu was still tracking after the overlay closed: it ended only by the rescue")
    }
}
