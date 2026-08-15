import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// The basket row under the list: the count, «Clear the marks» and the
/// prominent trash button. It had no ladder — the count is `fixedSize` and
/// nothing else gave anything up, so at the narrowest pane the *prominent*
/// button truncated: «In den Papierkorb l…» on the control that deletes.
///
/// The same model `DuplicatesBarWidthTests` keeps for the toolbar above it:
/// real AppKit metrics, the shipped strings in all eight languages, thresholds
/// read from `DuplicatesLayout` itself.
final class TheBasketRowFitsThePaneTests: XCTestCase {

    private enum Key {
        static let clear = "Clear the marks"
        static let trash = "Move to Trash"
    }

    /// Mirrored from `DuplicatesSettingsPage.basketRow`:
    /// `HStack(spacing: HelmSpace.s5)` inside `.padding(.horizontal,
    /// HelmLayout.formInset)`, three children, two gaps, a zero-minimum spacer.
    private enum Chrome {
        static let total = HelmLayout.formInset * 2 + HelmSpace.s5 * 2
    }

    /// The count line at `HelmText.figureFont` — `Font.system(size: 11,
    /// design: .monospaced)` — with the figures a real library produces, the
    /// same ones `DuplicatesBarWidthTests` measures the toolbar's count with.
    private func countLine(_ language: AppLanguage) -> CGFloat {
        let line = HelmBasket.line(count: 12_345,
                                   size: HelmBytes.string(118_900_000_000,
                                                          language: language.rawValue),
                                   language: language)
        return (line as NSString).size(withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        ]).width
    }

    private func smallButton(_ title: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.sizeToFit()
        return button.fittingSize.width
    }

    /// The prominent button is a regular-size control.
    private func prominentButton(_ title: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.sizeToFit()
        return button.fittingSize.width
    }

    private func symbolControl(_ name: String) -> CGFloat {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.sizeToFit()
        return button.fittingSize.width
    }

    private func demand(in language: AppLanguage, clearLabelled: Bool) -> CGFloat {
        Chrome.total + countLine(language)
            + (clearLabelled ? smallButton(L(Key.clear, language: language))
                             : symbolControl("xmark.circle"))
            + prominentButton(L(Key.trash, language: language))
    }

    private func widest(clearLabelled: Bool) -> (AppLanguage, CGFloat) {
        AppLanguage.allCases
            .map { ($0, demand(in: $0, clearLabelled: clearLabelled)) }
            .max { $0.1 < $1.1 }!
    }

    /// The labelled rung against the threshold that draws it, with room to
    /// spare — a threshold below its own row switches that row *into* an
    /// overflow.
    func testTheLabelledRowFitsTheWidthThatLetsItThrough() {
        let (language, needs) = widest(clearLabelled: true)
        XCTAssertGreaterThan(DuplicatesLayout.basketWithClearLabel - needs, 20, """
            The full basket row needs \(Int(needs)) pt in \(language.rawValue) \
            and `basketWithClearLabel` draws it from \
            \(Int(DuplicatesLayout.basketWithClearLabel)).
            """)
    }

    /// The bottom rung answers to the narrowest pane there is: the smallest
    /// window with the sidebar dragged wide, which is where the audit caught
    /// the prominent button truncating.
    func testTheSymbolRowFitsTheNarrowestPaneInEveryLanguage() {
        let narrowestPane: CGFloat = 540
        let (language, needs) = widest(clearLabelled: false)
        XCTAssertLessThan(needs, narrowestPane - 20, """
            With the clear control as a symbol the row still needs \
            \(Int(needs)) pt in \(language.rawValue) against a \
            \(Int(narrowestPane)) pt pane — the count has to move instead.
            """)
    }

    /// The shipped row reads the rung this file measures, and its two buttons
    /// never truncate: the trash button is the one control on the page whose
    /// words must survive every width.
    func testTheShippedRowClimbsTheLadderMeasuredHere() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let opens = try XCTUnwrap(page.range(of: "private func basketRow"))
        let closes = try XCTUnwrap(page.range(of: "\n    }",
                                              range: opens.upperBound..<page.endIndex))
        let row = String(page[opens.lowerBound..<closes.upperBound])
        XCTAssertTrue(row.contains("labelsClear"), """
            The basket row does not read `DuplicatesLayout.labelsClear`, so the \
            rung measured here is a rung nothing climbs.
            """)
        XCTAssertTrue(row.contains(".fixedSize()"),
                      "the trash button compresses instead of the ladder giving way")
    }

    /// The strings measured here are the ones the row draws.
    func testTheStringsMeasuredHereAreTheOnesTheRowDraws() {
        XCTAssertEqual(DupStr.clearBasket, L(Key.clear, language: AppLanguage.current))
        XCTAssertEqual(DupStr.moveToTrash, L(Key.trash, language: AppLanguage.current))
        XCTAssertEqual(DupStr.basketLine(3, "1 GB"),
                       HelmBasket.line(count: 3, size: "1 GB"))
    }
}
