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

/// **The editor under the inputs its brief did not name:** a module switched off right after an exit delivers nothing
/// and sounds no shutter. Panels are built and never ordered in.
@MainActor
final class TheEditorMeetsTheInputsNobodyPlannedTests: XCTestCase {

    private typealias Board = CountingBoard
    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private final class Shutter: ShutterPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var plays: Int { lock.withLock { count } }
        func play() { lock.withLock { count += 1 } }
    }

    /// One 1000×800-point frame at 1× per real screen, in screen order.
    private func freeze(windows: [FrozenWindow] = []) throws -> (Freeze, [DisplayID]) {
        let frames = try OverlayRig.frames()
        return (Freeze(displays: frames.map { .image($0) }, windows: windows), frames.map(\.id))
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = [],
                     repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: repeating, keyCode: code)!
    }

    private let kA: UInt16 = 0
    private let kReturn: UInt16 = 36

    // MARK: Through the controller

    private func rig(target: SaveTarget, shutter: Shutter = Shutter()) throws
        -> (CaptureController, Board, Disk, Opened, DisplayID) {
        let (freeze, ids) = try freeze()
        let board = Board(), disk = Disk(), opened = Opened()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, trash: NoTrash(), pasteboard: board,
                                     preferences: NoPreferences(), shutter: shutter, textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session,
                                           presentOverlay: { overlay in
                                               let built = overlay.build()
                                               if built { opened.overlays.append(overlay) }
                                               return built
                                           },
                                           presentBar: { _ in })
        return (controller, board, disk, opened, try XCTUnwrap(ids.first))
    }
    @MainActor private final class Opened { var overlays: [CaptureOverlay] = [] }

    private func editedThroughTheController(_ target: SaveTarget, shutter: Shutter = Shutter()) async throws
        -> (CaptureController, Board, Disk, CaptureOverlay) {
        let (controller, board, disk, opened, first) = try rig(target: target, shutter: shutter)
        controller.begin(.area)
        await waitUntil("the overlay opened") { !opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(opened.overlays.first)
        overlay.mouseDown(on: first, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: first, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: first)
        overlay.keyDown(key(kA, "ф"))
        overlay.mouseDown(on: first, at: CGPoint(x: 120, y: 120), flags: [])
        overlay.mouseDragged(on: first, at: CGPoint(x: 250, y: 200), flags: [])
        overlay.mouseUp(on: first)
        return (controller, board, disk, overlay)
    }

    /// The module switched off in the same turn as the exit: `cancel` promises that work
    /// in flight goes with the module, so nothing is written or copied afterwards. The
    /// control is the same press left alone.
    func testAModuleSwitchedOffRightAfterAnExitDeliversNothing() async throws {
        let (alone, aloneBoard, aloneDisk, aloneOverlay) = try await editedThroughTheController(.desktop)
        aloneOverlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the press left alone was delivered") { aloneBoard.copies + aloneDisk.written == 2 }
        await waitUntil("the press left alone ended") { !alone.isBusy }

        let (controller, board, disk, overlay) = try await editedThroughTheController(.desktop)
        overlay.keyDown(key(kReturn, "\r"))
        // What `ModuleUICache.dropWhenDisabled` does when the switch is turned.
        controller.cancel()
        await grace(0.5)
        XCTAssertEqual(disk.written, 0, "a module switched off right after Return still wrote the file")
        XCTAssertEqual(board.copies, 0, "a module switched off right after Return still took the clipboard")
    }

    /// The shutter is the sound of a picture being taken; a delivery cancelled with the
    /// module makes none. The engine cannot hold it back — the controller plays it before
    /// handing the picture over — so this is the check on the controller's own refusal.
    /// The control is the same press left alone, which sounds once.
    func testAModuleSwitchedOffRightAfterAnExitSoundsNoShutter() async throws {
        let aloneShutter = Shutter()
        let (alone, _, _, aloneOverlay) = try await editedThroughTheController(.desktop, shutter: aloneShutter)
        aloneOverlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the press left alone ended") { !alone.isBusy }
        XCTAssertEqual(aloneShutter.plays, 1, "the press left alone sounded no shutter, so the absence below says nothing")

        let shutter = Shutter()
        let (controller, _, _, overlay) = try await editedThroughTheController(.desktop, shutter: shutter)
        overlay.keyDown(key(kReturn, "\r"))
        controller.cancel()
        await grace(0.5)
        XCTAssertEqual(shutter.plays, 0, "a module switched off right after Return still sounded the shutter")
    }
}
