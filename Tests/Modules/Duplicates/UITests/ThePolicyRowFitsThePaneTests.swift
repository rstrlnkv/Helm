import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The policy row is a sentence with a pop-up in the middle of it, and a
/// sentence is the thing that grows most between languages.
///
/// It is measured the way `DuplicatesBarWidthTests` measures the toolbar: real
/// AppKit metrics against the shipped strings, in all eight languages named
/// outright — this machine's language is Russian, so a check that read
/// `AppLanguage.current` would measure one language eight times. Not a render:
/// a test that needs a window server is green here and absent on the next
/// machine.
///
/// **The row gives nothing up, and that is the claim under test.** The toolbar
/// above it drops a count and then two labels as the pane narrows, because what
/// it drops is said again elsewhere on the page. Nothing here is said twice: the
/// label is half a sentence and the pop-up is the other half. So it has to fit
/// the narrowest pane there is, in every language, and the guard is that it
/// does — with room to spare, since this is a model of a drawn row rather than
/// the drawing.
final class ThePolicyRowFitsThePaneTests: XCTestCase {

    /// The English of the one string the row measures, so that what is measured
    /// here and what the page draws cannot drift apart in silence — the shape
    /// `DuplicatesBarWidthTests` already keeps, and the English is the key.
    private enum Key {
        static let extraCopyIs = "An extra copy is"
    }

    /// The pane is the window's content less the sidebar, and **the sidebar is
    /// the person's to drag** — `SettingsWindow` opens the window at 1060 and
    /// refuses to go below 860, and the sidebar defaults to 214 within 180…320.
    ///
    /// So the pane a page opens on is 846, and the narrowest one that can be
    /// produced at all is 540: the smallest window with the sidebar dragged
    /// wide. Measuring against `window − 214` alone would leave 106 pt of the
    /// row unaccounted for, which is more than any of these strings has to
    /// spare.
    private enum Pane {
        static let atTheDefaultWindow: CGFloat = 1060 - 214
        static let atTheNarrowestItCanBe: CGFloat = 860 - 320
    }

    /// Mirrored from `DuplicatesSettingsPage.policyRow`: `HStack(spacing: 8)`
    /// and `.padding(.horizontal, HelmLayout.formInset)`.
    private enum Chrome {
        static let spacing: CGFloat = 8
        static let padding = HelmLayout.formInset
        static let total = padding * 2 + spacing
    }

    private func labelWidth(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]).width
    }

    /// What the row asks for in one language: the label, the pop-up at the width
    /// `HelmPickerWidth` gives it, and the chrome around them.
    ///
    /// The pop-up's width is taken from the same call the page makes rather than
    /// from a number here: a width test holding its own copy of the width goes on
    /// passing whatever the page starts drawing.
    private func demand(in language: AppLanguage) -> CGFloat {
        Chrome.total + labelWidth(L(Key.extraCopyIs, language: language))
            + DuplicatesLayout.policyPickerWidth(language: language)
    }

    private func widest() -> (AppLanguage, CGFloat) {
        AppLanguage.allCases.map { ($0, demand(in: $0)) }.max { $0.1 < $1.1 }!
    }

    func testTheRowFitsTheNarrowestPaneInEveryLanguage() {
        let (language, needs) = widest()
        XCTAssertLessThan(needs, Pane.atTheNarrowestItCanBe - 20, """
            The policy row needs \(Int(needs)) pt in \(language.rawValue) and the \
            narrowest pane is \(Int(Pane.atTheNarrowestItCanBe)). It gives nothing \
            up as it narrows, so a row that does not fit here clips — shorten the \
            strings or give the row a ladder like the toolbar's.
            """)
    }

    /// And the pane the page actually opens on. Separate from the assertion
    /// above so a failure says which of the two it is: a row that fits 846 and
    /// not 540 is a ladder to write, a row that fits neither is a string to
    /// shorten.
    func testTheRowFitsTheDefaultWindowInEveryLanguage() {
        let (language, needs) = widest()
        XCTAssertLessThan(needs, Pane.atTheDefaultWindow - 20,
                          "\(Int(needs)) pt in \(language.rawValue)")
    }

    /// The pop-up is as wide as its widest label, so it is the half of the row
    /// that moves. Recorded because it is what makes the row's own width worth
    /// measuring rather than assuming.
    func testThePickerIsWiderThanTheLabelInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertGreaterThan(DuplicatesLayout.policyPickerWidth(language: language),
                                 labelWidth(L(Key.extraCopyIs, language: language)),
                                 "\(language.rawValue)")
        }
    }

    /// What is measured here is what the page draws. The English is the key, so
    /// a reworded label would leave this file measuring a key that no longer
    /// exists — and reporting the English width for all eight languages.
    func testTheStringMeasuredHereIsTheOneThePageDraws() {
        XCTAssertEqual(DupStr.extraCopyIs,
                       L(Key.extraCopyIs, language: AppLanguage.current))
    }

    /// The row draws the label and the pop-up and nothing else — the check that
    /// caught the toolbar measuring two of its three controls.
    func testTheRowIsMadeOfThePartsMeasuredHere() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let opens = try XCTUnwrap(page.range(of: "private var policyRow:"))
        // The next section, whichever it is, so that a section inserted after
        // this one does not quietly widen what this check reads.
        let closes = try XCTUnwrap(page.range(of: "// MARK: -",
                                              range: opens.upperBound..<page.endIndex))
        let row = String(page[opens.lowerBound..<closes.lowerBound])
        XCTAssertTrue(row.contains("HStack(spacing: \(Int(Chrome.spacing)))"),
                      "the row body was not found — this check reads nothing")

        var drawn = Set<String>()
        var rest = Substring(row)
        while let hit = rest.range(of: "DupStr.") {
            let after = rest[hit.upperBound...]
            drawn.insert(String(after.prefix(while: { $0.isLetter })))
            rest = after
        }
        XCTAssertEqual(drawn, ["extraCopyIs", "policyName"], """
            The policy row draws a string this measurement does not account for, \
            or has stopped drawing one it does.
            """)
    }
}
