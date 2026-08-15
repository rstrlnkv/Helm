import XCTest
import HelmContract
@testable import HelmUI

/// The tour is generated from what the descriptors already say. These assert
/// the generation, not the wording: the wording belongs to each module and is
/// tested where it lives.
final class WelcomeStepsTests: XCTestCase {
    private func metadata(_ name: String, offering offer: String? = nil) -> ModuleMetadata {
        ModuleMetadata(id: ModuleID(rawValue: name.lowercased()), name: name,
                       summary: "what \(name) does", sfSymbol: "circle", welcomeOffer: offer)
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
    /// `L(_:language:)` names the language outright, which is the only way to
    /// see a shipped table with a hole in it.
    ///
    /// Asks the `.lproj` files the same way the app does — through `L()` — not
    /// through named `…English`/`…Table` constants: those existed only so this
    /// test could walk them, and went with them. Keep this list in step with
    /// `WelcomeStrings.swift`: a string added there and not here is a string
    /// nobody checks.
    func testEveryChromeStringExistsInEveryLanguage() {
        let english = [
            "windowTitle": "Welcome to Helm",
            "introTitle": "Tools for your Mac",
            "introBody": "Helm is made of modules. Each one does a single job, and you can switch off the ones you do not want.",
            "back": "Back",
            "next": "Next",
            "skip": "Skip",
            "done": "Done",
        ]
        for (name, base) in english {
            for language in AppLanguage.allCases where language != .en {
                let value = L(base, language: language)
                XCTAssertFalse(value.isEmpty, "\(name) is empty in \(language.rawValue)")
                XCTAssertNotEqual(value, base,
                                  "\(name) fell back to English in \(language.rawValue)")
            }
        }
    }

    /// The intro is a showcase: it carries every module's symbol, in registry
    /// order, so the first screen can show what the app is made of.
    func testTheIntroCarriesEveryModuleSymbolInOrder() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        XCTAssertEqual(steps[0].moduleSymbols, ["circle", "circle"])
        XCTAssertTrue(steps[1].moduleSymbols.isEmpty, "module steps are not showcases")
    }

    /// **A step may offer one thing to set up, and the offer is the module's
    /// own.** A tour that could take somebody somewhere would otherwise need a
    /// list of which module has something worth setting up — the tenth
    /// hand-written list of module ids in this app, and the one nothing would
    /// fail on when it went stale. The descriptor says it instead, beside the
    /// name and the summary the step is already built from.
    func testAStepCarriesTheOfferItsModuleMakes() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha", offering: "Set Alpha up"),
                                              metadata("Beta")])
        XCTAssertEqual(steps[1].offer, "Set Alpha up")
        XCTAssertNil(steps[2].offer, "a module that offers nothing gets no button")
        XCTAssertNil(steps[0].offer, "the intro is not a module")
    }

    /// A module step has to know which module it is, or its switch cannot be
    /// bound to anything. The intro is not a module and carries nil.
    func testModuleStepsCarryTheirIDAndTheIntroDoesNot() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        XCTAssertNil(steps[0].moduleID)
        XCTAssertEqual(steps[1].moduleID, "alpha")
        XCTAssertEqual(steps[2].moduleID, "beta")
    }
}
