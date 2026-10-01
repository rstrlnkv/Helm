import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What the Log page's cards and footer *say*, in every language: the word on a
/// card that has no start line of its own, and the dates the footer and the ×N
/// tooltip write.
final class TheLogCardsAreNamedAndDatedHonestlyTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ seconds: Double, _ category: String = "vpn",
                      _ message: String = "network state changed; re-reading") -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: .info, category: category, message: message)
    }

    // MARK: - The word on a card with no start line

    /// **A run that follows a «terminating» is not an «Earlier launch».** It is
    /// later than the launch above it — the page draws it below that card, the
    /// last on the page — and «earlier» is the word for the head of the tail,
    /// whose own start scrolled out of it. The file records the time of the
    /// run's first line and nothing more, so that is what the header says.
    func testARunAfterTerminatingIsNotCalledEarlierInAnyLanguage() throws {
        // The tail begins mid-launch, that launch ends, another says nothing of
        // how it began, and a last one has its start line.
        let lines = [line(0), line(10, "app", "terminating"),
                     line(600), line(610),
                     line(900, "app", "Helm 0.11.1-dev.14 started"), line(910)]
        let sessions = LogSessions.split(lines)
        XCTAssertEqual(sessions.map(\.title),
                       [.earlierLaunch, .noStartLine, .launch(version: "0.11.1-dev.14")],
                       "the fixture split into other cards than the three this is about")
        AppLanguage.each { language in
            let lang = language.rawValue
            let head = LogView.headerWords(for: sessions[0])
            XCTAssertEqual(head.heading, AppStr.logEarlierLaunch, "\(lang): the head of the tail lost its word")
            let after = LogView.headerWords(for: sessions[1])
            XCTAssertNotEqual(after.heading, AppStr.logEarlierLaunch,
                              "\(lang): a run that began after the launch above it is called «\(after.heading)»")
            XCTAssertEqual(after.heading, HelmDates.dayAndMinute(sessions[1].lines[0].date),
                           "\(lang): the run's header is not the time of its first line")
            XCTAssertNil(after.detail, "\(lang): the run's header carries a detail the file does not record")
            let launch = LogView.headerWords(for: sessions[2])
            XCTAssertEqual(launch.detail, "Helm 0.11.1-dev.14", "\(lang)")
        }
    }

    // MARK: - Dates the way each language writes them

    /// «since 21/09/2026 17:12» is a sentence about a date, and French and
    /// Spanish put an article before a date: «depuis le», «desde el». The
    /// neighbouring «Not modified since» already does, in the same two
    /// languages.
    func testTheFootersSinceTakesTheArticleBeforeADateInFrenchAndSpanish() {
        AppLanguage.only(.fr) {
            XCTAssertEqual(AppStr.logSince("21/09/2026 17:12"), "depuis le 21/09/2026 17:12")
        }
        AppLanguage.only(.es) {
            XCTAssertEqual(AppStr.logSince("21/9/26, 17:12"), "desde el 21/9/26, 17:12")
        }
        AppLanguage.each { language in
            XCTAssertTrue(AppStr.logSince("D").contains("D"), "\(language.rawValue): the date was dropped")
        }
    }

    /// The ×N tooltip says «until 09:00» for a run that ended the same day and
    /// «until <day and minute>» for one that crossed midnight; the second takes
    /// the article in French and Spanish, the first does not.
    func testTheRepeatTooltipTakesTheArticleOnlyBeforeADate() {
        let early = line(0)
        let sameDay = LogPresentation.Row(lines: [early, line(60)], heading: nil)
        let across = LogPresentation.Row(lines: [early, line(90_000)], heading: nil)
        AppLanguage.only(.fr) {
            XCTAssertTrue(LogRowView.repeatedUntilNote(sameDay, calendar: utc).hasPrefix("Répétée jusqu’à "),
                          LogRowView.repeatedUntilNote(sameDay, calendar: utc))
            XCTAssertTrue(LogRowView.repeatedUntilNote(across, calendar: utc).hasPrefix("Répétée jusqu’au "),
                          LogRowView.repeatedUntilNote(across, calendar: utc))
        }
        AppLanguage.only(.es) {
            XCTAssertTrue(LogRowView.repeatedUntilNote(sameDay, calendar: utc).hasPrefix("Repetida hasta "))
            XCTAssertFalse(LogRowView.repeatedUntilNote(sameDay, calendar: utc).hasPrefix("Repetida hasta el "))
            XCTAssertTrue(LogRowView.repeatedUntilNote(across, calendar: utc).hasPrefix("Repetida hasta el "),
                          LogRowView.repeatedUntilNote(across, calendar: utc))
        }
        AppLanguage.each { language in
            for row in [sameDay, across] {
                let note = LogRowView.repeatedUntilNote(row, calendar: utc)
                XCTAssertTrue(note.contains(LogRowView.repeatedUntil(row, calendar: utc)),
                              "\(language.rawValue): the tooltip lost the time it is about: \(note)")
            }
        }
    }

    /// **A row that ran across midnight is headed by the days it stands for,
    /// spelled by the system's interval formatter.** Japanese writes «～», not a
    /// dash with blanks round it; the others write a day that shares its month
    /// or year once. The expectation is the formatter's own answer for the
    /// language, built here with the language named; the subject is asserted
    /// first (a span was drawn), and Japanese is held to its sign.
    func testADaySpanIsSpelledTheWayTheLanguageSpellsIt() throws {
        let lines = [line(0, "app", "Helm 0.11.1-dev.14 started"),
                     line(70_000), line(171_000), line(171_001)]
        // Three lines that say the same thing in a row, the last on another day.
        let same = (0..<3).map { index in
            LogEntry(date: base.addingTimeInterval(Double(index) * 40_000), level: .warn, category: "layout",
                     message: "no accessibility grant — not watching")
        }
        let page0 = LogPresentation.build(lines + same, minimumLevel: .info, categories: [], query: "",
                                          language: "en", calendar: utc)
        let spans = page0.cards.flatMap(\.rows).filter {
            !utc.isDate($0.first.date, inSameDayAs: $0.last.date)
        }
        XCTAssertFalse(spans.isEmpty, "no row crossed midnight, so no span was drawn")
        AppLanguage.each { language in
            let page = LogPresentation.build(lines + same, minimumLevel: .info, categories: [], query: "",
                                             language: language.rawValue, calendar: utc)
            for row in page.cards.flatMap(\.rows)
            where !utc.isDate(row.first.date, inSameDayAs: row.last.date) {
                let formatter = DateIntervalFormatter()
                formatter.locale = Locale(identifier: language.rawValue)
                formatter.timeZone = utc.timeZone
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                let system = formatter.string(from: row.first.date, to: row.last.date)
                XCTAssertFalse(system.isEmpty, "\(language.rawValue): the system wrote no interval")
                XCTAssertEqual(row.heading, system, "\(language.rawValue): the span is not the system's")
                if language == .ja {
                    XCTAssertTrue(row.heading?.contains("～") ?? false, "ja: no «～» in \(row.heading ?? "nil")")
                    XCTAssertFalse(row.heading?.contains(" – ") ?? true, "ja: a hand-joined dash in \(row.heading ?? "nil")")
                }
            }
        }
    }
}
