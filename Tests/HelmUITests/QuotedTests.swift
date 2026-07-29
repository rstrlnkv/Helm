import XCTest
@testable import HelmUI

/// Quotation marks belong to the language, and which marks a language uses is
/// looked up rather than remembered — the same rule the units and the pane
/// names already follow (ARCHITECTURE.md § Localization).
///
/// Counted over the 1176 `Localizable.loctable` files macOS ships, for the
/// shape this helper draws — a substituted name between a pair of marks:
///
///     fr   «\u{00A0}%@\u{00A0}»  3206     « %@ » (plain space)  12
///     es   “%@”                  2768     «%@»                   0
///     ja   “%@”                  3099     「%@」                  1
///     zh   “%@”                  3399
///     de   „%@“                  3674
///     ru   «%@»                   483
///
/// Three of the eight were invented instead of read. French put ordinary
/// spaces inside its guillemets where Apple uses U+00A0 — which is not a
/// nicety: a plain space there lets the line break between the mark and the
/// name it belongs to. Spanish was given guillemets and Japanese corner
/// brackets, and macOS uses curly quotes for both when what it quotes is a
/// name. This is the shared helper, so each of these was wrong everywhere at
/// once.
final class QuotedTests: XCTestCase {

    private static let nbsp = "\u{00A0}"

    func testFrenchKeepsTheNameAgainstItsGuillemets() {
        let quoted = Quoted("Safari", language: .fr)
        XCTAssertEqual(quoted, "«\(Self.nbsp)Safari\(Self.nbsp)»")
        XCTAssertFalse(quoted.contains(" "), "an ordinary space can break the line here")
    }

    func testSpanishAndJapaneseUseTheMarksMacOSUses() {
        XCTAssertEqual(Quoted("Safari", language: .es), "“Safari”")
        XCTAssertEqual(Quoted("Safari", language: .ja), "“Safari”")
    }

    func testTheLanguagesThatWereAlreadyRightAreUnchanged() {
        XCTAssertEqual(Quoted("Safari", language: .en), "“Safari”")
        XCTAssertEqual(Quoted("Safari", language: .ru), "«Safari»")
        XCTAssertEqual(Quoted("Safari", language: .de), "„Safari“")
        XCTAssertEqual(Quoted("Safari", language: .zh), "“Safari”")
        XCTAssertEqual(Quoted("Safari", language: .pt), "“Safari”")
    }

    /// Whatever the marks are, every language must put the name between a
    /// distinct pair of them — an opening mark equal to the closing one is how
    /// a straight-quote fallback would show up.
    func testEveryLanguageWrapsTheNameInAPair() {
        for language in AppLanguage.allCases {
            let quoted = Quoted("NAME", language: language)
            guard let name = quoted.range(of: "NAME") else {
                XCTFail("\(language) lost the name: \(quoted)")
                continue
            }
            let opening = quoted[quoted.startIndex..<name.lowerBound]
            let closing = quoted[name.upperBound...]
            XCTAssertFalse(opening.isEmpty, "\(language) has no opening mark")
            XCTAssertFalse(closing.isEmpty, "\(language) has no closing mark")
            XCTAssertNotEqual(opening.first, closing.last,
                              "\(language) opens and closes with the same mark")
        }
    }

    /// The public one-argument form is what the app calls, and it must answer
    /// in the app's language rather than the system's.
    func testTheDefaultFollowsTheAppsLanguage() {
        XCTAssertEqual(Quoted("Safari"), Quoted("Safari", language: AppLanguage.current))
    }
}
