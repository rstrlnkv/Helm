import XCTest
import HelmRuntime
import HelmUI
@testable import HelmApp

/// What the menu-bar ring costs while a Keep Awake countdown is running: how
/// often `StatusItemController.refreshIcon` actually asks `MenuBarIcon.make`
/// for a new bitmap, against how often the 1 Hz `timerTick` fires it.
///
/// `refreshIcon` guards every call behind `StatusPlan.redrawKey`, comparing it
/// to the previous one and returning unless it changed — so the ring is not
/// redrawn on every tick merely because the tick happened. `redrawKey` also
/// *buckets* `timerProgress` to whole percent (`ARCHITECTURE.md`'s reasoning:
/// "a countdown moves by far less than a pixel per tick"), so a plain ring
/// redraws roughly a hundred times over the life of a session, however long it
/// runs — not 3600 times over an hour. **The countdown title is not bucketed**:
/// `TimerProgress.label` changes every second, and `redrawKey` folds `title` in
/// verbatim, so a session with "Show timer text" on redraws at 1 Hz regardless
/// of the ring.
///
/// `HELM_BENCH=1 swift test --filter MenuBarIconRedrawBenchmark`
final class MenuBarIconRedrawBenchmark: XCTestCase {

    /// `refreshIcon`'s own comparison, reproduced without a status bar: the
    /// number of distinct keys `redrawKey` produces across a whole session,
    /// tick by tick, is the number of times `MenuBarIcon.make` would actually
    /// run. Not a fake standing in for `StatusItemController` — the real
    /// `StatusPlan.redrawKey` and `StatusPlan.frame`, the same two calls
    /// `refreshIcon` makes.
    private func distinctKeys(sessionMinutes: Int, showTimerText: Bool) -> Int {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(TimeInterval(sessionMinutes * 60))
        var seen = Set<String>()
        var now = start
        while now < end {
            let remaining = end.timeIntervalSince(now)
            let progress = remaining / TimeInterval(sessionMinutes * 60)
            let title = showTimerText ? TimerLabel.label(remaining: remaining) : nil
            seen.insert(StatusPlan.redrawKey(style: "ring", size: "extraSmall", tint: "orange",
                                             progress: progress, title: title, frame: nil))
            now.addTimeInterval(1)
        }
        return seen.count
    }

    /// A plain ring, no countdown text: bucketed to the percent, so it redraws
    /// close to a hundred times whether the session is fifteen minutes or two
    /// hours — not once a second.
    func testARingAloneRedrawsAboutOncePerPercentNotOncePerSecond() {
        for minutes in [15, 60, 120] {
            let seconds = minutes * 60
            let keys = distinctKeys(sessionMinutes: minutes, showTimerText: false)
            XCTAssertLessThan(keys, 105,
                              "\(minutes) min session: \(keys) distinct icons over \(seconds) "
                              + "ticks — the percent bucket in StatusPlan.redrawKey stopped "
                              + "working")
        }
    }

    /// The countdown text is not bucketed, so turning it on takes the redraw
    /// rate from "about a hundred times a session" to "every second the
    /// session runs" — the real cost `refreshIcon` pays is however long
    /// `MenuBarIcon.make` itself takes (timed below), not the tick rate, which
    /// is fixed at 1 Hz by `timerTick` either way.
    func testShowingTheCountdownTextRedrawsEverySecond() {
        let minutes = 15
        let seconds = minutes * 60
        let keys = distinctKeys(sessionMinutes: minutes, showTimerText: true)
        // Not exactly `seconds`: the label only changes once a whole second of
        // display value ticks over, which is every loop iteration here since
        // the loop itself steps in whole seconds — so this is the ceiling, and
        // it should be close to it.
        XCTAssertGreaterThan(keys, seconds - 5,
                             "with the countdown text on, only \(keys) of \(seconds) ticks "
                             + "actually redrew — title stopped forcing a redraw every second")
    }

    // MARK: - What one `MenuBarIcon.make` costs

    /// The redraw itself: `lockFocus`, an `NSBezierPath`, `flattened` at 0.02
    /// flatness, walking the perimeter to find its start point, then stroking
    /// two arcs. Timed at the size and style Keep Awake actually ships
    /// (`.extraSmall`/M, `.ring`), warm. Report only — a wall-clock figure
    /// depends on the machine.
    func testMenuBarIconMakeWarmCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        _ = MenuBarIcon.make(style: .ring, size: .extraSmall, tintToken: "orange", progress: 0.5)
        let iterations = 500
        let start = Date()
        for i in 0..<iterations {
            _ = MenuBarIcon.make(style: .ring, size: .extraSmall, tintToken: "orange",
                                 progress: Double(i % 100) / 100)
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "MenuBarIcon.make(ring, progress:) warm: %.4f ms/call "
                     + "(%d calls in %.4f s)",
                     elapsed / Double(iterations) * 1000, iterations, elapsed))

        let plainStart = Date()
        for _ in 0..<iterations {
            _ = MenuBarIcon.make(style: .ring, size: .extraSmall, tintToken: "orange")
        }
        let plainElapsed = Date().timeIntervalSince(plainStart)
        print(String(format: "MenuBarIcon.make(ring, no progress) warm: %.4f ms/call "
                     + "(%d calls in %.4f s)",
                     plainElapsed / Double(iterations) * 1000, iterations, plainElapsed))
    }

    /// The number that matters once "show timer text" forces a redraw every
    /// second: a whole 15-minute session's worth of them, in one figure.
    func testMenuBarIconMakeOverAFullCountdownWithTextOn() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let seconds = 15 * 60
        _ = MenuBarIcon.make(style: .ring, size: .extraSmall, tintToken: "orange", progress: 0.5)
        let start = Date()
        for i in 0..<seconds {
            _ = MenuBarIcon.make(style: .ring, size: .extraSmall, tintToken: "orange",
                                 progress: Double(seconds - i) / Double(seconds))
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "a 15-minute countdown with the timer text on: %d redraws, "
                     + "%.3f s of MenuBarIcon.make total (%.4f ms/redraw)",
                     seconds, elapsed, elapsed / Double(seconds) * 1000))
    }
}

/// `TimerProgress.label` lives in `Module_KeepAwake_Engine`, which
/// `HelmAppTests` does not depend on (the host never links a module's engine —
/// `ARCHITECTURE.md` § Targets). The formatting rule is simple enough to state
/// here rather than pull the module in for one label, and this file only needs
/// it to change every second, which any monotonic label does.
private enum TimerLabel {
    static func label(remaining seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
