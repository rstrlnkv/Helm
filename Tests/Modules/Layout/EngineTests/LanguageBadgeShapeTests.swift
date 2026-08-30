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

    /// **Two tests about emoji flags stood here** — that every region in the
    /// layout table could be spelled with regional indicators, and that only a
    /// two-letter ASCII code makes one. They went with `BadgeStyle.flagEmoji`:
    /// Helm draws its own flags from `FlagAsset`, and `FlagAssetTests` is where
    /// the artwork's own coverage is asserted.
}
