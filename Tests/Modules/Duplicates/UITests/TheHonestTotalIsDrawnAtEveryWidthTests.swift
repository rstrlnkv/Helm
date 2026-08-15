import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// The one clone-corrected total on the page is drawn at every width the
/// window opens at.
///
/// It used to be a toolbar item behind `DuplicatesLayout.showsCount`, whose
/// threshold — 1040 pt of pane, measured correctly — first passes at a 1290 pt
/// window: wider than the app ever opens. A threshold, a measured constant and
/// a test were all maintained to hide the figure at every reachable width. The
/// line lives under the floor note now, where a note already wraps, so the
/// whole apparatus went with it.
final class TheHonestTotalIsDrawnAtEveryWidthTests: XCTestCase {

    /// The count line as a real library produces it, in the font the page draws
    /// it in (`HelmText.rowDetail`, system 11).
    private func lineWidth(_ language: AppLanguage) -> CGFloat {
        let line = DupStr.found(12_345,
                                HelmBytes.string(118_900_000_000, language: language.rawValue),
                                language: language)
        return (line as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11),
        ]).width
    }

    /// The narrowest pane the settings window can produce, less the block's own
    /// insets — the figure `TheGroupHeaderKeepsItsButtonsTests` answers to.
    /// Measured 2026-08-15: the widest line is German at 324 pt, so the line
    /// holds a single row everywhere; `fixedSize(horizontal: false)` on it means
    /// even a language that grows past this wraps rather than clips.
    func testTheCountLineFitsTheNarrowestPaneInEveryLanguage() {
        let narrowestPane: CGFloat = 540
        for language in AppLanguage.allCases {
            XCTAssertLessThan(lineWidth(language), narrowestPane, """
                \(language.rawValue): the total line outgrew the narrowest pane — it \
                will wrap, which is worth knowing even though it no longer clips.
                """)
        }
    }

    /// The line is drawn beside the floor note — the block that already appears
    /// with every result — and not in the toolbar, where a width ladder had to
    /// hide it. Read from the page's source, because the claim is about where.
    func testTheTotalLivesUnderTheFloorNoteNotInTheToolbar() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let opens = try XCTUnwrap(page.range(of: "Text(DupStr.floorNote)"))
        let closes = try XCTUnwrap(page.range(of: "Divider()",
                                              range: opens.upperBound..<page.endIndex))
        let block = String(page[opens.lowerBound..<closes.lowerBound])
        XCTAssertTrue(block.contains("DupStr.found("), """
            The clone-corrected total is no longer drawn with the floor note, and \
            nothing else on the page draws it at every width.
            """)
    }
}
