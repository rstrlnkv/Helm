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

/// **The last area is kept only while the option is on, and opens the overlay
/// only from the bar's Area mode.** Written for any confirmed area; read by
/// nothing else — the area shortcut is a fresh start, and the bar's Window mode
/// has no area to open on. The overlay is built over the real screens and never
/// ordered in, driven by hand.
@MainActor
final class TheRememberedSelectionBelongsToTheBarsAreaTests: XCTestCase {

    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }
    private struct Disk: ShotWriting {
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    private typealias Board = CountingBoard
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    /// One frame per real screen, the first one's UUID being `uuid`: the overlay
    /// is built over every screen or none.
    private func freeze(uuid: String) throws -> (Freeze, DisplayID) {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number),
                                        frame: CGRect(origin: CGPoint(x: 100_000 * CGFloat(index), y: 0),
                                                      size: CGSize(width: 1000, height: 800)),
                                        scale: 1, image: try XCTUnwrap(context.makeImage()),
                                        uuid: index == 0 ? uuid : "other-\(index)"))
        }
        let first = try XCTUnwrap(frames.first)
        return (Freeze(displays: frames.map { .image($0) }, windows: []), first.id)
    }

    private struct Rig {
        let controller: CaptureController
        let store: NamespacedStore
        let first: DisplayID
        let opened: Opened
    }

    @MainActor final class Opened {
        var overlays: [CaptureOverlay] = []
    }

    private func rig(remember: Bool, stored: RememberedSelection? = nil) throws -> Rig {
        let (freeze, first) = try freeze(uuid: "AAAA-1111")
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(remember, for: ScreenshotsSettings.Key.rememberSelection)
        store.set(SaveTarget.clipboard.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        stored?.write(to: store)
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: Disk(), trash: NoTrash(), pasteboard: Board(),
                                     preferences: NoPreferences(), shutter: NoShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english })
        let opened = Opened()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session,
                                           presentOverlay: { overlay in
                                               let built = overlay.build()
                                               if built { opened.overlays.append(overlay) }
                                               return built
                                           },
                                           presentBar: { _ in })
        return Rig(controller: controller, store: store, first: first, opened: opened)
    }

    private func drag(_ overlay: CaptureOverlay, on display: DisplayID) {
        overlay.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: display)
        overlay.keyDown(returnKey)
    }

    private var returnKey: NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                         isARepeat: false, keyCode: 36)!
    }

    func testAConfirmedAreaIsKeptWhileTheOptionIsOnAndNotWhenItIsOff() async throws {
        for remember in [true, false] {
            let box = try rig(remember: remember)
            box.controller.begin(.area)
            await waitUntil("the overlay opened (remember \(remember))") { !box.opened.overlays.isEmpty }
            drag(try XCTUnwrap(box.opened.overlays.first), on: box.first)
            await waitUntil("the press ended") { !box.controller.isBusy }
            let kept = RememberedSelection.read(box.store)
            if remember {
                XCTAssertEqual(kept, RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 100, y: 100, width: 200, height: 150)),
                               "a confirmed area was not remembered with its option on")
            } else {
                XCTAssertNil(kept, "an area was remembered with the option off")
            }
        }
    }

    func testOnlyTheBarsAreaOpensOnTheRememberedOne() async throws {
        let saved = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 50, y: 60, width: 400, height: 300)))

        // The bar's Area mode, option on: opens on it.
        let bar = try rig(remember: true, stored: saved)
        bar.controller.begin(.panel)
        bar.controller.capture(from: .area)
        await waitUntil("the bar's area overlay opened") { !bar.opened.overlays.isEmpty }
        let opened = try XCTUnwrap(bar.opened.overlays.first)
        XCTAssertEqual(opened.preselection?.display, bar.first)
        XCTAssertEqual(opened.preselection?.rect, saved.rect)

        // The same record with the option off: opens empty.
        let off = try rig(remember: false, stored: saved)
        off.controller.begin(.panel)
        off.controller.capture(from: .area)
        await waitUntil("the overlay opened with the option off") { !off.opened.overlays.isEmpty }
        XCTAssertNil(off.opened.overlays.first?.preselection, "the option is off and the overlay opened on a selection")

        // The area shortcut is a fresh start, option on or not.
        let shortcut = try rig(remember: true, stored: saved)
        shortcut.controller.begin(.area)
        await waitUntil("the shortcut's overlay opened") { !shortcut.opened.overlays.isEmpty }
        XCTAssertNil(shortcut.opened.overlays.first?.preselection, "the area shortcut opened on the remembered selection")

        // Window mode has no area to open on.
        let window = try rig(remember: true, stored: saved)
        window.controller.begin(.panel)
        window.controller.capture(from: .window)
        await waitUntil("the window overlay opened") { !window.opened.overlays.isEmpty }
        XCTAssertNil(window.opened.overlays.first?.preselection, "window mode opened on an area")

        // Another display's record opens empty.
        let foreign = try rig(remember: true, stored: RememberedSelection(display: "ZZZZ-9999", rect: saved.rect))
        foreign.controller.begin(.panel)
        foreign.controller.capture(from: .area)
        await waitUntil("the overlay opened over a foreign record") { !foreign.opened.overlays.isEmpty }
        XCTAssertNil(foreign.opened.overlays.first?.preselection, "a record of another display opened an overlay")
        for box in [bar, off, shortcut, window, foreign] { box.controller.cancel() }
    }

    /// Return takes the remembered selection into the editor as it stands, the next Return takes it,
    /// and a new drag replaces it.
    func testReturnTakesTheRememberedAreaAndADragReplacesIt() throws {
        let (freeze, first) = try freeze(uuid: "AAAA-1111")
        let rect = CGRect(x: 50, y: 60, width: 400, height: 300)
        var results: [OverlayResult] = []
        let overlay = CaptureOverlay(freeze: freeze, mode: .area, preselection: (first, rect)) { results.append($0) }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                   isARepeat: false, keyCode: 36)!
        overlay.keyDown(key)
        XCTAssertTrue(results.isEmpty, "Return on the remembered selection finished before the editor had it")
        overlay.keyDown(key)
        guard case .edited(let display, let local, _, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(display, first)
        XCTAssertEqual(local, rect)

        results = []
        let again = CaptureOverlay(freeze: freeze, mode: .area, preselection: (first, rect)) { results.append($0) }
        XCTAssertTrue(again.build())
        defer { again.close() }
        again.mouseDown(on: first, at: CGPoint(x: 10, y: 10), flags: [])
        XCTAssertNil(again.preselection, "a new drag left the remembered selection standing")
        again.keyDown(key)
        XCTAssertTrue(results.isEmpty, "Return in the middle of a new drag finished with \(results)")
    }

    /// **Remember switched off while the overlay is up: the confirm that follows
    /// writes nothing.** The overlay opened on the stored area (the option was
    /// on at the press); the switch then goes off through its one door, and
    /// Return takes the area that is still drawn. Whether to keep it is asked at
    /// the confirm, not at the press, so the store stays empty.
    func testRememberSwitchedOffWhileTheOverlayIsUpWritesNothingOnConfirm() async throws {
        let saved = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 50, y: 60, width: 400, height: 300)))
        let box = try rig(remember: true, stored: saved)
        box.controller.begin(.panel)
        box.controller.capture(from: .area)
        await waitUntil("the bar's area overlay opened") { !box.opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(box.opened.overlays.first)
        XCTAssertEqual(overlay.preselection?.rect, saved.rect, "the overlay did not open on the record, so nothing below is the case")

        ScreenshotsSettings.setRememberSelection(false, in: box.store)
        XCTAssertNil(RememberedSelection.read(box.store))

        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                   isARepeat: false, keyCode: 36)!
        overlay.keyDown(key)
        overlay.keyDown(key)
        await waitUntil("the press ended") { !box.controller.isBusy }
        XCTAssertNil(RememberedSelection.read(box.store), "the confirm after the switch went off wrote the area back")
        for key in [RememberedSelection.Key.display, RememberedSelection.Key.x, RememberedSelection.Key.y,
                    RememberedSelection.Key.width, RememberedSelection.Key.height] {
            XCTAssertNil(box.store.object(key), "\(key) was written after the switch went off")
        }
    }

    /// The same press with the switch left on writes the confirmed area — the
    /// control that says the confirm above did reach the writer.
    func testTheSameConfirmWithTheSwitchOnWritesTheArea() async throws {
        let saved = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 50, y: 60, width: 400, height: 300)))
        let box = try rig(remember: true)
        box.controller.begin(.panel)
        box.controller.capture(from: .area)
        await waitUntil("the overlay opened") { !box.opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(box.opened.overlays.first)
        overlay.mouseDown(on: box.first, at: CGPoint(x: 50, y: 60), flags: [])
        overlay.mouseDragged(on: box.first, at: CGPoint(x: 450, y: 360), flags: [])
        overlay.mouseUp(on: box.first)
        overlay.keyDown(returnKey)
        await waitUntil("the press ended") { !box.controller.isBusy }
        XCTAssertEqual(RememberedSelection.read(box.store), saved)
    }
}
