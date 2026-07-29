import XCTest
@testable import HelmUI

/// The changelog's dates are written down as "2026-07-28" and were drawn
/// straight into the sheet.
///
/// No language writes a date that way. It is a storage format — the one the
/// entries are keyed by, so it stays in `ChangelogData` — and turning it into a
/// day the reader recognises is the same job `HelmDates` already does for
/// "2 hours ago" and for the day-and-minute stamp.
final class ChangelogDateTests: XCTestCase {

    private static let day = "2026-07-28"

    func testAStoredDayIsWrittenInTheLanguageAskedFor() {
        XCTAssertTrue(HelmDates.day(Self.day, language: "en").contains("July"),
                      HelmDates.day(Self.day, language: "en"))
        XCTAssertTrue(HelmDates.day(Self.day, language: "de").contains("Juli"),
                      HelmDates.day(Self.day, language: "de"))
        XCTAssertTrue(HelmDates.day(Self.day, language: "ru").contains("июл"),
                      HelmDates.day(Self.day, language: "ru"))
    }

    /// The day itself must survive the trip. A date parsed in one time zone and
    /// written in another lands on the 27th for half the world, and a changelog
    /// entry dated a day early is the kind of wrong nobody reports.
    func testTheDayAndYearAreTheOnesGiven() {
        for language in ["en", "ru", "fr", "de", "es", "pt", "ja", "zh"] {
            let written = HelmDates.day(Self.day, language: language)
            XCTAssertTrue(written.contains("28"), "\(language): \(written)")
            XCTAssertTrue(written.contains("2026"), "\(language): \(written)")
        }
    }

    /// Whatever it writes, it must not be what it was given.
    func testItIsNotTheStorageFormat() {
        for language in ["en", "ru", "fr", "de", "es", "pt", "ja", "zh"] {
            XCTAssertNotEqual(HelmDates.day(Self.day, language: language), Self.day, language)
        }
    }

    /// A malformed entry shows what it says rather than nothing at all: the
    /// changelog is hand-written, and a blank line under a version number reads
    /// as a bug in the sheet rather than as a typo in the data.
    func testSomethingThatIsNotADayIsLeftAsItIs() {
        XCTAssertEqual(HelmDates.day("soon", language: "en"), "soon")
        XCTAssertEqual(HelmDates.day("", language: "en"), "")
    }

    func testTheDefaultFollowsTheAppsLanguage() {
        XCTAssertEqual(HelmDates.day(Self.day),
                       HelmDates.day(Self.day, language: AppLanguage.current.rawValue))
    }
}
