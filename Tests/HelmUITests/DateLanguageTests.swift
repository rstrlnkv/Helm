import XCTest
@testable import HelmUI

/// Dates were the one piece of text that came from the system's language rather
/// than the app's: three formatters were built with no locale at all, and two of
/// them were built once and held for the life of the process, so an Italian Mac
/// — outside Helm's eight, therefore shown an English UI — read
/// "Checked 2 ore fa".
final class DateLanguageTests: XCTestCase {

    func testARelativeDateIsSpelledInTheLanguageItIsAskedFor() {
        let then = Date(timeIntervalSinceNow: -7200)
        let russian = HelmDates.relative(then, language: "ru")
        let german = HelmDates.relative(then, language: "de")
        XCTAssertTrue(russian.contains("час"), russian)
        XCTAssertTrue(german.lowercased().contains("stunde"), german)
    }

    /// The half a held formatter got wrong: a second language must not be
    /// answered by the first one's formatter.
    func testEachLanguageKeepsItsOwnFormatter() {
        let then = Date(timeIntervalSinceNow: -7200)
        let first = HelmDates.relative(then, language: "ru")
        _ = HelmDates.relative(then, language: "fr")
        let again = HelmDates.relative(then, language: "ru")
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, HelmDates.relative(then, language: "fr"))
    }

    func testADayAndMinuteFollowsTheLanguageToo() {
        let stamp = Date(timeIntervalSince1970: 1_770_000_000)
        XCTAssertNotEqual(HelmDates.dayAndMinute(stamp, language: "ru"),
                          HelmDates.dayAndMinute(stamp, language: "en"))
    }

    /// A language Helm does not speak is not a language the dates may fall back
    /// to: the UI is English there, and the strip beside it has to be too.
    func testTheDefaultIsTheAppsLanguageAndNotTheSystems() {
        let then = Date(timeIntervalSinceNow: -7200)
        XCTAssertEqual(HelmDates.relative(then),
                       HelmDates.relative(then, language: AppLanguage.current.rawValue))
    }
}
