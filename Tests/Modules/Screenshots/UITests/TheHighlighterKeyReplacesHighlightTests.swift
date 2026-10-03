import HelmTestSupport
import XCTest

/// **The marker's name is the key `Highlighter` in all eight languages and
/// the old key `Highlight` is gone** — the tables and the code that asks.
/// Reads the files, not a language: this Mac speaks one of the eight.
final class TheHighlighterKeyReplacesHighlightTests: XCTestCase {

    private let languages = ["de", "en", "es", "fr", "ja", "pt", "ru", "zh"]

    func testTheKeyIsInEveryTableAndTheOldOneIsNot() throws {
        for language in languages {
            let lines = try RepoSource.lines(of: "Sources/HelmUI/Resources/\(language).lproj/Localizable.strings")
            XCTAssertGreaterThan(lines.count, 100, "\(language) table was not read")
            let hasNew = lines.contains { $0.hasPrefix("\"Highlighter\" = \"") && !$0.hasPrefix("\"Highlighter\" = \"\"") }
            XCTAssertTrue(hasNew, "\(language): \"Highlighter\" missing")
            XCTAssertFalse(lines.contains { $0.hasPrefix("\"Highlight\" =") }, "\(language): \"Highlight\" still there")
        }
    }

    func testTheCodeAsksForTheNewKey() throws {
        let code = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenshotsStrings.swift")
        XCTAssertTrue(code.contains("L(\"Highlighter\")"))
        XCTAssertFalse(code.contains("L(\"Highlight\")"))
    }
}
