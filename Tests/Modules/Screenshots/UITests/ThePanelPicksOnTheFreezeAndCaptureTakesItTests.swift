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

/// **The panel's Window and Area, end to end over fake ports.** Pressing a mode freezes the screen at once and opens the
/// overlay to pick on, with the panel standing above it; Capture is drawn only over a target; the shot goes to the
/// thumbnail's `handOff` with no editor; and with a timer the overlay closes, the ring counts, and the shot is taken from
/// a second freeze after the last tick. The screens are the real ones' ids with blank frames: nothing is ordered in.
@MainActor
final class ThePanelPicksOnTheFreezeAndCaptureTakesItTests: XCTestCase {

    private final class Screen: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var freezeCount = 0, windowCount = 0
        let frames: [FrozenDisplay]
        let windows: [FrozenWindow]
        init(frames: [FrozenDisplay], windows: [FrozenWindow]) { self.frames = frames; self.windows = windows }
        var freezes: Int { lock.withLock { freezeCount } }
        var windowAsks: Int { lock.withLock { windowCount } }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            lock.withLock { freezeCount += 1 }
            return .frozen(Freeze(displays: frames.map { .image($0) }, windows: windows))
        }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot {
            lock.withLock { windowCount += 1 }
            return .gone
        }
    }

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        // A disk that keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    private struct Board: ShotPasteboard {
        func copy(png: Data) -> PasteOutcome { .accepted }
        func copy(pngs: [Data]) -> PasteOutcome { .accepted }
        func copy(text: String) -> PasteOutcome { .accepted }
    }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    @MainActor private final class Held { var overlay: CaptureOverlay? }

    private struct Rig {
        let controller: CaptureController
        let screen: Screen
        let disk: Disk
        let gate: PromptGate
        let held: Held
        let display: DisplayID
    }

    private func rig(timer: CaptureTimer = .none) throws -> Rig {
        let shown = try OverlayRig.frames(scale: 1)
        let frames = shown.enumerated().map { index, frame in
            FrozenDisplay(id: frame.id, frame: frame.frame, scale: 1, image: frame.image, uuid: "UUID-\(index)")
        }
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200),
                                  layer: WindowPick.lowestLevel, ownerName: "Notes")
        let screen = Screen(frames: frames, windows: [window]), disk = Disk(), gate = PromptGate(), held = Held()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: screen, writer: disk, trash: NoTrash(), pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: NoShutter(), textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session,
                                           presentOverlay: { overlay in held.overlay = overlay; return overlay.build() },
                                           presentBar: { _ in }, tick: { _ in await gate.arrive() })
        return Rig(controller: controller, screen: screen, disk: disk, gate: gate, held: held,
                   display: try XCTUnwrap(frames.first?.id))
    }

    private func drag(_ overlay: CaptureOverlay, on display: DisplayID, _ area: CGRect) {
        overlay.mouseDown(on: display, at: area.origin, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        overlay.mouseUp(on: display)
    }

    func testAreaFromThePanelIsPickedOnTheFreezeAndNeverOpensThePalette() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        XCTAssertEqual(box.screen.freezes, 0, "the panel alone froze the screen")
        box.controller.bar.model.choose(.area)
        await waitUntil("the mode press opened the overlay") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertTrue(overlay.selectionOnly)
        XCTAssertTrue(box.controller.bar.selecting, "the panel does not stand above the overlay")
        XCTAssertEqual(CapturePanel.level(selecting: true).rawValue, NSWindow.Level.screenSaver.rawValue + 1)
        XCTAssertFalse(box.controller.bar.model.showsCapture, "Capture is drawn with nothing to take")

        drag(overlay, on: box.display, CGRect(x: 50, y: 60, width: 400, height: 300))
        XCTAssertTrue(box.controller.bar.model.showsCapture, "Capture is not drawn over a chosen area")
        XCTAssertNil(overlay.chrome(on: box.display), "the palette stands under an area the panel chose")
        XCTAssertFalse(try XCTUnwrap(overlay.view(for: box.display)).paletteIsShown)

        box.controller.capture(from: .area)
        await waitUntil("the shot was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.freezes, 1, "an untimed shot froze again")
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertFalse(box.controller.bar.selecting)
    }

    func testCaptureIsOfferedOnlyOverAWindowInWindowMode() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        XCTAssertFalse(box.controller.bar.model.showsCapture, "a window beneath the panel was taken for a choice")
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 900, y: 700))
        XCTAssertFalse(box.controller.bar.model.showsCapture, "an empty desktop is no target")
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(box.controller.bar.model.showsCapture)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 900, y: 700))
        XCTAssertFalse(box.controller.bar.model.showsCapture, "the target outlived the pointer's leaving the window")
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await waitUntil("the window was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.freezes, 1)
    }

    func testAPressOnTheOtherModeSwitchesTheOverlayOnTheSameFreeze() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(box.controller.bar.model.showsCapture)
        box.controller.bar.model.choose(.area)
        XCTAssertFalse(box.controller.bar.model.showsCapture, "the window picked in the other mode stayed a target")
        XCTAssertTrue(box.held.overlay === overlay)
        XCTAssertEqual(box.screen.freezes, 1, "a mode switch froze the screen again")
        box.controller.bar.model.choose(.screen)
        XCTAssertFalse(overlay.isOpen, "the screen mode left the overlay up")
        XCTAssertTrue(box.controller.bar.model.showsCapture, "the whole screen is always a target")
        XCTAssertTrue(box.controller.isBusy, "putting the overlay away ended the panel")
    }

    func testATimedAreaIsCutFromASecondFreezeAfterTheLastTick() async throws {
        let box = try rig(timer: .five)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        drag(overlay, on: box.display, CGRect(x: 50, y: 60, width: 400, height: 300))
        box.controller.capture(from: .area)
        await box.gate.reached()
        XCTAssertFalse(overlay.isOpen, "the overlay stayed up through the countdown")
        XCTAssertEqual(box.controller.bar.model.countdown, 5)
        XCTAssertFalse(box.controller.bar.selecting)
        XCTAssertEqual(box.screen.freezes, 1, "the second freeze came before the countdown was over")
        XCTAssertEqual(box.disk.written, 0)

        await box.gate.open()
        await waitUntil("the timed shot was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.freezes, 2, "the timed area was not cut from a fresh freeze")
        await waitUntil("the machine was freed") { !box.controller.isBusy }
    }

    func testATimedWindowIsAskedForByItsIdAfterTheLastTick() async throws {
        let box = try rig(timer: .ten)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await box.gate.reached()
        XCTAssertEqual(box.screen.windowAsks, 0, "the window was asked for before the countdown ended")
        await box.gate.open()
        await waitUntil("the timed window was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.screen.windowAsks, 1)
        XCTAssertEqual(box.screen.freezes, 1)
    }

    func testEscOnThePanelsOverlayEndsThePanelToo() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.rightMouseDown()
        await waitUntil("Esc freed the machine") { !box.controller.isBusy }
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertFalse(box.controller.bar.model.hasTarget)
    }

    func testTheCloseControlDuringATimedAreaTakesNothing() async throws {
        let box = try rig(timer: .five)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        drag(try XCTUnwrap(box.held.overlay), on: box.display, CGRect(x: 50, y: 60, width: 400, height: 300))
        box.controller.capture(from: .area)
        await box.gate.reached()
        box.controller.bar.model.cancel()
        await box.gate.open()
        await grace(0.3)
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertEqual(box.screen.freezes, 1, "a cancelled countdown froze the screen")
        XCTAssertFalse(box.controller.isBusy)
    }
}
