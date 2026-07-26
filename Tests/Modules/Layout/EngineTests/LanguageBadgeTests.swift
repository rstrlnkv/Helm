import XCTest
@testable import Module_Layout_Engine

/// The two characters in the corner of the screen. They are read at a glance,
/// so the rules are about recognition rather than correctness of naming.
final class LanguageBadgeTests: XCTestCase {
    func testNonLatinScriptsUseTheirOwnAlphabet() {
        XCTAssertEqual(LanguageBadge.label(language: "ru", region: "RU"), "РУ")
        XCTAssertEqual(LanguageBadge.label(language: "uk", region: "UA"), "УК")
        XCTAssertEqual(LanguageBadge.label(language: "el", region: "GR"), "ΕΛ")
    }

    /// "US" and "GB" are both English; showing "EN" twice tells you nothing.
    func testLatinLayoutsAreToldApartByCountry() {
        XCTAssertEqual(LanguageBadge.label(language: "en", region: "US"), "US")
        XCTAssertEqual(LanguageBadge.label(language: "en", region: "GB"), "GB")
        XCTAssertEqual(LanguageBadge.label(language: "de", region: "AT"), "AT")
    }

    /// A tag like "ru-RU" or "en_US" is what the system hands over.
    func testALongerTagStillWorks() {
        XCTAssertEqual(LanguageBadge.label(language: "ru-RU", region: nil), "РУ")
        XCTAssertEqual(LanguageBadge.label(language: "en-GB", region: nil), "EN")
    }

    func testAFlagIsBuiltFromTheCountry() {
        XCTAssertEqual(LanguageBadge.emojiFlag(region: "RU"), "🇷🇺")
        XCTAssertEqual(LanguageBadge.emojiFlag(region: "us"), "🇺🇸")
    }

    /// A language is not a country, and guessing one turns a keyboard layout
    /// into a statement. No country, no flag — the badge falls back to letters.
    func testNoCountryMeansNoFlag() {
        XCTAssertNil(LanguageBadge.emojiFlag(region: nil))
        XCTAssertNil(LanguageBadge.emojiFlag(region: ""))
        XCTAssertNil(LanguageBadge.emojiFlag(region: "USA"))
        XCTAssertNil(LanguageBadge.emojiFlag(region: "1A"))
    }

    /// A flag Helm cannot draw honestly is one it does not draw.
    func testDrawnFlagsAreOnlyTheOnesInTheTable() {
        XCTAssertEqual(LanguageBadge.stripes(region: "ru")?.colors.count, 3)
        XCTAssertEqual(LanguageBadge.stripes(region: "FR")?.vertical, true)
        XCTAssertEqual(LanguageBadge.stripes(region: "RU")?.vertical, false)
        XCTAssertNil(LanguageBadge.stripes(region: "JP"))
        XCTAssertNil(LanguageBadge.stripes(region: nil))
    }
}

extension LanguageBadgeTests {
    /// Stored as a string, so an unreadable value is the plainest thing rather
    /// than a crash or a blank menu bar.
    func testAnUnknownStyleFallsBackToLetters() {
        for raw in [nil, "", "Filled", "flag"] {
            XCTAssertEqual(BadgeStyle.from(raw), .plain, String(describing: raw))
        }
        for style in BadgeStyle.allCases {
            XCTAssertEqual(BadgeStyle.from(style.rawValue), style)
        }
    }

    func testOnlyFlagsNeedACountry() {
        XCTAssertTrue(BadgeStyle.flagEmoji.needsRegion)
        XCTAssertTrue(BadgeStyle.flagDrawn.needsRegion)
        for style in [BadgeStyle.plain, .filled, .outlined] {
            XCTAssertFalse(style.needsRegion)
        }
    }
}
