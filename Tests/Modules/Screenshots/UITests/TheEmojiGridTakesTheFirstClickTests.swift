import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// A window that can be key and is not: the state the overlay's panel is in when the person's own application has the keyboard and the
/// first click lands on Helm.
private final class NeverKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func makeKey() {}
    override func makeKeyAndOrderFront(_ sender: Any?) { orderFrontRegardless() }
}

/// **A press on the emoji grid is the grid's: it picks on the first click, and it never places, draws, selects or starts an area.** The grid is
/// hosted by the palette's own hosting view, in a window that is not key, and a press is sent at every fourth point across it through
/// `NSWindow.sendEvent`, which is where AppKit decides whether a first click is spent on making the window key: the 24 emoji come back
/// through the model's door, each one, so no cell of the grid is a dead one. A press on the overlay's own grid (the padding, the gaps between
/// the cells, the cells) leaves no layer, no draft and no area: the same sweep, through the overlay's door. The grid is there while the Emoji
/// tool is chosen and nowhere else (no tool, another tool, the eraser, Crop), above the palette and clear of it, inside the display, with the
/// pop-over open or shut; a click on the picture places the emoji that was picked, and none before one is picked.
///
/// What it would print if it failed totally: a host that refuses the first mouse eats the first press, and the sweep picks nothing; a
/// press that falls through the grid to the picture puts a layer or an area under it.
@MainActor
final class TheEmojiGridTakesTheFirstClickTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 200, width: 500, height: 300)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func build(area: CGRect? = nil) throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let built = try OverlayRig.overlay(scale: 1, area: area ?? self.area) { [weak self] in self?.results.append($0) }
        overlay = built.overlay
        return built
    }

    private func grid(in view: OverlayView) -> EditorBarHostingView<EmojiGrid>? {
        view.subviews.compactMap { $0 as? EditorBarHostingView<EmojiGrid> }.first
    }

    private func palette(in view: OverlayView) -> NSView? { view.subviews.first { $0 is EditorBarHostingView<EditorPalette> } }

    /// A press and a release at `point` of `host`'s bounds, through the window's own `sendEvent`.
    private func press(_ host: NSView, at point: CGPoint) throws {
        let window = try XCTUnwrap(host.window)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    // MARK: The first click

    func testTheHostTakesTheFirstMouseAndNeverTheKeyboard() throws {
        let (overlay, _, view) = try build()
        overlay.perform(.tool(.emoji))
        let host = try XCTUnwrap(grid(in: view), "the Emoji tool is chosen and the overlay has no grid")
        XCTAssertFalse(host.isHidden)
        XCTAssertTrue(host.acceptsFirstMouse(for: nil), "the first click on the grid is spent on making the window key")
        XCTAssertFalse(host.acceptsFirstResponder, "the grid takes the keyboard: the editor's keys stop meaning what they meant")
    }

    func testEveryCellPicksOnAFirstClickInAWindowThatIsNotKey() throws {
        let model = EmojiGridModel()
        var picked: [String] = []
        model.pick = { picked.append($0) }
        let host = EditorBarHostingView(rootView: EmojiGrid(model: model))
        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 100, "control: the grid measured \(size)")
        let window = NeverKeyWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: size.width, height: size.height), styleMask: [.borderless],
                                    backing: .buffered, defer: false)
        window.contentView = host
        window.alphaValue = 0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        XCTAssertFalse(window.isKeyWindow, "control: the window is key, so no click on it is a first one")
        for y in stride(from: CGFloat(2), to: size.height, by: 4) {
            for x in stride(from: CGFloat(2), to: size.width, by: 4) { try press(host, at: CGPoint(x: x, y: y)) }
        }
        XCTAssertFalse(window.isKeyWindow, "a press on the grid made its window key")
        XCTAssertEqual(Set(picked), Set(EmojiSet.all), "the cells that never answered: \(Set(EmojiSet.all).subtracting(picked))")
        XCTAssertFalse(picked.isEmpty)
    }

    func testAPressOnTheOverlaysGridPlacesAndDrawsAndSelectsNothing() throws {
        let (overlay, id, view) = try build()
        overlay.perform(.tool(.emoji))
        overlay.perform(.pickEmoji("👍"))
        overlay.perform(.tool(.rectangle))
        // A box, taken, so that a press that falls through to the picture would let go of it or take another.
        ScreenAndFilePress.drag(overlay, id, from: CGPoint(x: 150, y: 250), to: CGPoint(x: 250, y: 330))
        overlay.perform(.select)
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 150, y: 290))
        overlay.perform(.tool(.emoji))
        let held = overlay.palette.selectedTool
        let host = try XCTUnwrap(grid(in: view))
        let layers = overlay.editedLayers
        XCTAssertEqual(layers.map(\.tool), [.rectangle])
        // Every point of the grid, through the overlay's door and through the view's own events, both.
        let frame = host.frame
        for y in stride(from: frame.minY + 1, to: frame.maxY, by: 6) {
            for x in stride(from: frame.minX + 1, to: frame.maxX, by: 6) {
                let local = CGPoint(x: x, y: view.bounds.height - y)
                XCTAssertTrue(view.emojiGridCovers(local), "the grid does not cover its own point \(local)")
                overlay.mouseDown(on: id, at: local, flags: [])
                overlay.mouseDragged(on: id, at: CGPoint(x: local.x + 5, y: local.y + 5), flags: [])
                overlay.mouseUp(on: id)
            }
        }
        XCTAssertEqual(overlay.editedLayers, layers, "a press on the grid changed the layers")
        XCTAssertEqual(overlay.palette.selectedTool, held, "a press on the grid took or let go of a layer")
        XCTAssertEqual(overlay.editedArea, area, "a press on the grid changed the area")
        XCTAssertTrue(results.isEmpty, "a press on the grid ended the capture: \(results)")
    }

    // MARK: Where the grid stands

    func testTheGridIsThereWhileTheEmojiToolIsChosenAndNowhereElse() throws {
        let (overlay, _, view) = try build()
        func shown() -> Bool { grid(in: view).map { !$0.isHidden } ?? false }
        XCTAssertFalse(shown(), "the grid is up before the tool is chosen")
        overlay.perform(.tool(.emoji))
        XCTAssertTrue(shown(), "no grid for the Emoji tool")
        overlay.perform(.tool(.pen))
        XCTAssertFalse(shown(), "another tool, the grid stays")
        overlay.perform(.tool(.emoji))
        XCTAssertTrue(shown())
        overlay.perform(.select)
        XCTAssertFalse(shown(), "Select, the grid stays")
        overlay.perform(.tool(.emoji))
        overlay.perform(.erase)
        XCTAssertFalse(shown(), "the eraser is on and the grid stays")
        overlay.perform(.erase)
        XCTAssertTrue(shown(), "the eraser is off again and the Emoji tool is still chosen, but the grid is gone")
        overlay.perform(.crop)
        XCTAssertFalse(shown(), "Crop is on and the grid stays")
        XCTAssertFalse(view.emojiGridCovers(CGPoint(x: view.bounds.midX, y: view.bounds.midY)))
        overlay.perform(.exit(.confirm))
        results = []
    }

    func testTheGridStandsClearOfThePaletteInsideTheDisplayWhereverTheAreaIs() throws {
        let areas = [CGRect(x: 50, y: 30, width: 300, height: 120), CGRect(x: 100, y: 200, width: 500, height: 300), CGRect(x: 700, y: 650, width: 250, height: 120),
                     CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 400, y: 790, width: 40, height: 10)]
        for rect in areas {
            for popover in [false, true] {
                overlay?.close()
                let (overlay, _, view) = try build(area: rect)
                overlay.perform(.tool(.emoji))
                if popover { overlay.perform(.thicknessAndOpacity(anchorX: 200)) }
                let host = try XCTUnwrap(grid(in: view), "\(rect)")
                let bar = try XCTUnwrap(palette(in: view), "\(rect)")
                let name = "area \(rect), pop-over \(popover)"
                XCTAssertFalse(host.isHidden, name)
                XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(host.frame), "\(name): the grid \(host.frame) leaves the display \(view.bounds)")
                XCTAssertFalse(host.frame.intersects(bar.frame), "\(name): the grid \(host.frame) covers the palette \(bar.frame)")
            }
        }
    }

    // MARK: Pick, then place

    func testAClickOnThePictureAfterAPickPlacesThatEmojiAndNoneBeforeOne() throws {
        let (overlay, id, view) = try build()
        overlay.perform(.tool(.emoji))
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 300, y: 300))
        XCTAssertTrue(overlay.editedLayers.isEmpty, "a click with no emoji picked placed something: \(overlay.editedLayers)")
        overlay.perform(.pickEmoji("👍🏽"))
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(overlay.editedLayers.map(\.text), ["👍🏽"])
        XCTAssertEqual(overlay.editedLayers.first?.tool, .emoji)
        let frame = try XCTUnwrap(overlay.editedLayers.first?.frame)
        XCTAssertEqual(frame.midX, 300, accuracy: 0.01)
        XCTAssertEqual(frame.midY, 300, accuracy: 0.01)
        // (The grid stands over the lower part of the area, above the palette: the next points are above it.)
        // Another pick, another click, and the first is still the first.
        overlay.perform(.pickEmoji("🔥"))
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 450, y: 260))
        XCTAssertEqual(overlay.editedLayers.map(\.text), ["👍🏽", "🔥"])
        // A click on the emoji just placed takes it and does not put a second on it.
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 450, y: 260))
        XCTAssertEqual(overlay.editedLayers.count, 2, "a click on an emoji put another one on it")
        // A click outside the area places nothing.
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(overlay.editedLayers.count, 2, "a click outside the area placed an emoji")
        // One undo step each.
        overlay.perform(.undo)
        XCTAssertEqual(overlay.editedLayers.map(\.text), ["👍🏽"])
        overlay.perform(.undo)
        XCTAssertTrue(overlay.editedLayers.isEmpty)
        _ = view
    }

    func testAPickThatIsNoEmojiOrComesWithAnotherToolIsIgnored() throws {
        let (overlay, id, _) = try build()
        overlay.perform(.pickEmoji("👍"))
        overlay.perform(.tool(.emoji))
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 300, y: 300))
        XCTAssertTrue(overlay.editedLayers.isEmpty, "a pick made with the pen chosen was kept for the Emoji tool")
        for junk in ["", "ab", "👍👍", "\u{200B}", "\u{FE0F}", "e" + String(repeating: "\u{0301}", count: 40)] {
            overlay.perform(.pickEmoji(junk))
            ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 300, y: 300))
            XCTAssertTrue(overlay.editedLayers.isEmpty, "the pick \(junk.debugDescription) placed \(overlay.editedLayers.map(\.text))")
        }
        overlay.perform(.pickEmoji("🇫🇷"))
        overlay.perform(.pickEmoji("ab"))
        ScreenAndFilePress.click(overlay, id, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(overlay.editedLayers.map(\.text), ["🇫🇷"], "a junk pick replaced the good one")
    }
}

/// A press and a release through the overlay's own door.
@MainActor
enum ScreenAndFilePress {
    static func click(_ overlay: CaptureOverlay, _ id: DisplayID, at point: CGPoint) {
        overlay.mouseDown(on: id, at: point, flags: [])
        overlay.mouseUp(on: id)
    }

    static func drag(_ overlay: CaptureOverlay, _ id: DisplayID, from: CGPoint, to: CGPoint) {
        overlay.mouseDown(on: id, at: from, flags: [])
        overlay.mouseDragged(on: id, at: to, flags: [])
        overlay.mouseUp(on: id)
    }
}
