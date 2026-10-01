import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What the repair of the launch cards has to hold that the findings' own tests
/// do not say: the head of a rolling tail keeps one identity, a run that starts
/// on an unanswered «logging enabled» is not a launch of the version above it,
/// a repeat across midnight names its day in its tooltip.
final class TheLogCardsKeepTheirIdentityAndTheirWordsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_790_000_000)   // 14:13:20 UTC

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "vpn",
                      _ message: String = "network state changed; re-reading") -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message)
    }

    private func build(_ lines: [LogEntry]) -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "",
                              language: "en", calendar: utc)
    }

    /// A full tail that is one long launch: each tick the oldest line goes and
    /// one arrives, and the card must be the same card — a new identity is a card
    /// torn down and built whole every second.
    func testTheHeadOfARollingTailIsOneCard() {
        let all = (0..<300).map { line(Double($0)) }
        let ids = (0..<50).map { dropped in
            build(Array(all[dropped..<(dropped + 200)])).cards.map(\.id)
        }
        XCTAssertEqual(Set(ids.map { $0.count }), [1])
        XCTAssertEqual(Set(ids.flatMap { $0 }).count, 1, "the head card changed identity as the tail rolled")
    }

    /// The constant names the head and only the head: a later run that has no
    /// start line keeps its own first line's identity, so two cards never share.
    func testOnlyTheHeadSharesTheFixedIdentity() {
        let lines = [line(0), line(1, .info, "app", "terminating"), line(2), line(3)]
        let cards = build(lines).cards
        XCTAssertEqual(cards.count, 2)
        guard cards.count == 2 else { return }
        XCTAssertEqual(Set(cards.map(\.id)).count, 2)
        XCTAssertEqual(cards[1].id, lines[2].id)
    }

    func testAnUnansweredLoggingEnabledOpensARunWithNoVersion() {
        let lines = [line(0, .info, "app", "Helm 0.10.0 started"), line(1), line(2),
                     line(3, .info, "app", "logging enabled"), line(4, .warn, "layout", "declined")]
        let sessions = LogSessions.split(lines)
        XCTAssertEqual(sessions.count, 2, "the split changed: \(sessions.map(\.version))")
        guard sessions.count == 2 else { return }
        XCTAssertEqual(sessions.map(\.version), ["0.10.0", nil])
        XCTAssertEqual(sessions[1].lines.count, 2)
        XCTAssertEqual(sessions.flatMap(\.lines).map(\.id), lines.map(\.id))
    }

    func testAnAnsweredLoggingEnabledStaysInItsLaunch() {
        let lines = [line(0, .info, "app", "Helm 0.10.0 started"),
                     line(1, .info, "app", "logging disabled"),
                     line(2, .info, "app", "logging enabled"), line(3)]
        XCTAssertEqual(LogSessions.split(lines).map(\.version), ["0.10.0"])
    }

    func testTheTooltipNamesTheDayOnlyWhenTheRunCrossedIt() {
        let same = LogPresentation.Row(lines: [line(0), line(60)], heading: nil)
        let across = LogPresentation.Row(lines: [line(35_000), line(35_300)], heading: nil)
        XCTAssertFalse(utc.isDate(across.first.date, inSameDayAs: across.last.date))
        XCTAssertEqual(LogRowView.repeatedUntil(same, calendar: utc), HelmDates.logTime(same.last.date))
        XCTAssertEqual(LogRowView.repeatedUntil(across, calendar: utc),
                       HelmDates.dayAndMinute(across.last.date))
    }

    func testTheFooterCountsEveryLineWhenNothingIsFiltered() {
        let lines = [line(0, .info, "app", "Helm 0.11.0 started"), line(1), line(2, .warn),
                     line(100, .info, "app", "Helm 0.11.1 started"), line(101)]
        let page = build(lines)
        XCTAssertEqual(page.shown, lines.count)
        XCTAssertEqual(page.lines.count, lines.count)
    }
}
