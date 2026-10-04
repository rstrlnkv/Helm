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

/// **The ⋯ menu under the inputs its brief did not name:** Select while a stroke is under the pointer, Select twice, the
/// overlay closed while the menu is open (`NSMenu.popUp` runs its own loop and returns after the item's action, and the
/// call that opened it keeps the overlay alive, so an item chosen after the module was switched off or the capture was
/// cancelled still reaches `perform`), and the menu made for a closed overlay.
@MainActor
final class TheMoreMenuMeetsInputsNobodyPlannedTests: XCTestCase {

    private var results: [OverlayResult] = []
    private var rigged: [CaptureOverlay] = []

    override func tearDown() {
        rigged.forEach { $0.close() }
        rigged = []
        results = []
        super.tearDown()
    }

    private func build() throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let built = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300)) { [weak self] in self?.results.append($0) }
        rigged.append(built.overlay)
        return built
    }

    private func click(_ title: String, in menu: NSMenu) throws {
        menu.delegate?.menuNeedsUpdate?(menu)
        func flat(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(flat) ?? []) } }
        let item = try XCTUnwrap(flat(menu).first { $0.title == title }, "no item «\(title)»")
        let parent = try XCTUnwrap(item.menu)
        parent.performActionForItem(at: parent.index(of: item))
    }

    /// Select puts the tool down and **stays down**: sent twice it is still no tool (the tool items toggle, Select does not),
    /// and a drag after it makes no layer.
    func testSelectIsNoToolWhateverIsSentAndADragAfterItDrawsNothing() throws {
        AppLanguage.override = .en
        defer { AppLanguage.override = nil }
        let (overlay, display, view) = try build()
        overlay.perform(.tool(.rectangle))
        XCTAssertEqual(overlay.palette.tool, .rectangle, "the control: a tool is chosen first")
        let menu = EditorMenu.make(for: overlay.palette)
        try click(ScStr.select, in: menu)
        XCTAssertNil(overlay.palette.tool, "Select did not put the tool down")
        try click(ScStr.select, in: menu)
        XCTAssertNil(overlay.palette.tool, "Select twice picked a tool: it toggles like a tool item")
        let before = view.drawnShapes.count
        overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, before, "a drag after Select drew an object")
        // And the next tool item still works: Select is not a latch.
        try click(ScStr.tool(.rectangle), in: menu)
        XCTAssertEqual(overlay.palette.tool, .rectangle)
    }

    /// Select sent while a stroke is under the pointer (only the menu's item sends it, `EditorMenu.swift`, and the menu cannot be opened with the button down) acts
    /// as a tool key does there: the tool is put down at once, and **the stroke in hand is not lost**: the release makes
    /// it, and the next drag selects instead of drawing.
    func testSelectWhileAStrokeIsUnderThePointerKeepsTheStroke() throws {
        let (overlay, display, view) = try build()
        overlay.perform(.tool(.rectangle))
        let before = view.drawnShapes.count
        overlay.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 250), flags: [])
        XCTAssertEqual(view.drawnShapes.count, before + 1, "the control: the draft is on the screen")
        overlay.perform(.select)
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, before + 1, "the stroke was lost to a Select sent mid-drag")
        XCTAssertNil(overlay.palette.tool)
        overlay.mouseDown(on: display, at: CGPoint(x: 350, y: 300), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 450, y: 380), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, before + 1, "a second drag after Select drew")
        XCTAssertTrue(results.isEmpty)
    }

    /// The control for the next one: an item chosen from a menu of a live overlay does deliver.
    func testAnItemChosenFromTheMenuOfALiveOverlayDelivers() throws {
        AppLanguage.override = .en
        defer { AppLanguage.override = nil }
        let (overlay, _, _) = try build()
        try click(ScStr.save, in: EditorMenu.make(for: overlay.palette))
        guard case .edited(_, _, _, .save)? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    /// **The overlay is closed while the menu is open.** The capture was cancelled or the module switched off
    /// (`ScreenshotsCapture.cancel` → `overlay.close()`), the menu's loop goes on, and the person chooses Save: the item
    /// goes through `palette.perform` into an overlay that is closed, finishes it, and `overlayFinished` starts a delivery that
    /// nothing has cancelled. Nothing may leave a closed overlay.
    func testAnItemChosenAfterTheOverlayWasClosedDeliversNothing() throws {
        AppLanguage.override = .en
        defer { AppLanguage.override = nil }
        for title in [ScStr.save, ScStr.tool(.rectangle)] {
            results = []
            let (overlay, _, _) = try build()
            let menu = EditorMenu.make(for: overlay.palette)
            overlay.close()
            try click(title, in: menu)
            XCTAssertTrue(results.isEmpty, "«\(title)» chosen from the menu of a closed overlay delivered \(results)")
        }
        // The other exits go through the same door.
        for exit in [EditorExit.confirm, .copy, .save] {
            results = []
            let (overlay, _, _) = try build()
            overlay.close()
            overlay.palette.perform(.exit(exit))
            XCTAssertTrue(results.isEmpty, "\(exit) reached the closed overlay's owner: \(results)")
        }
    }
}
