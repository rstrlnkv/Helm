import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_UI

/// The words for Apple's installer are Apple's, not this app's: the person
/// reads them in Apple's window, and a second name for the same thing here
/// reads as a second thing. So they are read out of Apple's own bundle — the
/// alert's sentence for the tools' name, the menu's button title for «Install» —
/// and held to it, in the region `zh.lproj` and `pt.lproj` stand for.
///
/// **This reads a system bundle, and the subject must have happened.** A test
/// that finds nothing to compare and compares nothing passes; here a missing
/// bundle is a failure, so the guard cannot go green over an empty read.
final class TheToolsAreNamedAsAppleNamesThemTests: XCTestCase {

    private static let resources =
        "/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources"

    /// Helm's `zh.lproj` is Simplified script and its `pt.lproj` Brazilian
    /// wording (`arquivo`, `baixar`, `senha`), which are Apple's `zh_CN` and
    /// `pt_BR`.
    private static let appleRegion: [AppLanguage: String] = [
        .en: "en", .ru: "ru", .es: "es", .fr: "fr", .de: "de", .ja: "ja", .zh: "zh_CN", .pt: "pt_BR"
    ]

    /// The table's rows are dictionaries of strings, but the file also carries a
    /// provenance row of numbers, so it is read as `Any` and each value is kept
    /// only if it is text.
    private func loctable(_ name: String) throws -> [String: [String: String]] {
        let path = Self.resources + "/" + name + ".loctable"
        let raw = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: [String: Any]],
                                "Apple's \(name).loctable could not be read at \(path)")
        XCTAssertGreaterThan(raw.count, 20, "\(name).loctable carries almost nothing")
        return raw.mapValues { $0.compactMapValues { $0 as? String } }
    }

    /// The tools' name is the noun phrase Apple's own alert uses.
    func testTheNameIsTheOneInApplesAlert() throws {
        let alert = try loctable("Localizable")
        for language in AppLanguage.allCases {
            let region = try XCTUnwrap(Self.appleRegion[language])
            let sentence = try XCTUnwrap(alert[region]?["ALERT_INFORMATIVE_STRING"],
                                         "Apple's alert has no sentence for \(region)")
            XCTAssertTrue(sentence.contains(HbStr.appleTools(language: language)),
                          "\(language.rawValue): «\(HbStr.appleTools(language: language))» is not in Apple's own sentence «\(sentence)»")
        }
    }

    /// «Install» is the word on Apple's button — the menu table's title — and
    /// this app's own «Install» in the same language, so the sentence that names
    /// the button interpolates the one string and types nothing.
    func testTheInstallButtonIsTheWordOnApplesButton() throws {
        let menu = try loctable("MainMenu")
        let alert = try loctable("Localizable")
        for language in AppLanguage.allCases where language != .en {
            let region = try XCTUnwrap(Self.appleRegion[language])
            let title = try XCTUnwrap(menu[region]?["801.title"], "Apple's menu has no button title for \(region)")
            XCTAssertEqual(L("Install", language: language), title,
                           "\(language.rawValue): this app's «Install» is not the word on Apple's button")
            XCTAssertTrue(alert[region]?["ALERT_INFORMATIVE_STRING"]?.contains(title) ?? false,
                          "\(language.rawValue): Apple's own sentence does not name its button «\(title)»")
        }
        // English has no row in the menu table (the nib's own text is the
        // English); Apple's sentence names the button in the same word.
        XCTAssertTrue(alert["en"]?["ALERT_INFORMATIVE_STRING"]?.contains(L("Install", language: .en)) ?? false)
    }
}
