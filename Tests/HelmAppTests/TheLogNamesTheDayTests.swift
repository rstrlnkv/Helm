import XCTest
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The owner's report: «В журнале нет дат, только время». A row draws the time
/// of day and nothing else, so two lines a day apart read as one evening.
///
/// The page names the day above the first line shown and again wherever it
/// changes. Asserted per language, because the heading is a visible string and
/// this Mac runs in one of eight.
final class TheLogNamesTheDayTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ day: Int, hour: Int) -> LogEntry {
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: 5))!
        return LogEntry(date: date, level: .info, category: "app", message: "line")
    }

    func testTheFirstLineShownNamesItsDayInEveryLanguage() {
        let first = entry(29, hour: 23)
        AppLanguage.each { language in
            let heading = LogView.dayHeading(for: first, after: nil,
                                             language: language.rawValue, calendar: calendar)
            XCTAssertEqual(heading, HelmDates.day(first.date, language: language.rawValue),
                           "\(language)")
            XCTAssertFalse(heading?.isEmpty ?? true, "\(language)")
            XCTAssertTrue(heading?.contains("2026") ?? false, "\(language): \(heading ?? "nil")")
        }
    }

    func testTheHeadingChangesWithTheDayAndOnlyThen() {
        let evening = entry(28, hour: 12)
        let sameEvening = entry(28, hour: 13)
        let morning = entry(30, hour: 12)
        AppLanguage.each { language in
            let code = language.rawValue
            XCTAssertNil(LogView.dayHeading(for: sameEvening, after: evening,
                                            language: code, calendar: calendar), "\(language)")
            let next = LogView.dayHeading(for: morning, after: evening,
                                          language: code, calendar: calendar)
            XCTAssertNotNil(next, "\(language)")
            XCTAssertNotEqual(next, LogView.dayHeading(for: evening, after: nil,
                                                       language: code, calendar: calendar),
                              "\(language): two days read alike")
        }
    }
}
