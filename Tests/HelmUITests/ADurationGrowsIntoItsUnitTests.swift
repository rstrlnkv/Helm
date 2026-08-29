import XCTest
@testable import HelmUI

/// A span of saved time, spelled the way the language spells one.
///
/// The figure it draws starts at seconds on a quiet day and reaches hours over
/// a year, so the unit has to grow on its own: «4 081 минута» is what happens
/// to a page that picked minutes once and stopped thinking. It lives beside
/// `Bytes` and `HelmDates` for the same reason they do — a `Foundation`
/// formatter built with no locale answers in the *system's* language, not the
/// app's, and this app's language is its own setting.
final class ADurationGrowsIntoItsUnitTests: XCTestCase {

    func testSecondsWhileItIsSeconds() {
        for language in AppLanguage.allCases {
            let line = HelmDuration.string(40, language: language)
            XCTAssertFalse(line.isEmpty, "\(language) said nothing about 40 seconds")
            XCTAssertTrue(line.contains("40"), "\(language): \(line)")
        }
    }

    /// The spellings are macOS's own, measured on this Mac rather than
    /// invented: English abbreviates to «20m», Russian to «20 мин», Japanese to
    /// «20分». The first draft of this test asserted «3 min» — a form the system
    /// does not produce in any of the eight.
    func testMinutesOnceThereAreMinutes() {
        XCTAssertEqual(HelmDuration.string(3 * 60, language: .en), "3m")
        XCTAssertEqual(HelmDuration.string(59 * 60 + 59, language: .en), "59m")
        XCTAssertEqual(HelmDuration.string(20 * 60, language: .ru), "20 мин")
    }

    /// The case the page will actually show for a month of use.
    func testAnHourIsHoursAndMinutes() {
        XCTAssertEqual(HelmDuration.string(3600, language: .en), "1h")
        XCTAssertEqual(HelmDuration.string(3600 + 20 * 60, language: .en), "1h 20m")
        XCTAssertEqual(HelmDuration.string(11 * 3600 + 20 * 60, language: .en), "11h 20m")
        // The form the mockup drew, and the one this page will mostly show.
        XCTAssertEqual(HelmDuration.string(11 * 3600 + 20 * 60, language: .ru), "11 ч 20 мин")
    }

    /// **A round hour says «1 h», not «1 h 0 min».** A zero that carries no
    /// information is a zero the reader has to discard.
    func testAWholeHourDropsTheMinutes() {
        XCTAssertEqual(HelmDuration.string(2 * 3600, language: .en), "2h")
        XCTAssertEqual(HelmDuration.string(2 * 3600, language: .ru), "2 ч")
    }

    /// Nothing is nothing — not «0 s». The page draws no figure at all when
    /// there is nothing to draw, and this is the value it checks.
    func testNothingIsEmpty() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(HelmDuration.string(0, language: language).isEmpty,
                          "\(language) invented a figure for no time at all")
        }
    }

    /// Each language uses its own unit, not English abbreviations transliterated.
    func testEveryLanguageUsesItsOwnUnits() {
        XCTAssertTrue(HelmDuration.string(20 * 60, language: .ru).contains("мин"))
        XCTAssertTrue(HelmDuration.string(20 * 60, language: .de).contains("min"))
        XCTAssertTrue(HelmDuration.string(2 * 3600, language: .ja).contains("時間"))
        XCTAssertTrue(HelmDuration.string(2 * 3600, language: .zh).contains("小时"))
    }

    /// The figure has to be readable at a glance at the hero's size, so it never
    /// runs to three parts — no «1 h 20 min 30 s».
    func testItNeverRunsToThreeParts() {
        for language in AppLanguage.allCases {
            let line = HelmDuration.string(3600 + 20 * 60 + 30, language: language)
            XCTAssertLessThanOrEqual(line.split(separator: " ").count, 4, "\(language): \(line)")
        }
    }
}
