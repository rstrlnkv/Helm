import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A countdown that was cancelled freezes nothing.** The timer's wait is a
/// second of nothing, as many times as the length is long, and the module can be
/// switched off, the close control pressed or Esc typed inside any of them. What
/// the press resumes into after the wait is a freeze of every screen, and then a
/// file or the clipboard — for a capture nobody wants any more.
///
/// The wait is the controller's `tick` seam, so a test holds it still: a gate
/// the test opens *after* cancelling is the case that matters, because a wait
/// that ends normally is no evidence that nobody cancelled during it, and a
/// controller that only ever read its own flag after the whole loop would look
/// right against a tick that returns at once.
///
/// Mutant, red here: the countdown does not ask after its wait whether it was cancelled.
@MainActor
final class TheCountdownEndsWithTheModuleTests: XCTestCase {

    private typealias Disk = FakeWorkDisk

    private typealias Board = CountingBoard

    private struct Rig {
        let controller: CaptureController
        let capture: FakeScreen
        let disk: Disk
        let ticks: LockedCount
        let shown: LockedCount
    }

    private func rig(timer: CaptureTimer, tick: @escaping (LockedCount) -> (Duration) async throws -> Void) throws -> Rig {
        // A display no screen carries: nothing here can reach a real screen.
        let capture = FakeScreen(outcome: try FakeScreen.frozen(real: false)), disk = Disk(), ticks = LockedCount(), shown = LockedCount()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = scratchDirectory("shots-countdown")
        let session = CaptureSession(capture: capture, writer: disk, trash: AsideTrash.refusing(), pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: CountingShutter(), textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(store: store,
                                           session: session, presentOverlay: { _ in false },
                                           presentBar: { _ in shown.bump() }, tick: tick(ticks))
        return Rig(controller: controller, capture: capture, disk: disk, ticks: ticks, shown: shown)
    }

    /// The control: nobody cancels, so the press counts every second on the bar,
    /// freezes **after** the last one, and delivers.
    func testACountdownLeftAloneFreezesOnlyAfterItsLastSecond() async throws {
        var atFreeze = -1
        let box = try rig(timer: .five) { ticks in { _ in ticks.bump() } }
        box.capture.onFreeze = { atFreeze = box.ticks.value }
        box.controller.begin(.panel)
        XCTAssertEqual(box.shown.value, 1, "the panel shortcut did not put the bar up")
        box.controller.capture(from: .screen)
        await waitUntil("the press was delivered") { box.disk.written == 1 }
        XCTAssertEqual(box.ticks.value, 5, "five seconds are five waits")
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
        XCTAssertEqual(box.ticks.value, 0)
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
            XCTAssertEqual(box.ticks.value, 1, "\(way): the countdown never started, so nothing was proved")
            cancel(box.controller)
            await gate.open()
            await grace(0.4)
            XCTAssertEqual(box.capture.freezes, 0, "\(way): a cancelled countdown still froze the screen")
            XCTAssertEqual(box.disk.written, 0, "\(way): a cancelled countdown still wrote a file")
            XCTAssertEqual(box.ticks.value, 1, "\(way): the countdown went on counting after it was cancelled")
        }
    }

    /// A wait that never completes and ends only by being cancelled: the module
    /// goes off inside it, and the machine must be free for the next press —
    /// one `busy` flag that stayed set would drop every press from then on.
    func testAWaitThatNeverEndsIsLeftByCancellingAndTheNextPressWorks() async throws {
        let box = try rig(timer: .five) { ticks in { _ in ticks.bump(); try await Task.sleep(for: .seconds(3600)) } }
        box.controller.begin(.panel)
        box.controller.capture(from: .screen)
        await waitUntil("the countdown started") { box.ticks.value == 1 }
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
        XCTAssertEqual(box.shown.value, 1, "a second panel press raised a second bar")
        box.controller.capture(from: .screen)
        box.controller.capture(from: .screen)
        await gate.reached()
        await gate.open()
        await waitUntil("the press was delivered") { box.disk.written >= 1 }
        await grace(0.3)
        XCTAssertEqual(box.capture.freezes, 1, "a press during the bar or its countdown froze the screen again")
    }
}
