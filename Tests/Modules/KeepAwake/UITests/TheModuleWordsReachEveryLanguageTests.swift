import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_KeepAwake_UI

/// The module's catalog is compiled into the module's own bundle, and `KAStr` asks that bundle in
/// the app's language — not the language macOS resolves for the process, which is what `String(localized:)` answers by default.
///
/// The catalog guards in `Tests/HelmUITests` read the *file*; none of them can show that the words
/// come out of the built target in the language asked for. This does, in all eight: a lookup that
/// fell back to English (a language code the bundle does not match, a bundle that did not load)
/// reads correctly in English and fails here in the other seven, where English would pass every
/// file-reading guard.
final class TheModuleWordsReachEveryLanguageTests: XCTestCase {

    private func catalog() throws -> ModuleCatalogs.Catalog {
        try XCTUnwrap(ModuleCatalogs.all().first { $0.module == "KeepAwake" },
                      "Keep Awake has no catalog")
    }

    func testEachWordComesOutOfTheBundleInTheLanguageAsked() throws {
        let strings = try catalog().strings
        let words: [(String, () -> String)] = [
            ("keepAwake", { KAStr.moduleName }),
            ("summary", { KAStr.summary }),
            ("customDuration", { KAStr.customTimeTitle }),
            ("other", { KAStr.customTime }),
            ("done", { KAStr.done }),
        ]
        var differs = 0
        AppLanguage.each { language in
            for (symbol, word) in words {
                let expected = strings[symbol]?[language.rawValue]
                XCTAssertEqual(word(), expected, "\(symbol) in \(language.rawValue)")
                if language != .en, expected != strings[symbol]?["en"] { differs += 1 }
            }
        }
        XCTAssertGreaterThan(differs, 0, "no word differs from its English, so a fallback to English would pass")
    }

    /// A word other modules draw too stays in the kit and `KAStr` reads it through `L()`.
    func testASharedWordStillComesFromTheKit() {
        AppLanguage.only(.ru) { XCTAssertEqual(KAStr.timer, "Таймер") }
    }
}
