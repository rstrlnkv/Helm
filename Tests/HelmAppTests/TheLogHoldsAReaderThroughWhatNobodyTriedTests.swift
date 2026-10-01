import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page in a window on screen, under the changes
/// `TheLogKeepsAReaderWhereTheyWereTests` does not make: a fold opened at the
/// top of the view, the window *widened*, a card crossing
/// `LogView.lazyAbove` while it is read, and — with Follow lit — whether the end
/// is reached in one landing or in steps a person would see.
///
/// The reader's place is read the way that file reads it, by the pixels of the
/// one red glyph on the page (`TheLogKeepsAReaderWhereTheyWereTests.Window`).
@MainActor
final class TheLogHoldsAReaderThroughWhatNobodyTriedTests: XCTestCase {

    private typealias Window = TheLogKeepsAReaderWhereTheyWereTests.Window

    /// The cases that reproduce a defect found and not yet decided are skipped
    /// unless `HELM_KNOWN_GAPS=1`, the reproduction below each skip untouched, the
    /// convention `TheLogsHeadingsAndMarksHoldInEveryLanguageAndAppearanceTests`
    /// follows. When a gap is closed, delete its skip.
    private static var knownGapsRun: Bool { ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1" }

    /// As in the file beside this one: a point of rounding and room for a pixel.
    private let still: CGFloat = 2
    private let atTheEnd: CGFloat = HelmSpace.s5 + 1

    // MARK: - Fixtures

    /// Launches of a given number of rows each, every line distinct (a repeated
    /// line folds into one row with a count), one long line in seven so a change
    /// of width changes the heights, and one error line — the landmark — in the
    /// launch `landmarkIn` at row `landmarkRow`. The first launch has no start
    /// line: it is the tail's head, as on any Mac whose log is full.
    static func tail(rows: [Int], landmarkIn: Int, landmarkRow: Int) -> [LogEntry] {
        var lines: [LogEntry] = []
        var at = Date(timeIntervalSince1970: 1_789_000_000)
        let modules = ["vpn", "memory", "host", "layout", "autopilot", "disk"]
        for (launch, count) in rows.enumerated() {
            if launch > 0 {
                at.addTimeInterval(3_600)
                lines.append(LogEntry(date: at, level: .info, category: "app",
                                      message: "Helm 0.11.1-dev.\(launch) started"))
                for module in modules {
                    at.addTimeInterval(0.02)
                    lines.append(LogEntry(date: at, level: .info, category: "host", message: "enable \(module)"))
                }
            }
            for index in 0..<count {
                at.addTimeInterval(7)
                if launch == landmarkIn, index == landmarkRow {
                    lines.append(LogEntry(date: at, level: .error, category: "disk",
                                          message: "LANDMARK — the line the reader is reading"))
                    continue
                }
                let long = index % 7 == 3
                let message = "launch \(launch) line \(index)"
                    + (long ? " " + String(repeating: "a line long enough to wrap ", count: 9) : "")
                lines.append(LogEntry(date: at, level: index % 31 == 0 ? .warn : .info,
                                      category: modules[index % modules.count], message: message))
            }
        }
        return lines
    }

    /// One more line at the end of a full tail, the oldest leaving, as `LogTail`
    /// rotates.
    private func arrive(_ page: Window, _ message: String = "network state changed; re-reading") {
        let last = page.source.lines[page.source.lines.count - 1].date
        page.source.lines = Array((page.source.lines + [LogEntry(date: last.addingTimeInterval(5), level: .info,
                                                                 category: "vpn", message: message)])
            .suffix(HelmLog.tailLimit))
    }

    // MARK: - Follow off: a fold opened in view

    /// Follow off, a start-up fold at the very top of the view, opened by a
    /// click: the lines it brings are drawn below the fold the person clicked,
    /// where they asked for them. The view does not move — a press on something
    /// in view is not a change under the reader, and the first line below the
    /// fold is the one `LogReaderPlace` would otherwise hold, by scrolling the
    /// opened lines up out of view.
    func testAFoldOpenedAtTheTopOfTheViewOpensInView() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-fold-at-top: the held line below a fold at the top of the view scrolls the opened lines out of view")
        let lines = Self.tail(rows: [0, 200], landmarkIn: -1, landmarkRow: -1)
        var moved: [String] = []
        var opened = 0
        for width in [760, 1_000] as [CGFloat] {
            let page = Window(lines, width: width)
            defer { page.close() }
            page.pump(3)
            try page.pressFollow()
            try page.scroll(toY: 0)
            page.pump(0.6)
            let scroll = try XCTUnwrap(page.scroll)
            let before = scroll.documentVisibleRect.minY
            let was = page.reading()
            guard try page.openFoldBelow(0, through: 160) else { continue }
            opened += 1
            let after = scroll.documentVisibleRect.minY
            if abs(after - before) > still {
                moved.append("\(Int(width)) pt: the view moved \(Int(after - before)) pt (\(was) → \(page.reading()))")
            }
        }
        XCTAssertGreaterThan(opened, 0, "no click opened the fold, so nothing was asked")
        XCTAssertTrue(moved.isEmpty, "opening a fold at the top of the view scrolled away from it — "
                      + moved.joined(separator: "; "))
    }

    // MARK: - Follow off: the window widened

    /// Follow off, the window widened: every row above the reader that wrapped
    /// now takes fewer lines, and an offset held across that puts lines from
    /// further down in front of them. The widenings are the narrowings
    /// `testNarrowingTheWindowKeepsTheLineBeingReadInView` makes, undone.
    func testWideningTheWindowKeepsTheLineBeingRead() throws {
        var lost: [String] = []
        let tails: [(String, [LogEntry])] = [
            ("owner-shaped", TheLogKeepsAReaderWhereTheyWereTests.tailWithLandmark(
                TheLogOpensOnItsNewestLineInARealWindowTests.ownerShapedTail())),
        ] + (TheLogKeepsAReaderWhereTheyWereTests.realTailWithLandmark().map { [("real", $0)] } ?? [])
        for (name, lines) in tails {
            for (from, to) in [(760, 1_000), (670, 810)] as [(CGFloat, CGFloat)] {
                let page = Window(lines, width: from)
                defer { page.close() }
                page.pump(3)
                try page.pressFollow()
                let before = try page.scrollToLandmark()
                let was = page.reading()
                var frame = page.window.frame
                frame.size.width += to - from
                page.window.setFrame(frame, display: true)
                page.pump(2.5)
                XCTAssertEqual(page.host.bounds.width, to, accuracy: 1, "the window did not widen")
                let after = page.landmark()
                if after.map({ abs($0 - before) > still }) ?? true {
                    lost.append("\(name) \(Int(from)) → \(Int(to)) pt: line at \(Int(before)) pt → "
                                + (after.map { "\(Int($0)) pt" } ?? "out of view")
                                + " (\(was) → \(page.reading()))")
                }
            }
        }
        XCTAssertTrue(lost.isEmpty, "with Follow off a wider window moved the line being read — "
                      + lost.joined(separator: "; "))
    }

    // MARK: - Follow off: a card crossing the lazy threshold

    /// Follow off, the reader inside the newest launch, which holds two rows
    /// under `LogView.lazyAbove` — drawn plain — while lines arrive one by one
    /// and take it past the threshold, where its rows are drawn lazily: the
    /// stack the rows live in is replaced under the reader.
    func testTheReadersCardGrowingPastTheLazyThresholdKeepsTheLine() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-lazy-crossing: a card turning lazy under the reader loses the line")
        let rows = LogView.lazyAbove - 2
        let lines = Self.tail(rows: [300, HelmLog.tailLimit - 300 - 7 - 7 - rows, rows],
                              landmarkIn: 2, landmarkRow: rows / 2)
        XCTAssertEqual(lines.count, HelmLog.tailLimit, "precondition: the tail is full")
        try crossing(lines, arrivals: 5, label: "newest card 398 → 403 rows")
    }

    /// Follow off, the reader inside the tail's head, two rows over the
    /// threshold — drawn lazily — while lines arrive and the oldest leave it,
    /// until it is drawn plain.
    func testTheReadersCardShrinkingUnderTheLazyThresholdKeepsTheLine() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-lazy-crossing: a card turning plain under the reader moves the line")
        let rows = LogView.lazyAbove + 2
        let lines = Self.tail(rows: [rows, 284, HelmLog.tailLimit - rows - 7 - 284 - 7],
                              landmarkIn: 0, landmarkRow: rows / 2)
        XCTAssertEqual(lines.count, HelmLog.tailLimit, "precondition: the tail is full")
        try crossing(lines, arrivals: 5, label: "head card 402 → 397 rows")
    }

    /// Follow off, the reader in a plain card *below* a lazy head card, while
    /// lines arrive and the oldest leave the lazy card above them.
    func testAReaderBelowALazyCardKeepsTheLineAsTheHeadShrinks() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-below-lazy: a lazy card above a plain one loses the reader as lines arrive")
        let lines = Self.tail(rows: [600, HelmLog.tailLimit - 600 - 7 - 100 - 7, 100],
                              landmarkIn: 1, landmarkRow: 150)
        XCTAssertEqual(lines.count, HelmLog.tailLimit, "precondition: the tail is full")
        try crossing(lines, arrivals: 5, label: "reader below a lazy head of 600 rows")
    }

    private func crossing(_ lines: [LogEntry], arrivals: Int, label: String) throws {
        var moved: [String] = []
        for width in [760, 1_000] as [CGFloat] {
            let page = Window(lines, width: width)
            defer { page.close() }
            page.pump(3)
            try page.pressFollow()
            let before = try page.scrollToLandmark()
            let was = page.reading()
            var path: [String] = []
            for index in 0..<arrivals {
                arrive(page, "an arriving line \(index)")
                page.pump(1.6)
                let at = page.landmark()
                path.append(at.map { "\(Int($0))" } ?? "gone")
            }
            let after = page.landmark()
            if after.map({ abs($0 - before) > still }) ?? true {
                moved.append("\(Int(width)) pt: line at \(Int(before)) → \(path.joined(separator: " → "))"
                             + " (\(was) → \(page.reading()))")
            }
        }
        XCTAssertTrue(moved.isEmpty, "\(label): with Follow off the line being read moved as lines arrived — "
                      + moved.joined(separator: "; "))
    }

    // MARK: - Follow lit: one landing, or steps

    /// What the view's top did after a change, one sample per turn of the run
    /// loop — each turn is a frame the window drew.
    private struct Timeline {
        var samples: [(t: Double, top: CGFloat, gap: CGFloat)] = []

        /// Moves of more than two points, grouped into landings: a move more
        /// than 50 ms after the previous one starts a new landing, which a person
        /// sees as the list stopping and then jumping again.
        var landings: [(t: Double, by: CGFloat)] {
            var out: [(t: Double, by: CGFloat)] = []
            var lastMove = -1.0
            for (a, b) in zip(samples, samples.dropFirst()) where abs(b.top - a.top) > 2 {
                if lastMove < 0 || b.t - lastMove > 0.05 { out.append((b.t, b.top - a.top)) }
                else { out[out.count - 1].by += b.top - a.top }
                lastMove = b.t
            }
            return out
        }

        /// The longest stretch between two drawn frames — a turn of the run
        /// loop the main thread spent on the change.
        var longestFrame: Double {
            zip(samples, samples.dropFirst()).map { $1.t - $0.t }.max() ?? 0
        }

        var summary: String {
            landings.map { String(format: "%+.0f pt at %.0f ms", $0.by, $0.t * 1000) }.joined(separator: ", ")
                + String(format: "; longest frame %.0f ms", longestFrame * 1000)
        }
    }

    private func record(_ page: Window, seconds: Double, _ change: () throws -> Void) throws -> Timeline {
        let scroll = try XCTUnwrap(page.scroll)
        var line = Timeline()
        let start = CFAbsoluteTimeGetCurrent()
        func sample() {
            let top = scroll.documentVisibleRect.minY
            let gap = (scroll.documentView?.frame.height ?? 0) - scroll.documentVisibleRect.maxY
            line.samples.append((CFAbsoluteTimeGetCurrent() - start, top, gap))
        }
        sample()
        try change()
        while CFAbsoluteTimeGetCurrent() - start < seconds {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.004))
            sample()
        }
        return line
    }

    /// Follow lit at the end: a line arrives, Warnings → All, Follow pressed
    /// again from the top. Each must end at the end, in one landing.
    func testFollowLitReachesTheEndInOneLanding() throws {
        var stepped: [String] = []
        var short: [String] = []
        var unmoved: [String] = []
        var readings: [String] = []
        let ownerShaped = TheLogOpensOnItsNewestLineInARealWindowTests.ownerShapedTail()
        let oneLaunch = Self.tail(rows: [HelmLog.tailLimit], landmarkIn: -1, landmarkRow: -1)
        for (name, lines) in [("owner-shaped", ownerShaped), ("one long launch", oneLaunch)] {
            for width in [760, 1_000] as [CGFloat] {
                func check(_ what: String, _ line: Timeline, mustMove: Bool = false) {
                    let gap = line.samples.last?.gap ?? .infinity
                    readings.append("\(name), \(what), \(Int(width)) pt: [\(line.summary)] ends \(Int(gap)) pt short")
                    // The subject: the view moved at all, where the change has
                    // to move it. An arriving line need not: the oldest leaving
                    // the top can take the height the new one brings.
                    if mustMove, line.landings.isEmpty { unmoved.append("\(name), \(what), \(Int(width)) pt") }
                    if gap > atTheEnd { short.append("\(name), \(what), \(Int(width)) pt: \(Int(gap)) pt short") }
                    if line.landings.count > 1 {
                        stepped.append("\(name), \(what), \(Int(width)) pt: \(line.summary)")
                    }
                }
                let page = Window(lines, width: width)
                defer { page.close() }
                page.pump(3)
                XCTAssertLessThanOrEqual(try page.gap(), atTheEnd, "\(name) did not open at the end")
                // A line arrives; the page reads its source once a second.
                check("a line arriving", try record(page, seconds: 2.2) { arrive(page) })
                check("a long line arriving", try record(page, seconds: 2.2) {
                    arrive(page, String(repeating: "a long line arriving ", count: 120))
                })
                // Warnings, then All, measured from the press of All.
                try page.level(1)
                let content = try XCTUnwrap(page.channel.content(for: "log"))
                let binding = try XCTUnwrap(content.selectedTab)
                check("Warnings → All", try record(page, seconds: 2) { binding.wrappedValue = content.tabs[0].id },
                      mustMove: true)
                // Follow off, to the top, Follow on.
                try page.pressFollow()
                try page.scroll(toY: 0)
                let follow = try XCTUnwrap(content.actions.first { $0.id == "follow" })
                guard case .toggle(_, let perform) = follow.kind else { return XCTFail("Follow is not a toggle") }
                check("Follow from the top", try record(page, seconds: 2) { perform() }, mustMove: true)
            }
        }
        print("follow-lit landings — " + readings.joined(separator: "; "))
        XCTAssertTrue(unmoved.isEmpty, "the view never moved, so nothing was asked — " + unmoved.joined(separator: "; "))
        XCTAssertTrue(short.isEmpty, "Follow lit and the newest line out of view — " + short.joined(separator: "; "))
        XCTAssertTrue(stepped.isEmpty, "Follow lit reached the end in more than one landing — "
                      + stepped.joined(separator: "; "))
    }

    // MARK: - The cost of a tick, on screen

    /// The longest stretch the main thread spent awake while one line arrived
    /// at a full tail, measured by a run-loop observer between waking and going
    /// back to sleep — so the deferred work the page schedules after the read
    /// (`LogReaderPlace`'s rest timer, the hop to the end) is counted in its own
    /// turn too. On screen, in a window, at 810 pt. A report: `HELM_BENCH=1`; it
    /// fails only when a turn costs more than the tick's own interval.
    func testTheMainThreadCostOfOneArrivingLineOnScreen() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        var shapes: [(String, [LogEntry])] = [
            ("owner-shaped (9 cards, plain)", TheLogOpensOnItsNewestLineInARealWindowTests.ownerShapedTail()),
            ("three launches of ~330 (plain)", Self.tail(rows: [330, 328, 328], landmarkIn: -1, landmarkRow: -1)),
            ("one launch of 1000 (lazy)", Self.tail(rows: [HelmLog.tailLimit], landmarkIn: -1, landmarkRow: -1)),
        ]
        if let real = TheLogKeepsAReaderWhereTheyWereTests.realTailWithLandmark() { shapes.append(("real", real)) }
        var report: [String] = []
        for (name, lines) in shapes {
            for following in [true, false] {
                let page = Window(lines, width: 810)
                defer { page.close() }
                page.pump(3)
                if !following {
                    try page.pressFollow()
                    try page.scroll(toY: (page.scroll?.documentView?.frame.height ?? 0) / 2)
                    page.pump(1)
                }
                var awake = 0.0
                var worst = 0.0
                var turns: [Double] = []
                let observer = CFRunLoopObserverCreateWithHandler(
                    nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
                    true, 0) { _, activity in
                        let now = CFAbsoluteTimeGetCurrent()
                        if activity == .afterWaiting { awake = now }
                        else if awake > 0 { worst = max(worst, now - awake); awake = 0 }
                    }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                for index in 0..<6 {
                    worst = 0
                    arrive(page, "an arriving line \(index)")
                    page.pump(1.3)
                    turns.append(worst * 1000)
                }
                // A level switched there and back: the whole list is laid out
                // anew both ways.
                worst = 0
                try page.level(1)
                let toWarnings = worst * 1000
                worst = 0
                try page.level(0)
                let toAll = worst * 1000
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                let sorted = turns.sorted()
                report.append(String(format: "%@, Follow %@: arriving line median %.0f ms, worst %.0f ms; "
                                     + "All → Warnings %.0f ms, Warnings → All %.0f ms", name,
                                     following ? "on" : "off", sorted[sorted.count / 2], sorted.last ?? 0,
                                     toWarnings, toAll))
                XCTAssertLessThan(sorted.last ?? 0, 1000, "\(name): one arriving line held the main thread a second")
            }
        }
        print("log page, main thread per arriving line on screen — " + report.joined(separator: "; "))
    }
}
