import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What opening the Log page costs, counted in the one unit that grows with the
/// log: the rows the page lays out.
///
/// A row is a view, and a view costs a layout whether or not anybody scrolls to
/// it. The page reports every row it lays out to the reader's place
/// (`LogReaderPlace.drawnRows`, one report per row, taken back when the row
/// leaves), so the count is read from the page's own record, not from a size and
/// not from a clock. A bound that says the page draws rows in proportion to the
/// log is red on a page that draws all of it; a bound on a size would be
/// satisfied by a page that drew nothing.
///
/// **The window is never ordered.** The page is mounted the way
/// `TheLogPageOpensOnTheNewestLineTests` mounts it (`MountedRender`) and pumped
/// by forced layout. That a row reports its place there at all is a claim about
/// SwiftUI in a window nobody sees, so the count of a page that must have drawn
/// rows is asserted non-zero before it is compared with anything.
///
/// **Five groups, each holding a different part of what the page does.**
/// - The counted row: what the page lays out at open, fourfold the log against
///   the log.
/// - `LogPresentation.drawn(rowsBefore:)` alone: which launches, never half of
///   one, and what a line entering the newest launch cannot move.
/// - `LogView.earlierAfterAsk` alone: what an ask writes. Launches of unequal
///   sizes, where a doubling of the figure adds no launch, so that the count of
///   doublings must step over it; nothing written once every launch is drawn;
///   never a smaller count than the one given.
/// - `LogReaderPlace`'s ask alone (`drawEarlier`): on which roads of the rest it
///   is made, on which not, and that one rest asks once. A row that asserts "not
///   asked" ends by making the same place ask, so that it shows the rest ran and
///   that the state, not a rest that never came, held the ask back; the two rows
///   that assert "asked once" end by letting the same rest pass again.
/// - The page mounted: a rest at the top grows the page and the line being read
///   stays where it was; an ask grows it while a launch is not drawn and changes
///   nothing once every launch is; and Follow lit with the view at the end, the
///   page grows and the view is still at the end.
///
/// The waits are pumps of the run loop; nothing is asserted on a time.
@MainActor
final class TheLogDrawsTheNewestLaunchesFirstTests: XCTestCase {

    /// Launches of `launches` times `rowsPerLaunch` rows (43 by default), every
    /// line distinct, as the owner's tail is laid out: the first launch has no
    /// start line, every other has its start line and its start-up burst.
    private static func tail(launches: Int, rowsPerLaunch: Int = 43) -> [LogEntry] {
        tail(sizes: Array(repeating: rowsPerLaunch, count: launches))
    }

    /// One launch per element of `sizes`, each of that many rows (the start line
    /// and the start-up burst of every launch but the first come on top): the
    /// fixture of the window families, with no landmark in it.
    private static func tail(sizes: [Int]) -> [LogEntry] {
        TheLogHoldsAReaderThroughWhatNobodyTriedTests.tail(rows: sizes, landmarkIn: -1, landmarkRow: -1)
    }

    /// A tail as the app keeps one: `HelmLog.tailLimit` lines, the head of it cut
    /// wherever the limit falls, built from launches of `size` rows each.
    private static func fullTail(launchesOf size: Int) -> [LogEntry] {
        let lines = Array(tail(launches: HelmLog.tailLimit / size + 2, rowsPerLaunch: size).suffix(HelmLog.tailLimit))
        precondition(lines.count == HelmLog.tailLimit, "the fixture is not a full tail")
        return lines
    }

    /// `count` more distinct lines after the last one of `lines`, in the launch
    /// that is the newest: no start line, so no new launch.
    private static func appending(_ count: Int, to lines: [LogEntry]) -> [LogEntry] {
        var at = lines.last?.date ?? Date(timeIntervalSince1970: 1_789_000_000)
        return lines + (0..<count).map { index in
            at.addTimeInterval(7)
            return LogEntry(date: at, level: .info, category: "vpn", message: "arrived later \(index)")
        }
    }

    private static func presentation(_ lines: [LogEntry]) -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "")
    }

    /// What a card weighs toward `rowsBefore`: its rows and its start-up rows.
    private static func weight(_ card: LogPresentation.Card) -> Int {
        card.rows.count + card.startup.count
    }

    private func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    /// The host laid out and the run loop turned, pass after pass, until the count
    /// of rows `place` reports has stood still for a run of passes and is not
    /// zero, or a bound of passes is spent. The wait is by the count, never
    /// asserted on.
    private static func layOutUntilTheRowsStandStill(_ host: NSView, _ place: LogReaderPlace) {
        var last = -1
        var still = 0
        var passes = 0
        while passes < 600, still < 40 || place.drawnRows == 0 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            let now = place.drawnRows
            still = now == last ? still + 1 : 0
            last = now
            passes += 1
        }
    }

    /// What one mount of the page read and drew once it had landed.
    private struct Opened {
        let lines: Int
        let reads: Int
        /// Rows the page reports as standing, `LogReaderPlace.drawnRows`.
        let drawnRows: Int
        /// Launches the presentation holds, and the rows of all of them.
        let cards: Int
        let rowsPresented: Int
        /// The rows of the launches the rule draws at open, from the
        /// presentation's own cut (`LogPresentation.drawn(rowsBefore:)`).
        let rowsExpected: Int
        let documentHeight: CGFloat
        let viewHeight: CGFloat
    }

    /// The page mounted over `lines`, pumped until it has read its source and
    /// the count of rows has stood still (`layOutUntilTheRowsStandStill`), and
    /// what it holds then.
    private func open(_ lines: [LogEntry]) throws -> Opened {
        let source = LogPageUnderHandSource()
        source.lines = lines
        let place = LogReaderPlace()
        let mount = MountedRender(LogView(source: { source.reads += 1; return source.lines },
                                          storedLog: { false }, readerPlace: place),
                                  width: 810, height: 700, appearance: .aqua)
        defer { mount.drop() }
        Self.layOutUntilTheRowsStandStill(mount.host, place)
        let scroll = try XCTUnwrap(mount.host.everyView(ofType: NSScrollView.self).first,
                                   "the page drew no scroll view over \(lines.count) lines")
        let document = try XCTUnwrap(scroll.documentView, "the scroll view holds nothing")
        let presented = Self.presentation(lines)
        return Opened(lines: lines.count, reads: source.reads, drawnRows: place.drawnRows,
                      cards: presented.cards.count,
                      rowsPresented: presented.cards.reduce(0) { $0 + $1.rows.count },
                      rowsExpected: presented.drawn(rowsBefore: LogView.drawnAtOpen)
                          .reduce(0) { $0 + $1.rows.count },
                      documentHeight: document.frame.height,
                      viewHeight: scroll.documentVisibleRect.height)
    }

    // MARK: - The counted row

    /// Four times the log, four times the rows laid out: red on a page that draws
    /// every launch of the tail, green on one that draws a bounded part of it.
    func testFourTimesTheLogDoesNotLayOutFourTimesTheRows() throws {
        let small = try open(Self.tail(launches: 5))
        let large = try open(Self.tail(launches: 20))
        let printed = "\(small.lines) lines: \(small.drawnRows) rows drawn; "
            + "\(large.lines) lines: \(large.drawnRows) rows drawn"
        // The line a person reads in the log of the run; the failure message below
        // carries it again.
        print("LOG-DRAWN-ROWS \(printed) (presented \(small.rowsPresented) and \(large.rowsPresented) rows in \(small.cards) and \(large.cards) launches; documents \(Int(small.documentHeight)) and \(Int(large.documentHeight)) pt tall)")

        // The subject first. The fixtures are what they say: five launches, then
        // twenty, the larger one inside the tail the app keeps.
        XCTAssertEqual(small.lines, 243, "the small fixture is not 243 lines: \(printed)")
        XCTAssertEqual(large.lines, 993, "the large fixture is not 993 lines: \(printed)")
        XCTAssertLessThan(large.lines, HelmLog.tailLimit, "the large fixture is longer than a tail: \(printed)")
        XCTAssertEqual(small.cards, 5, "the presentation did not split five launches: \(printed)")
        XCTAssertEqual(large.cards, 20, "the presentation did not split twenty launches: \(printed)")
        XCTAssertGreaterThan(small.rowsPresented, 0, "a parser that read nothing proves nothing: \(printed)")
        XCTAssertEqual(large.rowsPresented, 4 * small.rowsPresented,
                       "the larger fixture is not fourfold the smaller in rows: \(printed)")
        // The source was read, by both pages.
        XCTAssertGreaterThanOrEqual(small.reads, 1, "the small page never read its source: \(printed)")
        XCTAssertGreaterThanOrEqual(large.reads, 1, "the large page never read its source: \(printed)")
        // The document is taller than the view, so there is more of it than is seen.
        XCTAssertGreaterThan(small.documentHeight, small.viewHeight * 3,
                             "the small page did not outgrow its view: \(printed)")
        XCTAssertGreaterThan(large.documentHeight, large.viewHeight * 3,
                             "the large page did not outgrow its view: \(printed)")
        // Rows were counted at all: a page that built nothing, or a window in which
        // no row reports its place, reads 0 here and is red, never green. And the
        // page draws the rows its rule gives at open — the newest launch and the
        // nearest older ones, whole — so at N and at 4N the count is the one the
        // presentation's own cut gives, and at 4N it is a part of what is
        // presented, not all of it. (The cut's arithmetic is pinned by literals in
        // `testTheCutOfTheFixtureIsFourLaunchesAtOpen`; here it is read from the cut.)
        XCTAssertGreaterThan(small.drawnRows, 0, "no row reported its place at 243 lines: \(printed)")
        XCTAssertGreaterThan(large.drawnRows, 0, "no row reported its place at 993 lines: \(printed)")
        XCTAssertGreaterThan(small.rowsExpected, 0, "the rule draws no row at 243 lines: \(printed)")
        XCTAssertEqual(small.drawnRows, small.rowsExpected,
                       "at 243 lines the page does not stand the rows the rule gives: \(printed)")
        XCTAssertEqual(large.drawnRows, large.rowsExpected,
                       "at 993 lines the page does not stand the rows the rule gives: \(printed)")
        XCTAssertLessThan(large.drawnRows, large.rowsPresented,
                          "at 993 lines the page stands every presented row: \(printed)")

        // The bound: fourfold the log is not fourfold the work.
        XCTAssertLessThan(large.drawnRows, 2 * small.drawnRows, """
            opening the Log page lays out rows in proportion to the log — \(printed) — \
            so the cost of the page grows with the lines it holds
            """)
    }

    // MARK: - The cut: LogPresentation.drawn(rowsBefore:)

    /// The fixture's arithmetic by literals, not by the rule: five launches of 43
    /// rows weigh 43, 49, 49, 49, 49 (the start line is a header, the six
    /// start-up lines count), so a hundred rows before the newest launch take
    /// three older launches (49, 98, 147) and the newest — four launches, at five
    /// and at twenty. The edges of `>=` are here: 49 is one older launch, 50 two.
    func testTheCutOfTheFixtureIsFourLaunchesAtOpen() {
        let five = Self.presentation(Self.tail(launches: 5))
        let twenty = Self.presentation(Self.tail(launches: 20))
        XCTAssertEqual(five.cards.map(Self.weight), [43, 49, 49, 49, 49], "the fixture is not the one the literals are for")
        XCTAssertEqual(twenty.cards.count, 20)
        XCTAssertEqual(LogView.drawnAtOpen, 100, "the figure the literals below are worked for")
        XCTAssertEqual(five.drawn(rowsBefore: LogView.drawnAtOpen).count, 4)
        XCTAssertEqual(twenty.drawn(rowsBefore: LogView.drawnAtOpen).count, 4)
        XCTAssertEqual(five.drawn(rowsBefore: LogView.drawnAtOpen).map(\.id), Array(five.cards.suffix(4)).map(\.id),
                       "the launches drawn are not the newest four")
        XCTAssertEqual(twenty.drawn(rowsBefore: 49).count, 2, "49 rows before the newest are one older launch")
        XCTAssertEqual(twenty.drawn(rowsBefore: 50).count, 3, "50 rows before the newest are two older launches")
        XCTAssertEqual(twenty.drawn(rowsBefore: 98).count, 3)
        XCTAssertEqual(twenty.drawn(rowsBefore: 99).count, 4)
    }

    /// Launches of unequal sizes, so that a cut which weighs a card wrongly or
    /// keeps a different number of them than it should lands somewhere else. For
    /// every `rowsBefore` from below zero to past the whole tail: what is drawn
    /// is the newest launches, each whole and the same card, and it is the
    /// fewest that hold `rowsBefore` rows before the newest — one card fewer
    /// would hold less, and every card when the older ones hold fewer.
    func testTheCutIsTheFewestWholeNewestLaunchesThatHoldTheRows() {
        let page = Self.presentation(Self.tail(sizes: [5, 120, 40, 7, 300, 33, 90]))
        let cards = page.cards
        XCTAssertEqual(cards.count, 7, "the fixture is not seven launches")
        let older = cards.dropLast().reduce(0) { $0 + Self.weight($1) }
        XCTAssertGreaterThan(older, 500, "the fixture is too small for a cut to matter")
        var distinct = Set<Int>()
        for rowsBefore in -3...(older + 3) {
            let drawn = page.drawn(rowsBefore: rowsBefore)
            distinct.insert(drawn.count)
            let say = "at rowsBefore \(rowsBefore) the cut drew \(drawn.count) of \(cards.count) launches"
            XCTAssertGreaterThanOrEqual(drawn.count, 1, say)
            // The newest launches, each the very card (whole: its rows and its fold unchanged).
            XCTAssertEqual(drawn.map(\.id), cards.suffix(drawn.count).map(\.id), say)
            for (cut, whole) in zip(drawn, cards.suffix(drawn.count)) {
                XCTAssertEqual(cut.rows.count, whole.rows.count, say)
                XCTAssertEqual(cut.startup.count, whole.startup.count, say)
            }
            let before = drawn.dropLast().reduce(0) { $0 + Self.weight($1) }
            if drawn.count < cards.count {
                XCTAssertGreaterThanOrEqual(before, rowsBefore, "\(say): the older ones hold only \(before)")
            }
            if drawn.count > 1, let oldest = drawn.first {
                XCTAssertLessThan(before - Self.weight(oldest), rowsBefore,
                                  "\(say): the oldest launch drawn was not needed")
            }
        }
        // The loop reached every size of cut, not only the ends.
        XCTAssertEqual(distinct, Set(1...cards.count), "the fixture's cuts: \(distinct.sorted())")
    }

    /// Asked for no rows the page draws the newest launch alone; asked for more
    /// than the older launches hold, every launch.
    func testNoRowsAskedIsTheNewestAloneAndMoreThanThereIsIsEveryLaunch() {
        let page = Self.presentation(Self.tail(launches: 5))
        let last = page.cards.last?.id
        XCTAssertNotNil(last)
        for none in [0, -1, -1_000, Int.min] {
            XCTAssertEqual(page.drawn(rowsBefore: none).map(\.id), [last].compactMap { $0 },
                           "rowsBefore \(none) did not draw the newest launch alone")
        }
        let older = page.cards.dropLast().reduce(0) { $0 + Self.weight($1) }
        XCTAssertEqual(older, 43 + 3 * 49, "the fixture's older launches")
        for more in [older, older + 1, 10_000, Int.max] {
            XCTAssertEqual(page.drawn(rowsBefore: more).map(\.id), page.cards.map(\.id),
                           "rowsBefore \(more) did not draw every launch")
        }
    }

    /// No launch, one launch: nothing to draw, and the one there is whatever is
    /// asked.
    func testNoLaunchDrawsNothingAndOneLaunchDrawsItselfWhateverIsAsked() {
        let empty = Self.presentation([])
        XCTAssertEqual(empty.cards.count, 0, "precondition: no lines, no launch")
        let one = Self.presentation(Self.tail(launches: 1))
        XCTAssertEqual(one.cards.count, 1, "precondition: one launch")
        for asked in [Int.min, -1, 0, 1, 100, 1_000_000, Int.max] {
            XCTAssertEqual(empty.drawn(rowsBefore: asked).count, 0, "rowsBefore \(asked) over no launch drew one")
            XCTAssertEqual(one.drawn(rowsBefore: asked).map(\.id), one.cards.map(\.id),
                           "rowsBefore \(asked) over one launch did not draw it")
        }
    }

    /// **Lines arriving in the newest launch cannot move the cut.** Sixty lines
    /// appended to the newest launch: it grows, and for every `rowsBefore` the
    /// oldest launch drawn is the same one and as many launches are drawn. A cut
    /// that counted the newest launch toward `rowsBefore` would take a launch
    /// away from under a reader standing in it.
    func testLinesAppendedToTheNewestLaunchLeaveTheOldestDrawnLaunchTheSame() {
        let base = Self.tail(sizes: [5, 120, 40, 7, 300, 33, 90])
        let before = Self.presentation(base)
        let after = Self.presentation(Self.appending(60, to: base))
        XCTAssertEqual(after.cards.count, before.cards.count, "precondition: the lines made a new launch")
        XCTAssertEqual(after.cards.last.map { $0.rows.count }, before.cards.last.map { $0.rows.count + 60 },
                       "precondition: the sixty lines are sixty rows of the newest launch")
        let older = before.cards.dropLast().reduce(0) { $0 + Self.weight($1) }
        var moved = 0
        for rowsBefore in 0...(older + 3) {
            let was = before.drawn(rowsBefore: rowsBefore)
            let now = after.drawn(rowsBefore: rowsBefore)
            if was.first?.id != now.first?.id || was.count != now.count { moved += 1 }
        }
        XCTAssertEqual(moved, 0, "arriving lines moved the oldest launch drawn at \(moved) of \(older + 4) sizes of cut")
    }

    /// The ceiling is the first doubling of `drawnAtOpen` that reaches the whole
    /// tail: the figure one doubling lower stays under it. No line under
    /// `Sources` reads the constant; this row pins the figure it is computed to
    /// be, and the rows that count asks take their bound from it.
    func testTheCeilingIsTheFirstDoublingThatCoversTheTail() {
        let ceiling = LogView.earlierCeiling
        XCTAssertGreaterThan(ceiling, 0)
        XCTAssertGreaterThanOrEqual(LogView.drawnAtOpen << ceiling, HelmLog.tailLimit,
                                    "the ceiling does not reach the whole tail")
        XCTAssertLessThan(LogView.drawnAtOpen << (ceiling - 1), HelmLog.tailLimit,
                          "the ceiling is a doubling too many")
    }

    // MARK: - What an ask writes: LogView.earlierAfterAsk

    /// How many launches `page` draws at each of the counts `0...last`.
    private func drawnCounts(_ page: LogPresentation, upTo last: Int) -> [Int] {
        (0...last).map { page.drawn(rowsBefore: LogView.drawnAtOpen << $0).count }
    }

    /// What `LogView.earlierAfterAsk` did with one page and one count.
    private enum Asked: Equatable {
        case wrote(Int)
        case wroteNothing
        /// The call had not returned when the wait for it ended. An ask whose
        /// guard is gone loops for ever on a page that draws one launch whatever
        /// the count, and a row that waited for it would end in no result at all.
        case neverReturned
    }

    private final class Reply: @unchecked Sendable {
        var value: Int??
    }

    /// The ask called on a thread of its own and waited for, so that a call that
    /// does not return is a result and not a stuck run. The wait is for a call
    /// that has hung; a call that returns is read at once, and nothing is
    /// asserted on how long it took.
    private func asked(_ earlier: Int, in page: LogPresentation) -> Asked {
        let reply = Reply()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            reply.value = .some(LogView.earlierAfterAsk(earlier, in: page))
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success, let value = reply.value else { return .neverReturned }
        return value.map { .wrote($0) } ?? .wroteNothing
    }

    /// The counts an ask writes, one answered from the one before, from 0 until
    /// it writes nothing. A walk that does not end, or reaches a count past
    /// `lastCountThatFits`, fails the row.
    private func walk(_ page: LogPresentation, _ say: String) -> [Int] {
        var written: [Int] = []
        var earlier = 0
        while case .wrote(let next) = asked(earlier, in: page) {
            written.append(next)
            earlier = next
            if next > Self.lastCountThatFits {
                XCTFail("\(say): the asks do not come to an end: \(written)")
                break
            }
        }
        return written
    }

    /// The last count of the unbroken run from 0 at which `drawnAtOpen << count`
    /// is a positive `Int` (by the shift's semantics, not a run: it is positive
    /// again at 59 and 60, so the run is not the only counts that are).
    private static let lastCountThatFits = 56

    /// **An ask steps over a doubling that adds no launch.** Launches of unequal
    /// sizes, where the figure doubled once draws the launches it drew before:
    /// three launches that draw 2, 2 and 3 launches at 100, 200 and 400 rows
    /// (three sizes), seven that draw 3, 3, 5 and 7, and the fixtures where every
    /// doubling adds. The counts an ask writes are literals, so that an ask which
    /// writes `earlier + 1` — a page that draws what it drew, so that nothing
    /// moves, nothing rests and nothing asks again — is red here, and the
    /// launches drawn grow at every ask until all are drawn.
    func testAnAskStepsOverADoublingThatAddsNothingAndEveryAskDrawsALaunchMore() {
        let fixtures: [(name: String, sizes: [Int], drawn: [Int], writes: [Int])] = [
            ("[300, 288, 398]", [300, 288, 398], [2, 2, 3], [2]),
            ("[402, 284, 300]", [402, 284, 300], [2, 2, 3], [2]),
            ("[600, 286, 100]", [600, 286, 100], [2, 2, 3], [2]),
            ("[5, 120, 40, 7, 300, 33, 90]", [5, 120, 40, 7, 300, 33, 90], [3, 3, 5, 7], [2, 3]),
            ("five launches of 43", Array(repeating: 43, count: 5), [4, 5], [1]),
            ("twenty launches of 43", Array(repeating: 43, count: 20), [4, 6, 10, 18, 20], [1, 2, 3, 4]),
        ]
        var stepped = 0
        for fixture in fixtures {
            let page = Self.presentation(Self.tail(sizes: fixture.sizes))
            XCTAssertEqual(page.cards.count, fixture.sizes.count, "\(fixture.name): the presentation did not split the launches")
            // The subject first: the launches each figure draws are the ones the literals are for.
            XCTAssertEqual(Array(drawnCounts(page, upTo: 6).prefix(fixture.drawn.count)), fixture.drawn,
                           "\(fixture.name): the fixture is not the one the literals are for")
            let written = walk(page, fixture.name)
            XCTAssertEqual(written, fixture.writes, "\(fixture.name): the counts the asks wrote")
            var earlier = 0
            for next in written {
                let before = page.drawn(rowsBefore: LogView.drawnAtOpen << earlier).count
                let after = page.drawn(rowsBefore: LogView.drawnAtOpen << next).count
                XCTAssertGreaterThan(after, before, "\(fixture.name): an ask from \(earlier) wrote \(next), which draws nothing more")
                for between in (earlier + 1)..<max(next, earlier + 1) {
                    XCTAssertEqual(page.drawn(rowsBefore: LogView.drawnAtOpen << between).count, before,
                                   "\(fixture.name): an ask from \(earlier) stepped over \(between), which draws a launch more")
                    stepped += 1
                }
                earlier = next
            }
            XCTAssertEqual(page.drawn(rowsBefore: LogView.drawnAtOpen << earlier).count, page.cards.count,
                           "\(fixture.name): the last count written does not draw every launch")
        }
        XCTAssertGreaterThan(stepped, 0, "no fixture had a doubling to step over, so the stepping was not asked")
    }

    /// **Nothing is written once every launch is drawn, from any count**, and
    /// whatever is written is a count above the one given that draws a launch
    /// more than it did. Every count from 0 to 56 (the last at which `drawnAtOpen`
    /// shifted is still a positive `Int`) over launches of unequal sizes, five
    /// launches and twenty, and a count past `earlierCeiling`.
    func testNothingIsWrittenOnceEveryLaunchIsDrawnFromAnyCountAndNothingIsLowered() {
        let pages: [(String, LogPresentation)] = [
            ("[300, 288, 398]", Self.presentation(Self.tail(sizes: [300, 288, 398]))),
            ("[5, 120, 40, 7, 300, 33, 90]", Self.presentation(Self.tail(sizes: [5, 120, 40, 7, 300, 33, 90]))),
            ("five launches", Self.presentation(Self.tail(launches: 5))),
            ("twenty launches", Self.presentation(Self.tail(launches: 20))),
        ]
        var silences = 0
        var writes = 0
        for (name, page) in pages {
            for earlier in 0...Self.lastCountThatFits {
                let drawn = page.drawn(rowsBefore: LogView.drawnAtOpen << earlier).count
                let answer = asked(earlier, in: page)
                if drawn == page.cards.count {
                    XCTAssertEqual(answer, .wroteNothing, "\(name): every launch is drawn at \(earlier) and an ask answered \(answer)")
                    silences += 1
                } else if case .wrote(let next) = answer {
                    XCTAssertGreaterThan(next, earlier, "\(name): an ask from \(earlier) wrote \(next), a count no higher")
                    XCTAssertGreaterThan(page.drawn(rowsBefore: LogView.drawnAtOpen << next).count, drawn,
                                         "\(name): an ask from \(earlier) wrote \(next), which draws no launch more")
                    writes += 1
                } else {
                    XCTFail("\(name): \(drawn) of \(page.cards.count) launches are drawn at \(earlier) and the ask answered \(answer)")
                }
            }
        }
        XCTAssertGreaterThan(writes, 0, "no ask wrote anything, so the writes were not asked")
        XCTAssertGreaterThan(silences, 0, "every launch was drawn at no count, so the silence was not asked")
        XCTAssertEqual(asked(LogView.earlierCeiling + 3, in: Self.presentation(Self.tail(launches: 20))), .wroteNothing,
                       "a count past the ceiling wrote a count")
    }

    /// No launch and one launch have nothing to add, whatever count they are
    /// given. An ask without its guard loops for ever on such a page (every count
    /// draws the launch there is, or none), which `asked(_:in:)` reports as a
    /// call that never returned.
    func testNoLaunchAndOneLaunchWriteNothingFromAnyCount() {
        let none = Self.presentation([])
        let one = Self.presentation(Self.tail(launches: 1))
        XCTAssertEqual(none.cards.count, 0, "precondition: no lines, no launch")
        XCTAssertEqual(one.cards.count, 1, "precondition: one launch")
        for (name, page) in [("no launch", none), ("one launch", one)] {
            for earlier in [0, 1, LogView.earlierCeiling, LogView.earlierCeiling + 1, Self.lastCountThatFits] {
                let answer = asked(earlier, in: page)
                XCTAssertEqual(answer, .wroteNothing, "\(name), count \(earlier): the ask answered \(answer)")
                if answer == .neverReturned { break }
            }
        }
    }

    /// **A tail at its cap is reached in at most `earlierCeiling` asks that write
    /// anything.** Full tails (`HelmLog.tailLimit` lines) of launches from one row
    /// to three hundred: the asks walk to a count that draws every launch, and the
    /// asks that write are no more than the ceiling counts.
    func testAFullTailIsReachedInNoMoreWritingAsksThanTheCeilingCounts() {
        var most = 0
        for size in [1, 5, 43, 100, 130, 300] {
            let page = Self.presentation(Self.fullTail(launchesOf: size))
            XCTAssertGreaterThan(page.cards.count, 1, "launches of \(size): the full tail is one launch")
            let written = walk(page, "launches of \(size)")
            XCTAssertGreaterThan(written.count, 0, "launches of \(size): the page opened with every launch drawn")
            XCTAssertLessThanOrEqual(written.count, LogView.earlierCeiling,
                                     "launches of \(size) (\(page.cards.count)): \(written.count) asks wrote, the ceiling counts \(LogView.earlierCeiling): \(written)")
            XCTAssertEqual(page.drawn(rowsBefore: LogView.drawnAtOpen << (written.last ?? 0)).count, page.cards.count,
                           "launches of \(size): the asks did not reach every launch: \(written)")
            most = max(most, written.count)
        }
        print("LOG-ASKS most asks that wrote, over full tails of six launch sizes: \(most) (ceiling \(LogView.earlierCeiling))")
    }

    // MARK: - The ask: LogReaderPlace.drawEarlier

    /// A place with a page's three closures replaced by counters: how many times
    /// the end was asked for, a line was scrolled to, and earlier launches asked.
    @MainActor private final class Reader {
        let place = LogReaderPlace()
        var follows: Bool
        var asked = 0
        var toEnd = 0
        var toLine = 0

        init(following: Bool) {
            follows = following
            place.following = { [unowned self] in self.follows }
            place.scrollToEnd = { [unowned self] in self.toEnd += 1 }
            place.scrollToLine = { [unowned self] _, _ in self.toLine += 1 }
            place.drawEarlier = { [unowned self] in self.asked += 1 }
        }

        /// A drawn row, as the page reports it, `y` from the top of the content.
        func row(at y: CGFloat) {
            let line = LogEntry(date: Date(), level: .info, category: "vpn", message: "row \(UUID())")
            place.rowMoved(line.id, frame: CGRect(x: 0, y: y, width: 600, height: 20))
        }
    }

    private func metrics(_ top: CGFloat, _ visible: CGFloat, _ content: CGFloat) -> LogReaderPlace.Metrics {
        .init(top: top, visibleHeight: visible, contentHeight: content)
    }

    /// The view reports `now` and the layout is left to come to rest: the pump
    /// is several times the place's quiet period (`LogReaderPlace.quiet`).
    private func rest(_ reader: Reader, _ now: LogReaderPlace.Metrics) {
        reader.place.scrolled(now)
        pump(0.3)
    }

    /// Follow lit, the end being sought and found, within a view of the top: the
    /// ask is made, once — and the same rest does not make it again.
    func testTheEndFoundWithinAViewOfTheTopAsksOnceAndTheSameRestDoesNotAskTwice() {
        let reader = Reader(following: true)
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 1, "the end found at rest within a view of the top did not ask")
        XCTAssertEqual(reader.toEnd, 0, "precondition: the end was not sought again")
        pump(0.3)
        XCTAssertEqual(reader.asked, 1, "one rest asked twice")
    }

    /// Far from the top of what is drawn nothing is asked, and the edge is the
    /// view's own height: a top equal to it asks, one past it does not, a top
    /// above the content (an overscroll) asks. The row ends asking, so that the
    /// silence before is the state's.
    func testFarFromTheTopNothingIsAskedAndTheEdgeIsAViewsHeight() {
        let reader = Reader(following: true)
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 1, "precondition: the first rest asked")
        rest(reader, metrics(5_000, 700, 5_700))
        XCTAssertEqual(reader.asked, 1, "at the end of 5 700 pt, 5 000 pt from the top, the page asked")
        rest(reader, metrics(701, 700, 1_401))
        XCTAssertEqual(reader.asked, 1, "a top one point past the view's height asked")
        rest(reader, metrics(700, 700, 1_400))
        XCTAssertEqual(reader.asked, 2, "a top equal to the view's height did not ask")
        rest(reader, metrics(-30, 700, 670))
        XCTAssertEqual(reader.asked, 3, "a view above the content's top did not ask")
        XCTAssertEqual(reader.toEnd, 0, "precondition: the end was never sought again")
    }

    /// Follow lit at the end and nobody seeking — the road that ends in
    /// `anchor = nil; return` — asks through the end alone, the line remembered
    /// by the rest before it being gone.
    func testFollowLitAtTheEndAsksOnEveryRestEvenWithNoLineHeld() {
        let reader = Reader(following: true)
        reader.row(at: 20)
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 1, "precondition: the end found asked")
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 2, "Follow lit, at the end, at rest did not ask")
        XCTAssertEqual(reader.toEnd, 0, "precondition: the end was not sought")
    }

    /// The end sought and not reached is not asked while the attempts last —
    /// every rest asks for the end instead — and when they are spent and the
    /// place gives up, it asks, once.
    func testWhileTheEndIsAskedForNothingIsAskedAndTheAttemptsSpentAsksOnce() {
        let reader = Reader(following: true)
        reader.place.scrolled(metrics(0, 700, 5_000))
        reader.row(at: 20)
        pump(0.3)
        for attempt in 1...LogReaderPlace.attempts {
            if attempt > 1 { rest(reader, metrics(0, 700, 5_000)) }
            XCTAssertEqual(reader.toEnd, attempt, "rest \(attempt) did not ask for the end")
            XCTAssertEqual(reader.asked, 0, "rest \(attempt) asked for earlier launches while the end is sought")
        }
        rest(reader, metrics(0, 700, 5_000))
        XCTAssertEqual(reader.toEnd, LogReaderPlace.attempts, "precondition: the attempts were spent, no further ask for the end")
        XCTAssertEqual(reader.asked, 1, "the place gave up on the end and did not ask")
        pump(0.3)
        XCTAssertEqual(reader.asked, 1, "one rest asked twice")
    }

    /// Content grown under a view that did not move seeks the end again and asks
    /// nothing — though a line is remembered, from the rest before, and the view
    /// is within a view of the top: only the end being sought holds the ask back.
    func testContentGrowingUnderAnUnmovedViewSeeksTheEndAndAsksNothing() {
        let reader = Reader(following: true)
        reader.row(at: 20)
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 1, "precondition: the end found asked, with the line remembered")
        rest(reader, metrics(0, 700, 3_000))
        XCTAssertEqual(reader.toEnd, 1, "precondition: the grown content sought the end again")
        XCTAssertEqual(reader.asked, 1, "a rest that asks for the end again asked for earlier launches")
        rest(reader, metrics(0, 700, 3_000))
        XCTAssertEqual(reader.toEnd, 2, "precondition: the second rest sought the end again")
        XCTAssertEqual(reader.asked, 1, "the end being sought, the place asked")
        rest(reader, metrics(0, 700, 700))
        XCTAssertEqual(reader.asked, 2, "the end reached again did not ask")
    }

    /// A person scrolls away from the end with Follow lit: the line at the top
    /// is remembered and the ask is made through it. With no line to remember
    /// the same scroll asks nothing — until one is drawn.
    func testAPersonScrollingAwayFromTheEndIsAskedThroughTheLineRememberedAndNotWithoutOne() {
        let held = Reader(following: true)
        held.row(at: 320)
        rest(held, metrics(300, 700, 1_000))
        XCTAssertEqual(held.asked, 1, "precondition: at the end the page asked")
        rest(held, metrics(0, 700, 1_000))
        XCTAssertEqual(held.asked, 2, "a person scrolled away from the end with a line to hold and the page did not ask")

        let bare = Reader(following: true)
        rest(bare, metrics(300, 700, 1_000))
        XCTAssertEqual(bare.asked, 1, "precondition: at the end the page asked")
        rest(bare, metrics(0, 700, 1_000))
        XCTAssertEqual(bare.asked, 1, "no line remembered and not at the end, and the page asked")
        bare.row(at: 320)
        pump(0.3)
        XCTAssertEqual(bare.asked, 2, "precondition: the same place asks once a line is drawn")
    }

    /// Follow off is asked through the line remembered alone: at the end or away
    /// from it, the end is nothing to a place that does not follow.
    func testFollowOffIsAskedThroughTheLineRememberedAndNotAtTheEndAlone() {
        let held = Reader(following: false)
        held.row(at: 20)
        rest(held, metrics(0, 700, 5_000))
        XCTAssertEqual(held.asked, 1, "Follow off with a line remembered did not ask")
        XCTAssertEqual(held.toEnd, 0, "precondition: Follow off never seeks the end")

        let bare = Reader(following: false)
        rest(bare, metrics(0, 700, 700))
        XCTAssertEqual(bare.asked, 0, "Follow off at the end with no line remembered asked")
        bare.row(at: 20)
        pump(0.3)
        XCTAssertEqual(bare.asked, 1, "precondition: the same place asks once a line is drawn")
    }

    /// A view, content or height that is not a number, and a content that is
    /// nothing, ask nothing: every comparison with it is false. Each place then
    /// is given a reading it can ask on, and asks.
    func testAReadingThatIsNotANumberAsksNothing() {
        let finite = metrics(0, 700, 1_000)
        let unreadable: [(String, LogReaderPlace.Metrics)] = [
            ("a top", metrics(.nan, 700, 1_000)),
            ("a visible height", metrics(0, .nan, 1_000)),
            ("a content height", metrics(0, 700, .nan)),
            ("a content of nothing", metrics(0, 700, 0)),
        ]
        for (name, reading) in unreadable {
            let reader = Reader(following: false)
            reader.row(at: 20)
            rest(reader, reading)
            XCTAssertEqual(reader.asked, 0, "\(name) that is not a number asked")
            rest(reader, finite)
            XCTAssertEqual(reader.asked, 1, "precondition: the same place asks on \(name) it can read")
        }
    }

    // MARK: - The page mounted

    /// The page mounted over `lines` with a place of the test's own and a toolbar
    /// channel, so that its controls are in reach and its re-declarations are
    /// counted — a write of the page's state re-runs its body, which declares.
    /// `LogPageUnderHand` mounts the page with no place handed in, so it cannot
    /// say how many rows stand; this mounts it with one, and presses Follow as
    /// `LogPageUnderHand.pressFollow` does.
    @MainActor private final class Page {
        let place = LogReaderPlace()
        let channel = HelmWindowToolbarChannel()
        let mount: MountedRender
        var declares = 0

        init(_ lines: [LogEntry], height: CGFloat = 700) {
            let place = place
            mount = MountedRender(LogView(source: { lines }, storedLog: { false }, readerPlace: place),
                                  width: 810, height: height, appearance: .aqua, channel: channel)
            channel.onChange = { [weak self] in self?.declares += 1 }
        }

        var scroll: NSScrollView? { mount.host.everyView(ofType: NSScrollView.self).first }

        /// Pumped for a fixed time that is longer than the place's quiet period
        /// (`LogReaderPlace.quiet`), so that a rest has fired, and then until the
        /// count of drawn rows has stood still (`layOutUntilTheRowsStandStill`).
        func settle() {
            let end = Date().addingTimeInterval(0.6)
            while Date() < end {
                mount.host.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            TheLogDrawsTheNewestLaunchesFirstTests.layOutUntilTheRowsStandStill(mount.host, place)
        }

        /// Follow is a toggle in the toolbar's capsule: pressing it is calling the
        /// action the page declared.
        func pressFollow() throws {
            let content = try XCTUnwrap(channel.content(for: "log"), "the page declared no toolbar")
            let action = try XCTUnwrap(content.actions.first { $0.id == "follow" }, "the toolbar has no follow action")
            guard case .toggle(_, let perform) = action.kind else { return XCTFail("Follow is not a toggle") }
            perform()
            settle()
        }

        func scrollToTop() throws {
            let scroll = try XCTUnwrap(scroll, "the page drew no scroll view")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
        }

        /// How far the bottom of the view is above the bottom of the document.
        func gap() throws -> CGFloat {
            let scroll = try XCTUnwrap(scroll, "the page drew no scroll view")
            let document = try XCTUnwrap(scroll.documentView, "the scroll view holds nothing")
            return document.frame.height - scroll.documentVisibleRect.maxY
        }

        func close() { mount.drop() }
    }

    /// **A rest at the top of what is drawn grows the page, and the line being
    /// read stays where it was.** Twenty launches, Follow off, the view brought
    /// to the top: the place's quiet period passes, it asks, the page draws
    /// earlier launches above, and the view moves down by what the document
    /// grew, so the row at the top of the view is under the same part of it.
    /// This is the road the pure rows only name: a bare scroll reaching the ask.
    func testAScrollToTheTopGrowsThePageAndTheLineAtTheTopStaysWhereItWas() throws {
        let page = Page(Self.tail(launches: 20))
        defer { page.close() }
        page.settle()
        let opened = page.place.drawnRows
        let presented = Self.presentation(Self.tail(launches: 20))
        let atOpen = presented.drawn(rowsBefore: LogView.drawnAtOpen).reduce(0) { $0 + $1.rows.count }
        XCTAssertGreaterThan(opened, 0, "no row reported its place")
        XCTAssertEqual(opened, atOpen, "precondition: the page opened on the rows the rule gives")

        try page.pressFollow()
        let scroll = try XCTUnwrap(page.scroll)
        let document = try XCTUnwrap(scroll.documentView)
        let heightBefore = document.frame.height
        XCTAssertGreaterThan(heightBefore, scroll.documentVisibleRect.height * 3,
                             "the page did not outgrow its view, so a position proves nothing")
        let declaresBefore = page.declares
        try page.scrollToTop()
        // `scrollToTop` has waited for the rest, so the page has already grown and the
        // hold has already moved the view: what is read here is the state after the
        // growth. Before it were read four things: the rows drawn at open, the document's
        // height, the height of the view's visible rect (in the precondition) and the
        // declarations.
        let grown = page.place.drawnRows
        let heightAfter = document.frame.height
        let top = scroll.documentVisibleRect.minY
        let growth = heightAfter - heightBefore
        print("LOG-GROWTH rows \(opened) -> \(grown); document \(Int(heightBefore)) -> \(Int(heightAfter)) pt (+\(Int(growth))); view top after \(top); declares +\(page.declares - declaresBefore)")
        XCTAssertGreaterThan(grown, opened, "a scroll to the top did not draw earlier launches")
        XCTAssertGreaterThan(growth, 0, "the document did not grow")
        XCTAssertGreaterThan(page.declares, declaresBefore, "the page's body did not run again")
        // The held line is where the growth left it: the view's top is the document's growth below
        // the top it was at (0), within the 2 pt the neighbouring families allow.
        XCTAssertEqual(top, growth, accuracy: 2,
                       "the view's top is \(top) pt after the document grew by \(growth) — the line being read moved")
    }

    /// **Asked more times than the ceiling, the page draws every launch and no
    /// more, and the count stops.** The closure the page gave the place is called
    /// as the place calls it: each ask up to the ceiling draws more launches and
    /// re-runs the page's body; after the ceiling the whole tail stands, and
    /// further asks change nothing — not the rows, and not the page's state,
    /// which would show as one more declaration of the toolbar.
    func testAskedPastTheCeilingThePageDrawsEveryLaunchAndTheCountStops() throws {
        let lines = Self.tail(launches: 20)
        let presented = Self.presentation(lines)
        let everyRow = presented.cards.reduce(0) { $0 + $1.rows.count }
        let page = Page(lines)
        defer { page.close() }
        page.settle()
        var rows = [page.place.drawnRows]
        XCTAssertGreaterThan(rows[0], 0, "no row reported its place")
        XCTAssertLessThan(rows[0], everyRow, "precondition: the page opened with less than every launch")
        var steps: [String] = []
        for ask in 1...LogView.earlierCeiling {
            let declares = page.declares
            page.place.drawEarlier()
            page.settle()
            rows.append(page.place.drawnRows)
            steps.append("ask \(ask): \(rows[ask - 1]) -> \(rows[ask]) rows, declares +\(page.declares - declares)")
            XCTAssertGreaterThan(rows[ask], rows[ask - 1], "ask \(ask) drew nothing more: \(steps)")
            XCTAssertGreaterThan(page.declares, declares, "ask \(ask) did not run the page's body: \(steps)")
        }
        XCTAssertEqual(rows.last, everyRow, "the asks up to the ceiling did not draw every launch: \(steps)")
        for extra in 1...(LogView.earlierCeiling + 2) {
            let declares = page.declares
            page.place.drawEarlier()
            page.settle()
            steps.append("extra \(extra): \(page.place.drawnRows) rows, declares +\(page.declares - declares)")
            XCTAssertEqual(page.place.drawnRows, everyRow, "ask past the ceiling changed the rows: \(steps)")
            XCTAssertEqual(page.declares, declares, "ask past the ceiling still wrote the page's state: \(steps)")
        }
        print("LOG-CEILING \(steps.joined(separator: "; ")) (every row \(everyRow))")
    }

    /// One ask as the place makes it, the page left to come to rest: the rows
    /// standing and the toolbar's declarations before and after.
    private func ask(_ page: Page) -> (rows: Int, drew: Int, declared: Int) {
        let rows = page.place.drawnRows
        let declares = page.declares
        page.place.drawEarlier()
        page.settle()
        return (rows, page.place.drawnRows - rows, page.declares - declares)
    }

    /// **A log whose every launch is drawn after the first ask is not asked
    /// again.** Five launches of 43 rows draw four at open and all five at the
    /// first ask; the asks after it re-declare nothing and leave the rows as they
    /// are. The count of rows is the whole tail, so the silence is not a page that
    /// drew nothing.
    func testAPageThatDrawsEveryLaunchAtTheFirstAskWritesNothingAtTheNext() throws {
        let lines = Self.tail(launches: 5)
        let everyRow = Self.presentation(lines).cards.reduce(0) { $0 + $1.rows.count }
        let page = Page(lines)
        defer { page.close() }
        page.settle()
        XCTAssertGreaterThan(page.place.drawnRows, 0, "no row reported its place")
        XCTAssertLessThan(page.place.drawnRows, everyRow, "precondition: the page opened with less than every launch")
        let first = ask(page)
        XCTAssertEqual(page.place.drawnRows, everyRow, "the first ask did not draw every launch: drew \(first.drew) rows")
        XCTAssertEqual(first.declared, 1, "the first ask did not run the page's body once")
        var later: [String] = []
        for index in 1...(LogView.earlierCeiling + 2) {
            let next = ask(page)
            later.append("ask \(index + 1): drew \(next.drew), declares +\(next.declared)")
            XCTAssertEqual(next.drew, 0, "an ask after every launch was drawn changed the rows: \(later)")
            XCTAssertEqual(next.declared, 0, "an ask after every launch was drawn wrote the page's state: \(later)")
        }
        XCTAssertEqual(page.place.drawnRows, everyRow, "the rows did not stand: \(later)")
    }

    /// **Every ask draws a launch more while one is not drawn, and the page is
    /// written once each.** Seven launches of unequal sizes draw 3, 3, 5 and 7
    /// launches at 100, 200, 400 and 800 rows: the first ask steps over 200 and
    /// the page's rows grow at it, as at the second, and the third finds nothing.
    func testEveryAskDrawsALaunchMoreOnLaunchesOfUnequalSizesUntilAllAreDrawn() throws {
        let lines = Self.tail(sizes: [5, 120, 40, 7, 300, 33, 90])
        let everyRow = Self.presentation(lines).cards.reduce(0) { $0 + $1.rows.count }
        let page = Page(lines)
        defer { page.close() }
        page.settle()
        XCTAssertGreaterThan(page.place.drawnRows, 0, "no row reported its place")
        var steps: [String] = []
        while page.place.drawnRows < everyRow, steps.count < LogView.earlierCeiling + 2 {
            let step = ask(page)
            steps.append("ask \(steps.count + 1): \(step.rows) -> \(page.place.drawnRows) rows, declares +\(step.declared)")
            XCTAssertGreaterThan(step.drew, 0, "an ask drew nothing while a launch was not drawn: \(steps)")
            XCTAssertEqual(step.declared, 1, "an ask did not run the page's body once: \(steps)")
        }
        XCTAssertEqual(page.place.drawnRows, everyRow, "the asks did not draw every launch: \(steps)")
        XCTAssertEqual(steps.count, 2, "the asks that drew were not the two the figures give: \(steps)")
        let after = ask(page)
        XCTAssertEqual(after.drew, 0, "an ask after every launch was drawn changed the rows: \(steps)")
        XCTAssertEqual(after.declared, 0, "an ask after every launch was drawn wrote the page's state: \(steps)")
        print("LOG-UNEQUAL \(steps.joined(separator: "; ")); then +\(after.declared) (every row \(everyRow))")
    }

    /// **The page grown with Follow lit, the view at the end, stays at the end —
    /// at every ask, the later ones included.** A log short enough that, with the
    /// view at the end, the view is within its own height of the top of what is
    /// drawn (the ask's condition on the distance), in a view tall enough to hold
    /// most of it: eleven launches of 40 rows, of which four are drawn at open and
    /// six and ten at the next figures. Follow is lit (the page's own default) and
    /// the page asks as the view rests at the end. The place's ask is wrapped to
    /// read the state it is made in — the rows standing, the view's top and its
    /// distance from the end — and then called, so that each ask is read in the
    /// state the growth of the one before it left. The rows grow at every ask that
    /// finds a launch undrawn, every ask is made with the view at the end, and the
    /// view is at the end afterwards, by the measure of the neighbouring families
    /// (the page's own bottom padding and a point).
    ///
    /// With `following() && isAtEnd` taken out of the ask the first ask is still
    /// made and the second is not, so it is the second that this row holds to the
    /// clause. What holds the end is not read here: in a window never ordered, with
    /// the page's bottom anchors (`defaultScrollAnchor`) taken out, the row printed
    /// the same figures, and the end was sought once, after the second growth. Whether
    /// the scroll view's own anchor keeps it in a window on screen is for a family
    /// that orders one.
    func testThePageGrownWithFollowLitAndTheViewAtTheEndIsStillAtTheEnd() throws {
        let lines = Self.tail(launches: 11, rowsPerLaunch: 40)
        let everyRow = Self.presentation(lines).cards.reduce(0) { $0 + $1.rows.count }
        let page = Page(lines, height: 4_000)
        defer { page.close() }
        var asks: [(rows: Int, gap: CGFloat, top: CGFloat, visible: CGFloat, document: CGFloat, sought: Int)] = []
        var sought = 0
        // The ask is made once the layout has been quiet for the place's period
        // (`LogReaderPlace.quiet`); the first row reported is early enough to
        // put the wrappers in its way.
        while page.place.drawnRows == 0 {
            page.mount.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        let original = page.place.drawEarlier
        let originalEnd = page.place.scrollToEnd
        // The page's view outlives the row for a moment and may rest once more; the
        // wrappers hold the page weakly and are taken off again, so that a rest after
        // the row has ended calls the page's own closures and nothing of the row's.
        defer {
            page.place.drawEarlier = original
            page.place.scrollToEnd = originalEnd
        }
        page.place.scrollToEnd = {
            sought += 1
            originalEnd()
        }
        page.place.drawEarlier = { [weak page] in
            if let page {
                let scroll = page.scroll
                asks.append((page.place.drawnRows, (try? page.gap()) ?? .nan,
                             scroll?.documentVisibleRect.minY ?? .nan,
                             scroll?.documentVisibleRect.height ?? 0, scroll?.documentView?.frame.height ?? 0,
                             sought))
            }
            original()
        }
        page.settle()
        let follow = try XCTUnwrap(page.channel.content(for: "log")?.actions.first { $0.id == "follow" },
                                   "the toolbar has no Follow")
        guard case .toggle(let lit, _) = follow.kind else { return XCTFail("Follow is not a toggle") }
        XCTAssertTrue(lit, "precondition: Follow is lit")
        let after = page.place.drawnRows
        let gapAfter = try page.gap()
        let scroll = try XCTUnwrap(page.scroll)
        let documentAfter = try XCTUnwrap(scroll.documentView).frame.height
        let said = asks.enumerated().map { index, ask in
            "ask \(index + 1): \(ask.rows) rows, document \(Int(ask.document)) pt, view \(Int(ask.visible)) pt at \(Int(ask.top)), \(Int(ask.gap)) pt from the end, end sought \(ask.sought) times"
        }
        print("LOG-FOLLOW \(said.joined(separator: "; ")); afterwards \(after) rows of \(everyRow), document \(Int(documentAfter)) pt, view top \(Int(scroll.documentVisibleRect.minY)), \(Int(gapAfter)) pt from the end, end sought \(sought) times")
        let first = try XCTUnwrap(asks.first, "the page asked for nothing: \(page.place.drawnRows) rows of \(everyRow) stand")
        // The subject: more than one ask came with a launch undrawn, the view at the
        // end, the top within a view of the view's top.
        XCTAssertGreaterThanOrEqual(asks.count, 2, "the page asked once, so no ask was made of a page that had already grown: \(said)")
        XCTAssertLessThan(first.rows, everyRow, "precondition: a launch was not drawn at the first ask: \(said)")
        for (index, ask) in asks.enumerated() {
            XCTAssertLessThanOrEqual(ask.gap, HelmSpace.s5 + 1, "ask \(index + 1) was made \(ask.gap) pt from the end: \(said)")
            XCTAssertLessThanOrEqual(ask.top, ask.visible, "ask \(index + 1) was made further than a view from the top: \(said)")
            XCTAssertGreaterThan(ask.document, ask.visible, "precondition: the document is not taller than the view at ask \(index + 1)")
        }
        // What follows: each ask that found a launch undrawn grew the page.
        for (before, next) in zip(asks, asks.dropFirst()) {
            XCTAssertGreaterThan(next.rows, before.rows, "an ask drew no launch more: \(said)")
        }
        XCTAssertGreaterThan(after, first.rows, "the ask drew no launch more: \(said)")
        XCTAssertLessThanOrEqual(gapAfter, HelmSpace.s5 + 1, "the page grew and the view is \(gapAfter) pt from the end: \(said)")
    }
}
