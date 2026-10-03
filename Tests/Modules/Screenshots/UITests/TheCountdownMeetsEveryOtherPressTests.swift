import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The presses nobody makes in a demo, made during a countdown or over an open overlay.** Every
/// screenshot shortcut pressed while the bar counts, and the bar closed and
/// opened again with a cancelled countdown's wait still pending. One capture
/// at a time: a press during the countdown is dropped and the countdown goes
/// on; a bar opened after a cancelled one starts clean, and the old wait, when
/// it finally ends, neither writes a number on the new bar nor freezes.
///
/// The wait is the controller's `tick` seam, held by a gate the test opens.
/// Nothing reaches a real screen: the bar and overlay seams count and present nothing.
@MainActor
final class TheCountdownMeetsEveryOtherPressTests: XCTestCase {

    private final class Freezes: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let image: CGImage
        init(_ image: CGImage) { self.image = image }
        var freezes: Int { lock.withLock { count } }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            lock.withLock { count += 1 }
            return .frozen(Freeze(displays: [.image(FrozenDisplay(id: DisplayID(0xDEAD_BEEF),
                                                                  frame: CGRect(x: 0, y: 0, width: 10, height: 5),
                                                                  scale: 2, image: image))], windows: []))
        }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
    }

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

    private typealias Board = CountingBoard
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    /// Which gate the next second waits on; swapped between two presses.
    private final class Gates: @unchecked Sendable {
        private let lock = NSLock()
        private var gate = PromptGate()
        private var n = 0
        var current: PromptGate {
            get { lock.withLock { gate } }
            set { lock.withLock { gate = newValue } }
        }
        var ticks: Int { lock.withLock { n } }
        func bump() -> PromptGate { lock.withLock { n += 1; return gate } }
    }

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }

    /// The overlay a seam "put up": kept, never ordered in, so a test can end it.
    @MainActor private final class Held { var overlay: CaptureOverlay? }

    private struct Rig {
        let controller: CaptureController
        let capture: Freezes
        let disk: Disk
        let gates: Gates
        let bars: Count
        let overlays: Count
        let held: Held
    }

    private func rig(timer: CaptureTimer, overlayStaysUp: Bool = false) throws -> Rig {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let capture = Freezes(try XCTUnwrap(context.makeImage())), disk = Disk(), gates = Gates()
        let bars = Count(), overlays = Count(), held = Held()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: capture, writer: disk, trash: NoTrash(), pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: NoShutter(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session,
                                           presentOverlay: { overlay in
                                               overlays.bump()
                                               guard overlayStaysUp else { return false }
                                               held.overlay = overlay
                                               return true
                                           },
                                           presentBar: { _ in bars.bump() },
                                           tick: { _ in await gates.bump().arrive() })
        return Rig(controller: controller, capture: capture, disk: disk, gates: gates, bars: bars, overlays: overlays,
                   held: held)
    }

    /// All three shortcuts pressed while the bar counts: each is dropped, the
    /// bar is not raised again, nothing freezes early, and the countdown that was
    /// running is the one that ends in the single capture.
    func testEveryShortcutPressedDuringTheCountdownIsDroppedAndTheCountdownGoesOn() async throws {
        let box = try rig(timer: .five)
        let gate = box.gates.current
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await gate.reached()
        XCTAssertEqual(box.gates.ticks, 1, "the countdown never started, so nothing was proved")
        XCTAssertEqual(box.controller.bar.model.countdown, 5)

        for hotkey in ScreenshotsHotkey.allCases { box.controller.begin(hotkey) }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 0, "a shortcut pressed during the countdown froze the screen before it ended")
        XCTAssertEqual(box.overlays.value, 0, "a shortcut pressed during the countdown raised an overlay")
        XCTAssertEqual(box.bars.value, 1, "a shortcut pressed during the countdown raised the bar again")
        XCTAssertTrue(box.controller.isBusy, "a press during the countdown freed the machine")
        XCTAssertEqual(box.controller.bar.model.countdown, 5, "a press during the countdown moved or cleared it")

        await gate.open()
        await waitUntil("the countdown's own capture was delivered") { box.disk.written == 1 }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 1, "one press, one freeze")
        XCTAssertEqual(box.gates.ticks, 5, "the countdown did not run its five seconds")
    }

    /// ✕ during a countdown, the bar opened again, Capture pressed again — and
    /// only then does the first press's wait end. The reopened bar shows no
    /// number (a number left on it would also block Return, which the bar
    /// refuses while counting), the new countdown starts from its full length,
    /// and the old wait ending writes nothing on the new bar and freezes nothing.
    func testABarOpenedAfterACancelledCountdownStartsCleanAndTheOldWaitIsInert() async throws {
        let box = try rig(timer: .ten)
        let first = box.gates.current
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await first.reached()
        XCTAssertEqual(box.controller.bar.model.countdown, 10, "the countdown never showed, so nothing was proved")

        box.controller.bar.model.cancel()
        XCTAssertFalse(box.controller.isBusy, "the close control left the machine busy")

        let second = PromptGate()
        box.gates.current = second
        box.controller.begin(.panel)
        XCTAssertEqual(box.bars.value, 2, "the panel shortcut after a cancel did not raise the bar")
        XCTAssertNil(box.controller.bar.model.countdown,
                     "the reopened bar still shows the cancelled countdown's number, and refuses Return while it does")
        XCTAssertFalse(box.controller.bar.model.counting)

        box.controller.capture(from: .screen)
        await second.reached()
        XCTAssertEqual(box.controller.bar.model.countdown, 10, "the new countdown did not start from its full length")

        await first.open()
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 0, "the cancelled countdown's wait ended in a freeze")
        XCTAssertEqual(box.controller.bar.model.countdown, 10,
                       "the cancelled countdown's wait wrote its next second on the new bar")

        await second.open()
        await waitUntil("the second press was delivered") { box.disk.written == 1 }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 1, "two presses' worth of freezes from one capture")
    }

    /// The overlay stage: every shortcut pressed while the overlay is up is
    /// dropped — no second freeze over the first (which would photograph the
    /// overlay), no bar, no second overlay — and once the overlay ends the next
    /// press works. The overlay is held "up" by a seam that keeps it and orders
    /// nothing in.
    func testEveryShortcutPressedWhileTheOverlayIsUpIsDroppedAndTheNextPressWorks() async throws {
        let box = try rig(timer: .none, overlayStaysUp: true)
        box.controller.begin(.area)
        await waitUntil("the area press reached the overlay") { box.overlays.value == 1 }
        XCTAssertEqual(box.capture.freezes, 1)
        XCTAssertTrue(box.controller.isBusy, "an overlay that is up left the machine free")

        for hotkey in ScreenshotsHotkey.allCases { box.controller.begin(hotkey) }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 1, "a shortcut pressed over the open overlay froze the screen again")
        XCTAssertEqual(box.overlays.value, 1, "a shortcut pressed over the open overlay raised a second one")
        XCTAssertEqual(box.bars.value, 0, "a shortcut pressed over the open overlay raised the bar")

        try XCTUnwrap(box.held.overlay, "the seam kept no overlay, so nothing was proved").finish(.cancelled)
        await waitUntil("Esc on the overlay freed the machine") { !box.controller.isBusy }
        box.controller.begin(.fullScreen)
        await waitUntil("the next press froze") { box.capture.freezes == 2 }
        await waitUntil("and was delivered") { box.disk.written == 1 }
    }
}
