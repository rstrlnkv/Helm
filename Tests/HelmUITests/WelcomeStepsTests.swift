import XCTest
import HelmContract
@testable import HelmUI

/// The tour is generated from what the descriptors already say. These assert
/// the generation, not the wording: the wording belongs to each module and is
/// tested where it lives.
final class WelcomeStepsTests: XCTestCase {
    private func metadata(_ name: String) -> ModuleMetadata {
        ModuleMetadata(id: ModuleID(rawValue: name.lowercased()), name: name,
                       summary: "what \(name) does", sfSymbol: "circle")
    }

    func testEveryModuleGetsOneStepAfterTheIntro() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        XCTAssertEqual(steps.count, 3, "an intro step plus one per module")
        XCTAssertEqual(steps[1].title, "Alpha")
        XCTAssertEqual(steps[2].title, "Beta")
    }

    func testTheIntroComesFirstAndIsNotAModule() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha")])
        XCTAssertEqual(steps[0].title, WelcomeStr.introTitle)
        XCTAssertEqual(steps[0].body, WelcomeStr.introBody)
    }

    func testAModuleStepCarriesItsSummaryAndSymbol() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha")])
        XCTAssertEqual(steps[1].body, "what Alpha does")
        XCTAssertEqual(steps[1].sfSymbol, "circle")
    }

    func testNoStepIsEmpty() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        for step in steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.body.isEmpty)
            XCTAssertFalse(step.sfSymbol.isEmpty)
        }
    }

    /// The suite runs in this machine's language, so a test that reads
    /// `AppLanguage.current` checks English eight times and calls it coverage.
    /// `L(_:_:language:)` names the language outright, which is the only way to
    /// see a table with a hole in it.
    ///
    /// The tables are read off `WelcomeStr` by name rather than through its
    /// accessors, because the accessors resolve `.current` internally — asking
    /// them in a loop over languages asks the same question eight times. Keep
    /// this list in step with `WelcomeStrings.swift`: a string added there and
    /// not here is a string nobody checks.
    func testEveryChromeStringExistsInEveryLanguage() {
        let tables: [(String, String, [AppLanguage: String])] = [
            ("windowTitle", WelcomeStr.windowTitleEnglish, WelcomeStr.windowTitleTable),
            ("introTitle", WelcomeStr.introTitleEnglish, WelcomeStr.introTitleTable),
            ("introBody", WelcomeStr.introBodyEnglish, WelcomeStr.introBodyTable),
            ("back", WelcomeStr.backEnglish, WelcomeStr.backTable),
            ("next", WelcomeStr.nextEnglish, WelcomeStr.nextTable),
            ("skip", WelcomeStr.skipEnglish, WelcomeStr.skipTable),
            ("done", WelcomeStr.doneEnglish, WelcomeStr.doneTable),
        ]
        for (name, english, table) in tables {
            for language in AppLanguage.allCases where language != .en {
                let value = L(english, table, language: language)
                XCTAssertFalse(value.isEmpty, "\(name) is empty in \(language.rawValue)")
                XCTAssertNotEqual(value, english,
                                  "\(name) fell back to English in \(language.rawValue)")
            }
        }
    }
}
