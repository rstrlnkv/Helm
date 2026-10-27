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

/// What the capture panel's test families share: a controller over fake ports whose freezes can be counted and
/// held call by call, and a disk that counts what it was given.
/// The overlay is **built and not ordered in** (`CaptureOverlay.build`), the bar seam puts nothing on a screen unless
/// a test asks for the real one.
@MainActor
enum PanelRig {

    /// The screen: every call to `freeze` is numbered from 1 and may be held on a gate.
    final class Screen: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var freezeCount = 0
        let base: [FrozenDisplay]
        let windows: [FrozenWindow]
        /// A held freeze: the n-th call waits for the gate, if one is set for it.
        var hold: @Sendable (Int) -> PromptGate? = { _ in nil }

        init(base: [FrozenDisplay], windows: [FrozenWindow]) {
            self.base = base; self.windows = windows
        }
        var freezes: Int { lock.withLock { freezeCount } }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            let n = lock.withLock { freezeCount += 1; return freezeCount }
            if let gate = hold(n) { await gate.arrive() }
            return .frozen(Freeze(displays: base.map { .image($0) }, windows: windows))
        }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }

    final class Disk: ShotWriting, @unchecked Sendable {
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
    struct Board: ShotPasteboard {
        func copy(png: Data) -> PasteOutcome { .accepted }
        func copy(pngs: [Data]) -> PasteOutcome { .accepted }
        func copy(text: String) -> PasteOutcome { .accepted }
    }
    struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    struct NoShutter: ShutterPlaying { func play() {} }

    @MainActor final class Held { var overlay: CaptureOverlay?; var overlays = 0; var bars = 0 }

    struct Rig {
        let controller: CaptureController
        let screen: Screen
        let disk: Disk
        let held: Held
        let display: DisplayID
    }

    /// Every real screen, 1000 x 800 points at scale 1, each with a UUID; the first holds a window at (100,100,300,200).
    static func rig(timer: CaptureTimer = .none, presentBar: @escaping (CapturePanel) -> Void = { _ in },
                    tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> Rig {
        let shown = try OverlayRig.frames(scale: 1)
        let base = shown.enumerated().map { index, frame in
            FrozenDisplay(id: frame.id, frame: frame.frame, scale: 1, image: frame.image, uuid: "UUID-\(index)")
        }
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200),
                                  layer: WindowPick.lowestLevel, ownerName: "Notes")
        let screen = Screen(base: base, windows: [window])
        let disk = Disk(), held = Held()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: screen, writer: disk, trash: NoTrash(), pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: NoShutter(), textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in held.overlays += 1; held.overlay = overlay; return overlay.build() },
                                           presentBar: { bar in held.bars += 1; presentBar(bar) }, tick: tick)
        return Rig(controller: controller, screen: screen, disk: disk, held: held, display: try XCTUnwrap(base.first?.id))
    }

    static func drag(_ overlay: CaptureOverlay, on display: DisplayID, _ area: CGRect) {
        overlay.mouseDown(on: display, at: area.origin, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        overlay.mouseUp(on: display)
    }

    static let area = CGRect(x: 50, y: 60, width: 400, height: 300)
}
