import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A countdown that was cancelled freezes nothing.** The timer's wait is a
/// second of nothing, five or ten times, and the module can be switched off, the
/// close control pressed or Esc typed inside any of them. What the press
/// resumes into after the wait is a freeze of every screen and, on the area
/// press, panels over all of them — for a capture nobody wants any more.
///
/// The wait is the controller's `tick` seam, so a test holds it still: a gate
/// the test opens *after* cancelling is the case that matters, because a wait
/// that ends normally is no evidence that nobody cancelled during it, and a
/// controller that only ever read its own flag after the whole loop would look
/// right against a tick that returns at once.
@MainActor
final class TheCountdownEndsWithTheModuleTests: XCTestCase {

    private final class Freezes: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let image: CGImage
        /// Called inside each freeze, so a test can read what the countdown had reached.
        var onFreeze: () -> Void = {}
        init(_ image: CGImage) { self.image = image }
        var freezes: Int { lock.withLock { count } }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            lock.withLock { count += 1 }
            onFreeze()
            // A display no screen carries: nothing here can reach a real screen.
            return .frozen(Freeze(displays: [.image(FrozenDisplay(id: DisplayID(0xDEAD_BEEF),
                                                                  frame: CGRect(x: 0, y: 0, width: 10, height: 5),
                                                                  scale: 2, image: image))], windows: []))
        }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .gone }
    }

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
    }

    private struct Board: ShotPasteboard { func copy(png: Data) -> PasteOutcome { .accepted } }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    private final class Ticks: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }

    private struct Rig {
        let controller: CaptureController
        let capture: Freezes
        let disk: Disk
        let ticks: Ticks
        let shown: Ticks
    }

    private func rig(timer: CaptureTimer, tick: @escaping (Ticks) -> (Duration) async throws -> Void) throws -> Rig {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let capture = Freezes(try XCTUnwrap(context.makeImage())), disk = Disk(), ticks = Ticks(), shown = Ticks()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: capture, writer: disk, pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: NoShutter(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session, presentOverlay: { _ in false },
                                           presentBar: { _ in shown.bump() }, tick: tick(ticks))
        return Rig(controller: controller, capture: capture, disk: disk, ticks: ticks, shown: shown)
    }

    /// The control: nobody cancels, so the press counts every second on the bar,
    /// freezes **after** the last one, and delivers.
    func testACountdownLeftAloneFreezesOnlyAfterItsLastSecond() async throws {
        var atFreeze = -1
        let box = try rig(timer: .five) { ticks in { _ in ticks.bump() } }
        box.capture.onFreeze = { atFreeze = box.ticks.count }
        box.controller.begin(.panel)
        XCTAssertEqual(box.shown.count, 1, "the panel shortcut did not put the bar up")
        box.controller.capture(from: .screen)
        await waitUntil("the press was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.ticks.count, 5, "five seconds are five waits")
        XCTAssertEqual(atFreeze, 5, "the screen was frozen before the countdown was over")
        XCTAssertEqual(box.capture.freezes, 1)
    }

    func testTheBarShowsEverySecondLeft() async throws {
        let seen = Seen()
        var controllerRef: CaptureController?
        let box = try rig(timer: .five) { ticks in
            { _ in
                ticks.bump()
                let left = await MainActor.run { controllerRef?.bar.model.countdown }
                seen.add(left)
            }
        }
        controllerRef = box.controller
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await waitUntil("the press was delivered") { box.disk.written == 1 }
        XCTAssertEqual(seen.values, [5, 4, 3, 2, 1], "the bar did not show the seconds left")
        XCTAssertNil(box.controller.bar.model.countdown, "the bar kept a number after the countdown ended")
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Int?] = []
        var values: [Int?] { lock.withLock { list } }
        func add(_ value: Int?) { lock.withLock { list.append(value) } }
    }

    /// No timer: no wait at all, and the press freezes at once.
    func testNoTimerMeansNoWait() async throws {
        let box = try rig(timer: .none) { ticks in { _ in ticks.bump() } }
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await waitUntil("the press was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.ticks.count, 0)
    }

    /// The module's switch, the close control and Esc — the last two are the bar's
    /// own cancel — each cancel inside a wait that the test then lets **end**.
    func testACancelledCountdownFreezesNothingWhateverEndsIt() async throws {
        let ways: [(String, (CaptureController) -> Void)] = [
            ("the module switched off", { $0.cancel() }),
            ("the close control or Esc", { $0.bar.model.cancel() }),
        ]
        for (way, cancel) in ways {
            let gate = PromptGate()
            let box = try rig(timer: .ten) { ticks in { _ in ticks.bump(); await gate.arrive() } }
            box.controller.begin(.panel)
            box.controller.capture(from: .screen)
            await gate.reached()
            XCTAssertEqual(box.ticks.count, 1, "\(way): the countdown never started, so nothing was proved")
            cancel(box.controller)
            await gate.open()
            await grace(0.4)
            XCTAssertEqual(box.capture.freezes, 0, "\(way): a cancelled countdown still froze the screen")
            XCTAssertEqual(box.disk.written, 0, "\(way): a cancelled countdown still wrote a file")
            XCTAssertEqual(box.ticks.count, 1, "\(way): the countdown went on counting after it was cancelled")
        }
    }

    /// A wait that never completes and ends only by being cancelled: the module
    /// goes off inside it, and the machine must be free for the next press —
    /// one `busy` flag that stayed set would drop every press from then on.
    func testAWaitThatNeverEndsIsLeftByCancellingAndTheNextPressWorks() async throws {
        let box = try rig(timer: .five) { ticks in { _ in ticks.bump(); try await Task.sleep(for: .seconds(3600)) } }
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await waitUntil("the countdown started") { box.ticks.count == 1 }
        box.controller.cancel()
        await grace(0.2)
        XCTAssertEqual(box.capture.freezes, 0)
        // The same machine, pressed again by the shortcut that has no bar.
        box.controller.begin(.fullScreen)
        await waitUntil("the next press freezes") { box.capture.freezes == 1 }
        await waitUntil("and is delivered") { box.disk.written == 1 }
    }

    /// One flag: while the bar is up a second panel press and a second capture are dropped.
    func testASecondPressWhileTheBarIsUpIsDropped() async throws {
        let gate = PromptGate()
        let box = try rig(timer: .five) { ticks in { _ in ticks.bump(); await gate.arrive() } }
        box.controller.begin(.panel)
        box.controller.begin(.panel)
        box.controller.begin(.fullScreen)
        XCTAssertEqual(box.shown.count, 1, "a second panel press raised a second bar")
        box.controller.capture(from: .screen)
        box.controller.capture(from: .screen)
        await gate.reached()
        await gate.open()
        await waitUntil("the press was delivered") { box.disk.written >= 1 }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 1, "a press during the bar or its countdown froze the screen again")
    }
}
