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

    /// **The flag built from regional indicators is gone** with the
    /// `flagEmoji` style it drew for. Helm ships its own artwork
    /// (`FlagAsset`, 50 PNGs), `flagDrawn` is the default and now the only flag
    /// style, and «Flag» and «Flag, system» were one idea under two names that
    /// nobody could tell apart from the words. `LanguageBadge.label` still
    /// carries the rule that matters — a language is not a country, and no
    /// country means letters rather than a guess.
}

extension LanguageBadgeTests {
    /// Stored as a string, so an unreadable value is the plainest thing rather
    /// than a crash or a blank menu bar.
    func testAnUnknownStyleFallsBackToLetters() {
        for raw in [nil, "", "Filled", "flag"] {
            XCTAssertEqual(BadgeStyle.from(raw), .default, String(describing: raw))
        }
        for style in BadgeStyle.allCases {
            XCTAssertEqual(BadgeStyle.from(style.rawValue), style)
        }
    }

    func testOnlyFlagsNeedACountry() {
        XCTAssertTrue(BadgeStyle.flagDrawn.needsRegion)
        for style in [BadgeStyle.plain, .filled, .outlined] {
            XCTAssertFalse(style.needsRegion)
        }
    }
}

/// Every layout should reach a flag, or the indicator is flags for some rows
/// and letters for others — which reads as a bug, not a choice.
extension LanguageBadgeTests {
    func testTheLayoutNameDecidesTheCountry() {
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.ABC",
                                            language: "en"), "US")
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.British",
                                            language: "en"), "GB")
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.Russian-PC",
                                            language: "ru"), "RU")
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.German-DIN-2137",
                                            language: "de"), "DE")
    }

    /// "ABC" and "British" are both English: the language tag alone cannot tell
    /// them apart, which is why the layout name is asked first.
    func testTheLanguageTagAloneWouldNotDoIt() {
        XCTAssertNotEqual(LanguageBadge.region(sourceID: "com.apple.keylayout.ABC", language: "en"),
                          LanguageBadge.region(sourceID: "com.apple.keylayout.British",
                                               language: "en"))
    }

    /// A layout Helm has never heard of still gets a country when its tag
    /// carries one.
    func testAnUnknownLayoutFallsBackToTheTag() {
        XCTAssertEqual(LanguageBadge.region(sourceID: "com.example.keylayout.Whatever",
                                            language: "fr-CA"), "CA")
        XCTAssertNil(LanguageBadge.region(sourceID: "com.example.keylayout.Whatever",
                                          language: "eo"))
    }

    /// And when there is genuinely no country, letters — rather than a blank.
    func testNoCountryStillHasALabel() {
        XCTAssertFalse(LanguageBadge.label(language: "eo", region: nil).isEmpty)
    }
}

/// The table is scanned with `first(where: hasPrefix)` over a Dictionary, whose
/// order is seeded per process. That is only safe while no key is a prefix of
/// another — the comment above the table claims it, and nothing checked.
final class BadgeTablePrefixTests: XCTestCase {

    /// Every layout id that could be ambiguous must answer the same on every
    /// launch. Asking a hundred times exercises a hundred iteration orders
    /// across runs, and the answer may not depend on which one came up.
    func testNoLayoutNameCanBeClaimedByTwoDifferentRegions() {
        let names = ["Canadian", "Canadian-CSA", "US", "USExtended", "USInternational-PC",
                     "Russian", "Russian-PC", "British", "British-PC", "German", "German-DIN",
                     "Swiss", "SwissGerman", "SwissFrench", "ABC", "ABC-QWERTZ",
                     "Belarusian", "Byelorussian", "Serbian", "Serbian-Latin",
                     "Portuguese", "Brazilian", "Spanish", "Spanish-ISO"]
        for name in names {
            let answers = Set((0..<100).map {
                _ in LanguageBadge.region(sourceID: "com.apple.keylayout.\(name)",
                                          language: "en") ?? "<nil>"
            })
            XCTAssertEqual(answers.count, 1,
                           "\(name) resolves to \(answers.sorted()) depending on dictionary order")
        }
    }
}
