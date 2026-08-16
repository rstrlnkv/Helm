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

    /// A tail nothing is writing to — the owner's machine between log lines.
    /// The page still pays per second: this is the cost of watching a log that
    /// says nothing.
    func testAQuietTailStillChurnsEverySecond() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let box = TailBox(Self.fixtureTail())
        let (view, window) = mountedLogPage(box)
        defer { window.contentView = nil }

        // Warm-up: CoreText, glyph caches, the first full render of 1000 rows.
        letThePageTick(seconds: 3, view: view)
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

        let perTickKept = laps.map(\.kept).reduce(0, +) / max(ticks, 1)
        let peakLine = laps.map { String(format: "kept %+d KB, transient peak %d KB",
                                         $0.kept / 1024, $0.peak / 1024) }
            .joined(separator: "; ")
        print("log page, quiet tail of 1000: \(ticks) ticks in 3×5 s laps — \(peakLine); "
              + String(format: "%.0f B kept per tick", Double(perTickKept)))

        // Report plus one deterministic bound: a page polling an unchanged tail
        // must not *keep* memory per tick. Transient churn is timing-dependent
        // and is the printed half; a sustained keep would be the hidden-page
        // ratchet all over again, and that it fails on.
        XCTAssertLessThan(perTickKept, 64 * 1024,
            "the log page kept \(perTickKept) bytes per tick of a tail nobody wrote to")
    }

    /// A tail that grows one line per poll — the busiest the real page gets
    /// outside an operation, since `LogTail` is written per event and the page
    /// polls once a second.
    func testAGrowingTailPerTickCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let box = TailBox(Self.fixtureTail())
        box.appendPerCall = true
        let (view, window) = mountedLogPage(box)
        defer { window.contentView = nil }

        letThePageTick(seconds: 3, view: view)
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
        XCTAssertGreaterThanOrEqual(ticks, 9, "the tick fired \(ticks) times; too few to measure")

        let perTickKept = laps.map(\.kept).reduce(0, +) / max(ticks, 1)
        let peakLine = laps.map { String(format: "kept %+d KB, transient peak %d KB",
                                         $0.kept / 1024, $0.peak / 1024) }
            .joined(separator: "; ")
        print("log page, growing tail at cap: \(ticks) ticks in 3×5 s laps — \(peakLine); "
              + String(format: "%.0f B kept per tick", Double(perTickKept)))
    }
}
