import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The inputs the Follow rule's key newly watches, taken one at a time on the
/// real page.
///
/// The rule scrolls to the list's end whenever Follow, the first shown line,
/// the newest shown line or the shown count changes, and only while Follow is
/// lit. So the questions are the edges of that key: with Follow off, none of
/// its inputs may move the reader; with the tail full, the first line and the
/// count change on every arrival and the view must still land on the newest
/// line without passing through somewhere else; a burst of lines must not turn
/// into a burst of scrolls; and the zero-height end mark the rule scrolls to
/// must add nothing a person can see or copy.
final class TheLogFollowRuleHoldsAtItsEdgesTests: XCTestCase {

    private let start = LogPageUnderHand.start

    /// A full tail: a thousand lines, the `LogTail` bound, with a day heading
    /// every `perDay` lines.
    private func fullTail(perDay: Int = 1_000_000) -> LogPageUnderHandSource {
        let source = LogPageUnderHandSource()
        source.lines = (0..<1000).map { index in
            LogEntry(date: date(index, perDay: perDay), level: index % 2 == 1 ? .warn : .info,
                     category: "app", message: "line \(index)")
        }
        return source
    }

    private func date(_ index: Int, perDay: Int) -> Date {
        let day = index / perDay
        return start.addingTimeInterval(Double(day) * 86_400 + Double(index % perDay))
    }

    /// What `LogTail.append` does once the buffer is full: the oldest line goes
    /// as the newest arrives, so the first identity and the last change
    /// together and the count stays at the bound.
    private func arrive(_ source: LogPageUnderHandSource, _ index: Int, perDay: Int = 1_000_000,
                        message: String? = nil) {
        source.lines.append(LogEntry(date: date(index, perDay: perDay), level: .info,
                                     category: "app", message: message ?? "line \(index)"))
        if source.lines.count > 1000 { source.lines.removeFirst(source.lines.count - 1000) }
    }

    // MARK: - Follow off: nothing the key watches moves the reader

    /// The filter changes the first line, the count and — under Errors-free
    /// logs — nothing else; with Follow off the reader stays where they were.
    @MainActor
    func testFollowOffAFilterChangeLeavesTheReaderWhereTheyWere() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.5)
        try page.pressFollow()
        try page.scrollNearTop()
        let held = try XCTUnwrap(page.scroll).documentVisibleRect.minY
        XCTAssertGreaterThan(try page.gap(), 1000, "the reader never left the end")

        try page.level(1)
        XCTAssertEqual(try XCTUnwrap(page.scroll).documentVisibleRect.minY, held, accuracy: 1,
                       "with Follow off, narrowing the filter moved the reader")
        XCTAssertGreaterThan(try page.gap(), 1000, "with Follow off, narrowing went to the end")
        try page.level(0)
        XCTAssertEqual(try XCTUnwrap(page.scroll).documentVisibleRect.minY, held, accuracy: 1,
                       "with Follow off, widening the filter moved the reader")
        XCTAssertGreaterThan(try page.gap(), 1000, "with Follow off, widening went to the end")
    }

    /// A full tail taking a line drops its oldest: the first identity and the
    /// last both change and the count does not. With Follow off the rule must
    /// not act. What the scroll view does on its own is to keep the lines under
    /// the reader where they were — the offset steps back by the one row that
    /// went from above — so the claim is that it never steps further than a
    /// row, and never towards the end.
    @MainActor
    func testFollowOffAFullTailDroppingItsOldestLineLeavesTheReader() throws {
        let source = fullTail()
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "the full tail did not open on its newest line")
        try page.pressFollow()
        try page.scrollNearTop()
        let firstBefore = source.lines.first?.id
        for index in 1000..<1003 {
            let before = try XCTUnwrap(page.scroll).documentVisibleRect.minY
            arrive(source, index)
            page.pump(1.2)
            let after = try XCTUnwrap(page.scroll).documentVisibleRect.minY
            print("follow off, full tail, line \(index): offset \(before) -> \(after)")
            XCTAssertLessThanOrEqual(abs(after - before), 24, "with Follow off, line \(index) "
                                     + "arriving into a full tail moved the reader \(after - before) pt")
            XCTAssertGreaterThan(try page.gap(), 1000, "with Follow off, line \(index) took the "
                                 + "reader to the end")
        }
        // The subject happened: the tail really was full and really dropped.
        XCTAssertEqual(source.lines.count, 1000)
        XCTAssertNotEqual(source.lines.first?.id, firstBefore, "the oldest line never went")
    }

    // MARK: - Follow on, a full tail

    /// Every arrival into a full tail changes the first identity and the last
    /// together. The view has to end on the newest line each time, and while
    /// it gets there it may not pass through anywhere further than one window
    /// from the end — a jump to the top and back would read as the page
    /// flickering through the log once a second.
    @MainActor
    func testAFullTailTakingALineLandsOnItWithoutLeavingTheEnd() throws {
        try landsOnEveryArrival(perDay: 1_000_000)
    }

    /// The same with a day heading every four lines, so the oldest line
    /// dropping moves a heading at the top and an arrival on a new day brings
    /// a heading of its own at the bottom — the lazy stack has to estimate
    /// rows of two heights on both ends.
    @MainActor
    func testAFullTailWithDayHeadingsTakingALineLandsOnIt() throws {
        try landsOnEveryArrival(perDay: 4)
    }

    @MainActor
    private func landsOnEveryArrival(perDay: Int) throws {
        let source = fullTail(perDay: perDay)
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "the full tail did not open on its newest line")
        let scroll = try XCTUnwrap(page.scroll)
        let window = scroll.documentVisibleRect.height
        for index in 1000..<1006 {
            arrive(source, index, perDay: perDay)
            var worst: CGFloat = 0
            let end = Date().addingTimeInterval(1.2)
            while Date() < end {
                page.mount.host.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
                let document = try XCTUnwrap(scroll.documentView)
                worst = max(worst, document.frame.height - scroll.documentVisibleRect.maxY)
            }
            let gap = try page.gap()
            XCTAssertLessThan(gap, 24, "line \(index) into a full tail: the page sits \(gap) pt "
                              + "above its newest line")
            XCTAssertLessThan(worst, window, "line \(index) into a full tail: on the way the page "
                              + "was \(worst) pt from its end, more than a window")
        }
    }

    /// The newest line wraps — to two lines of type, four, six and about ten. Follow
    /// promises the newest line, so the whole of its type is in view: the view
    /// may stop short of the list's own bottom padding, but not of the line.
    ///
    /// **What "the end" is now.** The rule scrolls to a zero-height mark below the
    /// last card, so a view that landed exactly stands the page's bottom padding
    /// (`HelmSpace.s5`) above the list's end, and that is the floor; a jump to
    /// the newest row instead stands the row's own padding, the card's and the
    /// page's above it (21 pt, measured). The page before the cards — a flat lazy
    /// list with the mark inside it — landed 31–52 pt short for a line of 25
    /// words (the tester's own reading on that page, 2026-09-30); why is not
    /// established, and this test holds the result and not the reason.
    @MainActor
    func testATallNewestLineIsShownToItsEnd() throws {
        for full in [false, true] {
            for words in [6, 15, 25, 40] {
                let source = full ? fullTail() : LogPageUnderHand.log()
                let page = LogPageUnderHand(source)
                defer { page.close() }
                page.pump(1.5)
                XCTAssertLessThan(try page.gap(), 24, "the page did not open on its newest line")
                let long = Array(repeating: "a long wrapped message", count: words)
                    .joined(separator: " ")
                arrive(source, 1000, message: long)
                page.pump(1.5)
                let first = try page.gap()
                page.pump(2.2)
                let later = try page.gap()
                print("tall newest line, full tail \(full), \(words) words: gap \(first) then \(later)")
                // The page's own bottom padding is all that may sit under the
                // mark; a point of slack for the rounding of a measured height.
                XCTAssertLessThanOrEqual(later, HelmSpace.s5 + 1, "full tail \(full), \(words) words: the newest line was "
                                  + "followed to \(first) pt short of the list's end, and \(later) pt "
                                  + "after a quiet read — its last lines of type are below the view")
            }
        }
    }

    // MARK: - A burst of lines is not a burst of scrolls

    /// A hundred lines a second into a full tail. The page reads its source on
    /// a one-second tick, so the rule can fire at most once a read; the clip
    /// view's origin is what a scroll moves, sampled on every turn of the run
    /// loop, and it may move a handful of times per read at most — not once
    /// per line.
    @MainActor
    func testABurstOfLinesScrollsOncePerReadAndNotOncePerLine() throws {
        let source = fullTail()
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.5)
        let scroll = try XCTUnwrap(page.scroll)
        var moves = 0
        var lastY = scroll.contentView.bounds.minY
        var next = 1000
        var lastFed = Date.distantPast
        let feedUntil = Date().addingTimeInterval(3.2)
        let end = feedUntil.addingTimeInterval(1.2)
        while Date() < end {
            if Date() < feedUntil, Date().timeIntervalSince(lastFed) >= 0.01 {
                arrive(source, next)
                next += 1
                lastFed = Date()
            }
            page.mount.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            let y = scroll.contentView.bounds.minY
            if abs(y - lastY) > 0.5 { moves += 1 }
            lastY = y
        }
        let lines = next - 1000
        XCTAssertGreaterThan(lines, 100, "the burst never happened (\(lines) lines)")
        print("burst: \(lines) lines, \(moves) scroll moves")
        // No floor on the moves: a view already at the end of a full tail
        // need not move at all — measured 0 with the rule scrolling to the
        // newest row, 2 with it scrolling to the end mark. What would be a
        // storm is a move per line, and the reads cap that at one per tick.
        // Five reads at most in 4.4 s; three moves per read is generous.
        XCTAssertLessThanOrEqual(moves, 15, "\(lines) lines produced \(moves) scroll moves")
        XCTAssertLessThan(try page.gap(), 24, "after the burst the page is not on its newest line")
    }

    // MARK: - The end mark is not a row

    /// The mark the rule scrolls to has no height and no ink: the space under
    /// the newest line's type, followed to the end, is the row's own padding,
    /// the card's and the page's, and no more.
    @MainActor
    func testTheEndMarkAddsNoSpaceUnderTheNewestLine() throws {
        // 401 lines: the newest is an info line, which carries no wash, so
        // the only ink at the bottom of the list is its type.
        let page = LogPageUnderHand(LogPageUnderHand.log(401))
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24)
        let scroll = try XCTUnwrap(page.scroll)
        let host = page.mount.host
        let frame = scroll.convert(scroll.bounds, to: host)
        // Host is flipped (SwiftUI): y grows downwards, like the reading.
        let top = Int(frame.minY.rounded(.up)) + 1, bottom = Int(frame.maxY.rounded(.down)) - 1
        let inks = try XCTUnwrap(RenderedLines.read(host, points: top...bottom, margin: 60),
                                 "no reading of the list")
        let lowest = try XCTUnwrap(inks.map(\.bottom).max(), "the list drew no type")
        let under = CGFloat(bottom) - lowest
        print("space under the newest line's ink: \(under) pt")
        // 3 pt row padding + the card's 6 + the page's 12 = 21, measured to the
        // half point, and 8 pt for a descender; a row more would be 18 pt or so
        // on top of that.
        let expected = 3 + HelmSpace.s3 + HelmSpace.s5
        XCTAssertLessThan(under, expected + 8, "\(under) pt under the newest line's type")
    }
}
