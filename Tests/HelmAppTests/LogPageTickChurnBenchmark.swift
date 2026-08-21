import XCTest
import SwiftUI
import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What one second of the log page costs while somebody is reading it.
///
/// `LogView` polls: a `RepeatingTick(interval: 1)` calls `refresh()`, which
/// reassigns `@State entries` with a fresh copy of the tail (LogView.swift:381).
/// SwiftUI cannot know the copy is equal — a `@State` write dirties the page —
/// so every second the page is on screen re-evaluates `body`, re-filters the
/// full tail (`shown` is computed in three places), and re-diffs a `ForEach`
/// over up to 1000 rows, whether or not a single line arrived.
///
/// The page it measures is the one the owner triages on: the no-phase footprint
/// swings in `helm.log` (±80–140 MB between 15 s samples, «no phases running»)
/// cluster in exactly the sessions where the log page was open, need no
/// permission, and stop when the machine is left alone.
///
/// The fixture feeds a full tail — 1000 lines, the cap — through the page's own
/// `source:` parameter, which exists for measurement; nothing here reads this
/// Mac's log. Costs are read against the allocator's books
/// (`malloc_zone_statistics`' `size_in_use`), the house instrument for what a
/// loop allocates; `phys_footprint` is printed beside them only to tie the
/// figure to the samples the owner's log shows.
///
/// `HELM_BENCH=1 swift test --filter LogPageTickChurnBenchmark`
@MainActor
final class LogPageTickChurnBenchmark: XCTestCase {

    /// A tail at the cap, shaped like the real one: mostly info, a few warns,
    /// realistic message lengths, categories from several modules. Invented
    /// content — the page must never be measured against whatever this machine
    /// happens to have logged (LogView's own rule, at its `source` parameter).
    private static func fixtureTail() -> [LogEntry] {
        let categories = ["vpn", "memory", "scan", "layout", "autopilot",
                          "keepawake", "uninstaller", "app"]
        let messages = [
            "sample: 118 MB (+3 MB) — no phases running",
            "network state changed; re-reading",
            "duplicates: notDue",
            "watching 3 folder(s)",
            "settled: bench#dca3=disconnected, bench#7b99=connected",
            "holding sleep: app, display too",
            "swept 12, acted 1, refused 0, failed 0",
            "trash sweep requested",
        ]
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return (0..<1000).map { i in
            LogEntry(date: start.addingTimeInterval(Double(i) * 4.7),
                     level: i % 25 == 0 ? .warn : .info,
                     category: categories[i % categories.count],
                     message: messages[i % messages.count])
        }
    }

    /// The feeding end of the page's poll. Counts calls, so a lap can prove the
    /// tick actually fired — a run loop that never let the timer speak would
    /// measure silence and read as free (the vacuous-absence rule).
    private final class TailBox {
        var entries: [LogEntry]
        var calls = 0
        var appendPerCall = false
        init(_ entries: [LogEntry]) { self.entries = entries }
        func read() -> [LogEntry] {
            calls += 1
            if appendPerCall {
                entries.removeFirst()
                entries.append(LogEntry(date: Date(), level: .info, category: "vpn",
                                        message: "network state changed; re-reading"))
            }
            return entries
        }
    }

    private func mountedLogPage(_ box: TailBox) -> (NSHostingView<AnyView>, NSWindow) {
        let view = NSHostingView(rootView: AnyView(
            LogView(source: { box.read() }, storedLog: { false })
                .frame(width: 810, height: 700)))
        view.frame = NSRect(x: 0, y: 0, width: 810, height: 700)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        view.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        for _ in 0..<100 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return (view, window)
    }

    /// Spins the main run loop for `seconds`, letting the page's own 1 Hz tick
    /// fire — the page is driven by its real timer, not by a stand-in.
    private func letThePageTick(seconds: TimeInterval, view: NSView) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            autoreleasepool {
                view.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }
    }

    /// **Long enough that the first lap measures the page and not the
    /// process.**
    ///
    /// XCTest runs a class's cases in one process and in alphabetical order, so
    /// whichever sorts first pays for CoreText, the glyph caches and the first
    /// full render of a thousand rows — and at the 3 s this used to be, the
    /// growing-tail case was still handing memory back three laps later.
    /// Measured 2026-08-21, three runs: it reported −1987 KB on lap 1, −93 KB
    /// on lap 2 and +9 KB on lap 3, which averages to **−141 KB kept per
    /// tick**. That number is about warm-up settling, no ceiling could be
    /// derived from it, and it is why the case below had no ceiling at all —
    /// the quiet case looked honest only because it sorts second and inherited
    /// a warm process.
    ///
    /// At 15 s both settle before the first lap, and the two read 0.6–2.5 KB a
    /// tick instead of one reading 1.2 KB and the other −141 KB.
    private static let warmUpSeconds: TimeInterval = 15

    /// **The page must not *keep* memory per tick**, whatever the tail is
    /// doing. Transient churn is timing-dependent and is the printed half; a
    /// sustained keep is the hidden-page ratchet, and that is what both cases
    /// fail on.
    ///
    /// One constant and not a number written twice: the two cases ask the same
    /// question of the same page, so a ceiling that drifted between them would
    /// be two different promises wearing one name.
    ///
    /// **Both ends of it are measured, 2026-08-21.** Settled, the page keeps
    /// 0.6 KB a tick on the quiet tail and 1.7–2.5 KB on the growing one, so
    /// 64 KB is twenty-five times the worse reading and will not fail on noise.
    /// And it sits *under* the defect it exists for: made to retain the tail
    /// once per poll — the ratchet, planted in `TailBox.read` — the growing
    /// case reported **115 738 B/tick** and failed here. A ceiling between the
    /// two readings is a ceiling that can fail; one above 115 KB would have
    /// been a number that merely looked like a guard.
    private static let keptPerTickCeiling = 64 * 1024

    /// Three five-second laps of the page's own tick, and what it kept per one.
    ///
    /// The two cases differ in what the tail does between polls and in nothing
    /// else, so the lap loop is one function. Written twice it was two chances
    /// for the warm-up, the floor or the ceiling to stop agreeing — which is
    /// exactly what had happened to all three.
    private func keptPerTick(of box: TailBox, called label: String) -> Int {
        let (view, window) = mountedLogPage(box)
        defer { window.contentView = nil }

        letThePageTick(seconds: Self.warmUpSeconds, view: view)
        let ticksBefore = box.calls

        var laps: [(kept: Int, peak: Int)] = []
        for _ in 0..<3 {
            let before = AllocatorBooks.allocatedBytes()
            let (_, peak) = AllocatorPeak.during {
                letThePageTick(seconds: 5, view: view)
            }
            laps.append((AllocatorBooks.allocatedBytes() - before, peak))
        }
        let ticks = box.calls - ticksBefore
        // The subject must have happened: a run loop that starved the timer
        // would measure nothing and pass.
        XCTAssertGreaterThanOrEqual(ticks, 9,
            "the page's own 1 Hz tick fired \(ticks) times across 15 s of run loop; " +
            "the measurement below would be of silence")

        let kept = laps.map(\.kept).reduce(0, +) / max(ticks, 1)
        let peakLine = laps.map { String(format: "kept %+d KB, transient peak %d KB",
                                         $0.kept / 1024, $0.peak / 1024) }
            .joined(separator: "; ")
        print("log page, \(label): \(ticks) ticks in 3×5 s laps — \(peakLine); "
              + String(format: "%.0f B kept per tick", Double(kept)))
        return kept
    }

    /// A tail nothing is writing to — the owner's machine between log lines.
    /// The page still pays per second: this is the cost of watching a log that
    /// says nothing.
    func testAQuietTailStillChurnsEverySecond() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let kept = keptPerTick(of: TailBox(Self.fixtureTail()), called: "quiet tail of 1000")
        XCTAssertLessThan(kept, Self.keptPerTickCeiling,
            "the log page kept \(kept) bytes per tick of a tail nobody wrote to")
    }

    /// A tail that grows one line per poll — the busiest the real page gets
    /// outside an operation, since `LogTail` is written per event and the page
    /// polls once a second.
    ///
    /// **It was `testAGrowingTailPerTickCost` and it asserted nothing about the
    /// cost it was named for.** The figure was printed for a person to read,
    /// which is the shape `ReleaseDigestFootprintTests` had while a real leak
    /// sat behind it: a test that exists to catch a regression has to fail on
    /// one. What was missing first was not the assertion but a number worth
    /// asserting — see `warmUpSeconds`.
    func testAGrowingTailKeepsNothingPerTickEither() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let box = TailBox(Self.fixtureTail())
        box.appendPerCall = true
        let kept = keptPerTick(of: box, called: "growing tail at cap")
        XCTAssertLessThan(kept, Self.keptPerTickCeiling,
            "the log page kept \(kept) bytes per tick of a tail gaining a line a poll")
    }
}
