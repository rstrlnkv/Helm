import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A capture the module was switched off under does nothing afterwards.**
///
/// The freeze is the one long wait in a capture — some hundred milliseconds of
/// ScreenCaptureKit on three displays — and the module's switch can be turned
/// in it. `ModuleUICache.dropWhenDisabled` then calls `CaptureController.cancel`,
/// which closes an overlay that does not exist yet and lets the controller go;
/// the task that was waiting on the freeze still holds the controller and
/// resumes. On the area shortcut what it resumes into is `CaptureOverlay.present` — panels
/// above the menu bar on every screen, owned by a controller nobody holds, for
/// a module that is off. That path cannot be shown here without putting the
/// overlay on the screen of whoever runs the suite, so this reads the same
/// resumption on the full-screen shortcut, where what it resumes into is a file and the clipboard.
///
/// The freeze is held open by a gate, because a fake that answers at once is
/// over before the switch can be turned.
@MainActor
final class ACaptureDoesNotOutliveItsModuleTests: XCTestCase {

    private final class HeldFreeze: ScreenCapturing, @unchecked Sendable {
        let gate = PromptGate()
        let frozen: Freeze
        init(_ frozen: Freeze) { self.frozen = frozen }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            await gate.arrive()
            return .frozen(frozen)
        }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
    }

    private final class Board: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var copies: Int { lock.withLock { count } }
        func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1 }; return .accepted }
    }

    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }

    private struct NoShutter: ShutterPlaying {
        func play() {}
    }

    private func frozen(real: Bool = false) throws -> Freeze {
        // Frames for the real screens, which the overlay needs to build its panels.
        if real { return Freeze(displays: try OverlayRig.frames().map { .image($0) }, windows: []) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        // A display id no screen carries: nothing here can reach a real screen.
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(0xDEAD_BEEF),
                                                      frame: CGRect(x: 0, y: 0, width: 10, height: 5),
                                                      scale: 2, image: image))],
                      windows: [])
    }

    /// The thumbnail is off, so no toast is put on anybody's screen.
    private func rig(_ target: SaveTarget, realScreens: Bool = false,
                     presenting: @escaping (CaptureOverlay) -> Bool = { _ in false })
        throws -> (CaptureController, HeldFreeze, Disk, Board) {
        let capture = HeldFreeze(try frozen(real: realScreens)), disk = Disk(), board = Board()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: capture, writer: disk, pasteboard: board, preferences: NoPreferences(), shutter: NoShutter(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session, presentOverlay: presenting)
        return (controller, capture, disk, board)
    }

    /// The control: the same press, nobody touching the switch, is a file under a
    /// file target and a copy under the clipboard — each of the two outcomes the
    /// cancelled press below must not reach.
    func testAPressLeftAloneIsDelivered() async throws {
        for target in [SaveTarget.desktop, .clipboard] {
            let (controller, capture, disk, board) = try rig(target)
            controller.begin(.fullScreen)
            await capture.gate.reached()
            await capture.gate.open()
            await waitUntil("the press became its file or its copy under \(target)") {
                disk.written + board.copies == 1
            }
            XCTAssertEqual(disk.written, target == .clipboard ? 0 : 1, "\(target)")
            XCTAssertEqual(board.copies, target == .clipboard ? 1 : 0, "\(target)")
        }
    }

    func testAPressWhoseModuleWentOffMidFreezeWritesAndCopiesNothing() async throws {
        for target in [SaveTarget.desktop, .clipboard] {
            let (controller, capture, disk, board) = try rig(target)
            controller.begin(.fullScreen)
            await capture.gate.reached()
            // What `ModuleUICache.dropWhenDisabled` does when the switch is turned.
            controller.cancel()
            await capture.gate.open()
            await grace(0.5)
            XCTAssertEqual(disk.written, 0,
                           "a capture of a module switched off during its freeze still wrote a file afterwards (\(target))")
            XCTAssertEqual(board.copies, 0,
                           "a capture of a module switched off during its freeze still took the clipboard afterwards (\(target))")
        }
    }

    /// The area shortcut: the freeze is the same wait, and what it resumes into is the overlay.
    /// The presentation is counted and declined, so no panel reaches a screen; the
    /// control first, because an absence is only worth something beside the same
    /// press that did present.
    func testAnAreaPressLeftAloneReachesTheOverlay() async throws {
        let presented = Count()
        let (controller, capture, _, _) = try rig(.desktop, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await capture.gate.reached()
        await capture.gate.open()
        await waitUntil("the area press reached the overlay") { presented.value == 1 }
    }

    func testAnAreaPressWhoseModuleWentOffMidFreezeShowsNoOverlay() async throws {
        let presented = Count()
        let (controller, capture, _, _) = try rig(.desktop, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await capture.gate.reached()
        controller.cancel()
        await capture.gate.open()
        await grace(0.5)
        XCTAssertEqual(presented.value, 0,
                       "a module switched off during the freeze still put the area-shortcut overlay on every screen")
    }

    /// The overlay is held through the presentation seam (built, never shown), a shot is taken and the module
    /// goes off while the overlay waits for its flash: the panels must be gone at once, not when the timer
    /// finds them. The control is the same shot left alone, which is still open and leaving right after it.
    func testTheModuleGoingOffDuringTheFlashClosesTheOverlayAtOnce() async throws {
        for cancelled in [false, true] {
            let held = Held()
            let (controller, capture, _, _) = try rig(.clipboard, realScreens: true, presenting: { overlay in
                overlay.reducesMotion = { false }
                held.overlay = overlay
                return overlay.build()
            })
            controller.begin(.area)
            await capture.gate.reached()
            await capture.gate.open()
            await waitUntil("the overlay reached the seam") { held.overlay != nil }
            let overlay = try XCTUnwrap(held.overlay)
            let display = try XCTUnwrap(try OverlayRig.frames().first?.id)
            overlay.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
            overlay.mouseDragged(on: display, at: CGPoint(x: 400, y: 300), flags: [])
            overlay.mouseUp(on: display)
            overlay.perform(.exit(.confirm))
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "the subject: the shot is flashing (\(cancelled))")
            if cancelled {
                controller.cancel()
                XCTAssertFalse(overlay.isOpen, "the module went off in the flash and the panels stayed up")
                XCTAssertFalse(overlay.leaving)
            } else {
                XCTAssertTrue(overlay.isOpen, "the control: left alone it is open until the flash is over")
                await waitUntil("the flash ended by itself") { !overlay.isOpen }
            }
            overlay.close()
        }
    }

    @MainActor private final class Held {
        var overlay: CaptureOverlay?
    }

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }
}
