import XCTest
@testable import HelmRuntime

/// A count of things is a number the language writes its own way.
///
/// Counts were interpolated straight out of `Int`, so a scan of `/` reported
/// "1499308 files" — seven digits nobody can read at a glance, in a place where
/// the only thing the number has to do is convey a magnitude. macOS writes
/// 1 499 308 in Russian and French and 1.499.308 in German.
///
/// This is a separate helper from `decimal` on purpose. `decimal` turns
/// grouping *off*, because it writes the mantissa of a size — "1,5" in "1,5 ГБ"
/// — and a grouping separator there would be a second decimal mark in the same
/// number. So the two cannot share a setting, only a formatter cache.
final class GroupedCountTests: XCTestCase {

    func testGermanGroupsWithFullStops() {
        XCTAssertEqual(HelmBytes.grouped(1_499_308, language: "de"), "1.499.308")
    }

    func testEnglishGroupsWithCommas() {
        XCTAssertEqual(HelmBytes.grouped(1_499_308, language: "en"), "1,499,308")
    }

    /// Russian and French group with a space, but which space is the system's
    /// business and it has changed between releases (U+00A0, U+202F). What this
    /// guards is that the separator is a space that will not break the number
    /// across two lines — not which codepoint macOS picked this year.
    func testRussianAndFrenchGroupWithANonBreakingSpace() {
        for language in ["ru", "fr"] {
            let written = HelmBytes.grouped(1_499_308, language: language)
            XCTAssertEqual(written.filter(\.isNumber), "1499308", written)
            let separators = Set(written.filter { !$0.isNumber })
            XCTAssertEqual(separators.count, 1, "\(language) used more than one separator: \(written)")
            let separator = separators.first!
            XCTAssertTrue(separator.isWhitespace, "\(language) grouped with \(separator)")
            XCTAssertFalse(separator == " ", "\(language) can break the number across lines")
        }
    }

    /// The defect this replaces, stated so the tests above are not measuring
    /// their own convention: an ungrouped seven-digit count is what shipped.
    func testTheNumberIsNotLeftUngrouped() {
        for language in ["en", "ru", "fr", "de", "es", "pt", "ja", "zh"] {
            XCTAssertNotEqual(HelmBytes.grouped(1_499_308, language: language), "1499308", language)
        }
    }

    /// Small numbers get no separator anywhere — "1 000" is a threshold, not a
    /// rule, and three digits must read as three digits.
    func testShortNumbersAreLeftAlone() {
        for language in ["en", "ru", "fr", "de"] {
            XCTAssertEqual(HelmBytes.grouped(0, language: language), "0")
            XCTAssertEqual(HelmBytes.grouped(999, language: language), "999")
        }
    }

    func testNegativeCountsAreStillWritable() {
        XCTAssertEqual(HelmBytes.grouped(-1_499_308, language: "en"), "-1,499,308")
    }

    /// The size mantissa must not have picked up grouping on the way past: the
    /// two share a formatter cache and would share its settings by accident.
    func testTheSizeMantissaStillHasNoGrouping() {
        XCTAssertEqual(HelmBytes.decimal(1234.5, decimals: 1, language: "en"), "1234.5")
        XCTAssertEqual(HelmBytes.string(1_400_000_000, language: "en"), "1.4 GB")
    }
}
