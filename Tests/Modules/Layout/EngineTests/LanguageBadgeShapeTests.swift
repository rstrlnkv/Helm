import XCTest
@testable import Module_Layout_Engine

/// The badge on language tags of an unhelpful shape, and the tables behind it.
///
/// The indicator is drawn from whatever `kTISPropertyInputSourceLanguages`
/// happens to say, which is a list Helm does not control: it can carry a bare
/// code, a script, a region, or nothing at all.
final class LanguageBadgeShapeTests: XCTestCase {
    /// An empty label is not a small indicator — it is no indicator. The image
    /// is sized to the text, so a status item switched on draws at zero width:
    /// invisible, unclickable, and indistinguishable from the module being off.
    ///
    /// Reachable: `InputSourceInfo` reads `languages(source).first ?? ""`, and
    /// its own fallback for a source it cannot read at all is "?" — so the gap
    /// is only in this path.
    func testTheBadgeIsNeverEmpty() {
        for language in ["", " ", "-", "und", "mul", "zxx"] {
            XCTAssertFalse(LanguageBadge.label(language: language, region: nil).isEmpty,
                           "an empty badge draws a zero-width menu bar item: \"\(language)\"")
        }
    }

    /// Every shape the system actually hands over: a bare code, a code with a
    /// region, a code with a script, and the underscore form.
    func testTheTagIsReadDownToItsLanguage() {
        XCTAssertEqual(LanguageBadge.label(language: "ru_RU", region: nil), "РУ")
        XCTAssertEqual(LanguageBadge.label(language: "RU", region: nil), "РУ")
        XCTAssertEqual(LanguageBadge.label(language: "sr-Cyrl-RS", region: nil), "СР")
        XCTAssertEqual(LanguageBadge.label(language: "zh-Hans-CN", region: nil), "中")
        XCTAssertEqual(LanguageBadge.label(language: "en", region: "gb"), "GB")
    }

    /// A script of its own outranks the country: two Latin layouts are told
    /// apart by region, but Russian is "РУ" wherever it is typed.
    func testAScriptOfItsOwnIgnoresTheRegion() {
        XCTAssertEqual(LanguageBadge.label(language: "ru", region: "KZ"), "РУ")
        XCTAssertEqual(LanguageBadge.label(language: "ru", region: nil), "РУ")
    }

    /// The stripes are handed to a six-hex-digit parser that reports nothing on
    /// a value it cannot read — it just fills black. A typo in the table would
    /// ship as a black band on somebody's flag, and no test would notice.
    func testEveryDrawnFlagIsMadeOfReadableColours() {
        for region in ["RU", "DE", "FR", "IT", "NL", "UA", "PL", "AT", "ES", "BE", "IE", "SE"] {
            guard let stripes = LanguageBadge.stripes(region: region) else {
                return XCTFail("\(region) left the table")
            }
            XCTAssertTrue((2...3).contains(stripes.colors.count), region)
            for hex in stripes.colors {
                XCTAssertEqual(hex.count, 6, "\(region): \"\(hex)\" is not six hex digits")
                XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "\(region): \"\(hex)\"")
            }
        }
    }

    /// The two flag styles are offered for the same layout, so a country that
    /// can be drawn must also be one that can be spelled with regional
    /// indicators — otherwise one style shows a flag and the other letters.
    func testADrawnFlagAlwaysHasAnEmojiToo() {
        for region in ["RU", "DE", "FR", "IT", "NL", "UA", "PL", "AT", "ES", "BE", "IE", "SE"] {
            XCTAssertNotNil(LanguageBadge.emojiFlag(region: region), region)
        }
    }

    /// Two characters, both ASCII letters. Everything else is not a country
    /// code however much it looks like one — and the arithmetic behind the flag
    /// runs off the end of the alphabet for anything that is not.
    func testOnlyATwoLetterCountryMakesAFlag() {
        for region in ["R U", "R-", "RÜ", "🇷🇺", "R\u{0301}U", "р", "ру"] {
            XCTAssertNil(LanguageBadge.emojiFlag(region: region), region)
        }
    }
}
