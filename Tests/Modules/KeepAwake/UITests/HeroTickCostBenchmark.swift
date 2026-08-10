import XCTest
import SwiftUI
import AppKit
import Darwin
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// What one second's tick of `KeepAwakeSettingsPage.sessionHero` costs, and
/// whether the cost depends on whether anything visible actually changes.
///
/// `TimelineView(.periodic(from: .now, by: 1))` re-runs its content closure
/// once a second for as long as the settings window is open, whatever state
/// the hero is in. `.idle`, `.indefinite` and `.automatic` draw nothing that
/// depends on `now` — no digits, no `timedNote` — so every tick in those three
/// states recomputes `SessionHero.of(...)`, reinitialises `KeepAwakeHero` and
/// asks SwiftUI to diff a view that cannot have changed. Only `.timed` has
/// anything to redraw.
///
/// This is a *timing* question, so it prints rather than asserts — the number
/// depends on the machine it runs on, the house rule for anything gated behind
/// `HELM_BENCH=1` (`ScanConditionsPerTickBenchmark` is the model).
///
/// `HELM_BENCH=1 swift test --filter HeroTickCostBenchmark`
@MainActor
final class HeroTickCostBenchmark: XCTestCase {

    private final class Box: ObservableObject {
        @Published var state: SessionHero = .idle
        @Published var suppressed = false
        @Published var tick = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private struct Harness: View {
        @ObservedObject var box: Box
        var body: some View {
            KeepAwakeHero(state: box.state, now: box.tick, anyRuleOn: true,
                          defaultDurationMinutes: 60, suppressed: box.suppressed,
                          heldByOthers: false,
                          ruleHolds: true,
                          timedNote: { end in
                              // What the real page does on every `.timed` tick:
                              // `SessionHero.holderAfterTimer` plus a formatted
                              // clock reading, not a stub.
                              let until = HelmDates.timeOfDay(end)
                              guard let holder = SessionHero.holderAfterTimer(
                                      conditions: [], timerEndsAutomation: false) else {
                                  return until
                              }
                              return until + " · \(holder)"
                          },
                          start: { _ in }, stop: {}, resume: {})
                .frame(width: HelmLayout.settingsColumn)
        }
    }

    /// A view that never reads `box.tick` at all — the floor imposed by the
    /// drain below (a `RunLoop` pass, an `NSWindow`, an `NSHostingView`), with
    /// no SwiftUI diffing work behind it, since nothing this view reads ever
    /// changes. Every hero reading is reported beside this one, because the
    /// drain's own floor is otherwise indistinguishable from real work in the
    /// number and would make an idle tick look expensive whether or not it is.
    private struct StaticHarness: View {
        var body: some View {
            Text("static").font(.system(size: 40, weight: .light))
                .frame(width: HelmLayout.settingsColumn)
        }
    }

    /// Ticks `box.tick` (and, for `.timed`, keeps the deadline in the future)
    /// `count` times, draining the run loop briefly after each — the same
    /// shape `HeroMotionProbe.series` uses to let SwiftUI actually act on a
    /// change, shortened because this file times many more of them.
    private func costOfTicking(_ state: SessionHero?, count: Int) -> Double {
        let box = Box()
        let host: NSHostingView<AnyView>
        if let state {
            box.state = state
            host = NSHostingView(rootView: AnyView(Harness(box: box)))
        } else {
            host = NSHostingView(rootView: AnyView(StaticHarness()))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 780, height: 300)
        window.layoutIfNeeded()
        for _ in 0..<10 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }

        let start = Date()
        for i in 1...count {
            box.tick = Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            if let state, case .timed = state {
                box.state = .timed(until: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) + 3600))
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
        }
        let elapsed = Date().timeIntervalSince(start)
        window.contentView = nil
        return elapsed / Double(count) * 1000
    }

    func testTickCostByState() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let ticks = 200
        let floor = costOfTicking(nil, count: ticks)
        let idle = costOfTicking(.idle, count: ticks)
        let indefinite = costOfTicking(.indefinite, count: ticks)
        let automatic = costOfTicking(.automatic([.externalDisplay]), count: ticks)
        let timed = costOfTicking(.timed(until: Date(timeIntervalSince1970: 1_700_003_600)),
                                  count: ticks)
        print(String(format: "hero tick, %d ticks each: floor (no dependency on the tick "
                     + "at all) %.4f ms/tick, idle %.4f ms/tick, indefinite %.4f ms/tick, "
                     + "automatic %.4f ms/tick, timed %.4f ms/tick",
                     ticks, floor, idle, indefinite, automatic, timed))
        print(String(format: "over the floor: idle +%.4f ms, indefinite +%.4f ms, "
                     + "automatic +%.4f ms, timed +%.4f ms",
                     idle - floor, indefinite - floor, automatic - floor, timed - floor))
        // An hour open on each non-countdown state — the common case, since a
        // countdown is the exception rather than the rule for a settings
        // window left open. The floor is subtracted out: what the drain costs
        // regardless is not this file's finding, only what the hero adds to it.
        print(String(format: "projected over one hour open (3600 ticks), floor subtracted: "
                     + "idle %.2f s, indefinite %.2f s, automatic %.2f s, timed %.2f s",
                     (idle - floor) * 3600 / 1000, (indefinite - floor) * 3600 / 1000,
                     (automatic - floor) * 3600 / 1000, (timed - floor) * 3600 / 1000))
    }

    // MARK: - The pure cost inside `.timed`: `timedNote`

    /// `timedNote` — `SessionHero.holderAfterTimer` plus `HelmDates.timeOfDay`
    /// — is the one piece of per-tick work the brief calls out by name. Timed
    /// without any view around it, warm (the formatter is cached after the
    /// first call — `HelmDates`'s own `Cache`).
    func testTimedNoteWarmCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        _ = HelmDates.timeOfDay(end) // pay the first-call formatter build outside the timing
        let iterations = 5000
        let start = Date()
        for _ in 0..<iterations {
            let until = HelmDates.timeOfDay(end)
            let holder = SessionHero.holderAfterTimer(conditions: [.externalDisplay],
                                                       timerEndsAutomation: false)
            _ = holder.map { until + " · \($0)" } ?? until
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "timedNote (warm): %.5f ms/call (%d calls in %.4f s)",
                     elapsed / Double(iterations) * 1000, iterations, elapsed))
    }

    // MARK: - Memory: a settings window left open for hours

    /// Bytes malloc currently has handed out, across every zone — the
    /// allocator's own books, not `MemoryFootprint.current()`
    /// (`phys_footprint`), which answers what the *process* costs the machine
    /// and can read flat across a fill that really did allocate (§ the house
    /// rule on `HashCacheScaleBenchmark`).
    private static func allocatedBytes() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// A session left running for hours with the settings window open is
    /// thousands of ticks of the same hero, the same `timedNote`, the same
    /// `NSBezierPath`/`NSHostingView` machinery underneath — all of it
    /// transient by design (a `String`, a view value, freed the moment the
    /// tick that made it is over). This runs three checkpoints an hour apart
    /// (in ticks, not wall clock) and asks whether the allocator's count keeps
    /// climbing between them, the way it would if something were being kept
    /// rather than freed.
    ///
    /// A **negative result recorded on purpose** (§ the house rule on keeping
    /// one): the expectation going in is that nothing here should grow, and
    /// this is what proves that expectation rather than assuming it.
    func testNoGrowthAcrossSimulatedHoursOfTicking() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let box = Box()
        box.state = .timed(until: Date(timeIntervalSince1970: 1_700_000_000 + 999_999))
        let host = NSHostingView(rootView: AnyView(Harness(box: box)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 780, height: 300)
        window.layoutIfNeeded()
        for _ in 0..<10 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }

        func tick(_ count: Int, from base: Int) {
            for i in 0..<count {
                autoreleasepool {
                    let t = base + i
                    box.tick = Date(timeIntervalSince1970: 1_700_000_000 + Double(t))
                    box.state = .timed(until: Date(timeIntervalSince1970: 1_700_000_000
                                                   + Double(t) + 3600))
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
                }
            }
        }

        let perCheckpoint = 600 // simulated ten minutes of ticks
        // Two warm-up laps, not one: the first pays for CoreText/CoreGraphics
        // glyph and path caches filling for the first time (measured: tens of
        // megabytes, one time, system-wide — not this view's own doing), and a
        // single lap left that noise sitting inside the very delta meant to
        // catch a *per-tick* leak. A second lap confirms those caches really
        // have settled before either measured lap begins.
        tick(perCheckpoint, from: 0)
        tick(perCheckpoint, from: perCheckpoint)
        let afterWarmup = Self.allocatedBytes()
        tick(perCheckpoint, from: perCheckpoint * 2)
        let afterSecondLap = Self.allocatedBytes()
        tick(perCheckpoint, from: perCheckpoint * 3)
        let afterThirdLap = Self.allocatedBytes()
        window.contentView = nil

        let firstDelta = afterSecondLap - afterWarmup
        let secondDelta = afterThirdLap - afterSecondLap
        print(String(format: "allocator size_in_use after warm-up: %d KB; "
                     + "+%d KB over the next %d ticks, +%d KB over the %d after that",
                     afterWarmup / 1024, firstDelta / 1024, perCheckpoint,
                     secondDelta / 1024, perCheckpoint))
        // A real per-tick leak would make the second lap's growth track the
        // first's (both cover the same number of ticks); steady-state churn
        // does not scale with lap count at all. 200 bytes/tick is generous —
        // well above String/formatter noise and well below anything that kept
        // a `Date` or a `String` per tick (24+ bytes each, and the hero builds
        // several per tick already counted in `firstDelta`).
        let ceiling = perCheckpoint * 200
        XCTAssertLessThan(secondDelta, max(firstDelta, ceiling),
                          "allocator use grew \(secondDelta) bytes over the third lap of "
                          + "\(perCheckpoint) ticks after \(firstDelta) bytes over the second — "
                          + "growth is tracking tick count rather than settling")
    }
}
