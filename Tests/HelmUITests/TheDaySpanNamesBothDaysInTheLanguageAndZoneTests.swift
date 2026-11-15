import Foundation
import XCTest
@testable import HelmUI

/// `HelmDates.daySpan` heads a log row that ran across midnight. The Log page
/// tests only check that such a heading exists, so the language and the zone
/// the formatter is built for were pinned by nothing: a formatter fixed to one
/// language or one zone passed every test in the tree.
final class TheDaySpanNamesBothDaysInTheLanguageAndZoneTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!  // UTC+14
    // 2026-09-22 12:00 UTC and 2026-09-23 12:00 UTC.
    private let first = Date(timeIntervalSince1970: 1_790_078_400)
    private let last = Date(timeIntervalSince1970: 1_790_164_800)

    func testTheSpanNamesBothDaysAndTheMonth() {
        let span = HelmDates.daySpan(from: first, to: last, language: "en", zone: utc)
        XCTAssertTrue(span.contains("22") && span.contains("23") && span.contains("September"), span)
    }

    func testTheZoneDecidesWhichDaysAreNamed() {
        let inUTC = HelmDates.daySpan(from: first, to: last, language: "en", zone: utc)
        let farEast = HelmDates.daySpan(from: first, to: last, language: "en", zone: kiritimati)
        XCTAssertNotEqual(inUTC, farEast, "the span ignored the zone it was asked for")
        XCTAssertTrue(farEast.contains("24"), farEast)
        XCTAssertFalse(inUTC.contains("24"), inUTC)
    }

    func testTheLanguageDecidesHowTheyAreSpelled() {
        let english = HelmDates.daySpan(from: first, to: last, language: "en", zone: utc)
        let japanese = HelmDates.daySpan(from: first, to: last, language: "ja", zone: utc)
        let german = HelmDates.daySpan(from: first, to: last, language: "de", zone: utc)
        XCTAssertFalse(japanese.contains("September"), japanese)
        XCTAssertTrue(german.contains("September"), german)
        XCTAssertEqual(Set([english, japanese, german]).count, 3, "the span ignored the language it was asked for")
    }

    func testAskingTwiceInAnotherLanguageDoesNotAnswerFromTheFirst() {
        _ = HelmDates.daySpan(from: first, to: last, language: "ja", zone: utc)
        let english = HelmDates.daySpan(from: first, to: last, language: "en", zone: utc)
        XCTAssertTrue(english.contains("September"), english)
    }

    /// A span is spelled like the day headings of its language: in Chinese and
    /// Japanese with the 年 and 月 of `HelmDates.day`, not in numerals.
    ///
    /// Past defect: backlog #26, the interval formatter wrote `2026/9/22 – 2026/9/23`.
    func testTheSpanInChineseAndJapaneseIsSpelledLikeTheDayHeadings() {
        for language in ["zh", "ja"] {
            let heading = HelmDates.day(first, language: language)
            let span = HelmDates.daySpan(from: first, to: last, language: language, zone: utc)
            XCTAssertTrue(heading.contains("年") && heading.contains("月"), heading)
            XCTAssertTrue(span.hasPrefix(heading), "\(language): the span «\(span)» does not open as the heading «\(heading)»")
        }
    }
}
