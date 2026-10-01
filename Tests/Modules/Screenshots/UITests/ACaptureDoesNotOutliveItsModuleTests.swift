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
        func freeze() async -> FreezeOutcome {
            await gate.arrive()
            return .frozen(frozen)
        }
        func window(_ id: UInt32) async -> WindowShot { .gone }
    }

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        func write(_ png: Data, into folder: URL, base: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(folder.appendingPathComponent(base + ".png"))
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
    }

    private func frozen() throws -> Freeze {
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
    private func rig(_ destination: ScreenDestination,
                     presenting: @escaping (CaptureOverlay) -> Bool = { _ in false })
        throws -> (CaptureController, HeldFreeze, Disk, Board) {
        let capture = HeldFreeze(try frozen()), disk = Disk(), board = Board()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(destination.rawValue, for: ScreenshotsSettings.Key.afterFullScreen)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: capture, writer: disk, pasteboard: board, preferences: NoPreferences(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session, presentOverlay: presenting)
        return (controller, capture, disk, board)
    }

    /// The control: the same press, nobody touching the switch, is a file and a copy.
    func testAPressLeftAloneIsDelivered() async throws {
        let (controller, capture, disk, board) = try rig(.both)
        controller.begin(.fullScreen)
        await capture.gate.reached()
        await capture.gate.open()
        await waitUntil("the press became a file") { disk.written == 1 }
        XCTAssertEqual(board.copies, 1, "the press left alone was not copied")
    }

    func testAPressWhoseModuleWentOffMidFreezeWritesAndCopiesNothing() async throws {
        let (controller, capture, disk, board) = try rig(.both)
        controller.begin(.fullScreen)
        await capture.gate.reached()
        // What `ModuleUICache.dropWhenDisabled` does when the switch is turned.
        controller.cancel()
        await capture.gate.open()
        await grace(0.5)
        XCTAssertEqual(disk.written, 0,
                       "a capture of a module switched off during its freeze still wrote a file afterwards")
        XCTAssertEqual(board.copies, 0,
                       "a capture of a module switched off during its freeze still took the clipboard afterwards")
    }

    /// The area shortcut: the freeze is the same wait, and what it resumes into is the overlay.
    /// The presentation is counted and declined, so no panel reaches a screen; the
    /// control first, because an absence is only worth something beside the same
    /// press that did present.
    func testAnAreaPressLeftAloneReachesTheOverlay() async throws {
        let presented = Count()
        let (controller, capture, _, _) = try rig(.both, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await capture.gate.reached()
        await capture.gate.open()
        await waitUntil("the area press reached the overlay") { presented.value == 1 }
    }

    func testAnAreaPressWhoseModuleWentOffMidFreezeShowsNoOverlay() async throws {
        let presented = Count()
        let (controller, capture, _, _) = try rig(.both, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await capture.gate.reached()
        controller.cancel()
        await capture.gate.open()
        await grace(0.5)
        XCTAssertEqual(presented.value, 0,
                       "a module switched off during the freeze still put the area-shortcut overlay on every screen")
    }

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }
}
