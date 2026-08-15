import XCTest
@testable import Module_Duplicates_UI

/// The ladder, as numbers rather than as a feeling.
///
/// The pane is the window's content less the fixed 250 pt sidebar: **810 pt at
/// the default 1060 pt window, 610 at the 860 pt minimum**. Every rung below
/// names the language that sets it and what that rung was measured at;
/// `DuplicatesBarWidthTests` takes those measurements again from the shipped
/// strings, so what lives here are pins on the thresholds, not the measurement.
///
/// There is no count rung any more: the clone-corrected total moved under the
/// floor note, where it is drawn at every width —
/// `TheHonestTotalIsDrawnAtEveryWidthTests` holds that, and holds that the line
/// fits the narrowest pane in all eight languages.
final class DuplicatesLayoutTests: XCTestCase {

    private func pane(ofWindow width: CGFloat) -> DuplicatesLayout {
        DuplicatesLayout(availableWidth: width - 250)
    }

    // MARK: - The two windows a person actually gets

    /// The defect this ladder exists for. The row wanted 977 pt in German at
    /// the size the window *opens* at, where the pane is 810 — so the page was
    /// clipped at both ends out of the box in seven of the eight languages, and
    /// the narrow window the bug was reported against only made it obvious.
    func testTheDefaultWindowKeepsEveryLabel() {
        let layout = pane(ofWindow: 1060)
        XCTAssertTrue(layout.labelsMarkAll)
        XCTAssertTrue(layout.labelsSearch)
    }

    /// At the narrowest window the labels go and the controls stay. 502 pt in
    /// French for path, one labelled control and two symbols — inside 610 with
    /// room, which is what "no control ever disappears" costs.
    func testTheSmallestWindowKeepsBothControlsAsSymbols() {
        let layout = pane(ofWindow: 860)
        XCTAssertFalse(layout.labelsMarkAll)
        XCTAssertFalse(layout.labelsSearch)
    }

    // MARK: - A threshold each

    /// French, 721.0 pt: path, `Choisir un autre dossier`, `Rechercher à
    /// nouveau`, `Marquer toutes les copies en trop`.
    func testTheMarkAllLabelArrivesOnlyAboveWhatTheFrenchRowNeeds() {
        XCTAssertFalse(DuplicatesLayout(availableWidth: 759).labelsMarkAll)
        XCTAssertTrue(DuplicatesLayout(availableWidth: 760).labelsMarkAll)
    }

    /// French again, 607.0 pt: the same row with mark-all reduced to its symbol.
    func testTheSearchLabelArrivesOnlyAboveWhatTheFrenchRowNeeds() {
        XCTAssertFalse(DuplicatesLayout(availableWidth: 659).labelsSearch)
        XCTAssertTrue(DuplicatesLayout(availableWidth: 660).labelsSearch)
    }

    /// The measurements, against the thresholds that let each row through. A
    /// threshold below its own row is the whole defect this ladder replaced:
    /// crossing one switched its row *into* an overflow.
    func testNoThresholdIsBelowTheRowItLetsThrough() {
        let rows: [(String, CGFloat, (DuplicatesLayout) -> Bool)] = [
            ("three labels, fr", 721.0, { $0.labelsMarkAll }),
            ("mark-all as a symbol, fr", 607.0, { $0.labelsSearch }),
        ]
        for (row, needs, shown) in rows {
            XCTAssertFalse(shown(DuplicatesLayout(availableWidth: needs - 0.5)),
                           "\(row) is drawn at \(needs - 0.5) pt, where it needs \(needs)")
        }
    }

    // MARK: - The order things are given up in

    /// Take a label before a control, and take what repeats the screen first:
    /// the mark-all label says what every group header says, and `Search again`
    /// keeps its label longest because nothing else on the page carries it.
    func testTheMarkAllLabelGoesBeforeTheSearchLabel() {
        for width in stride(from: 0.0, through: 1400.0, by: 2.5) {
            let layout = DuplicatesLayout(availableWidth: width)
            if layout.labelsMarkAll {
                XCTAssertTrue(layout.labelsSearch,
                              "at \(width) pt the mark-all label outlived the search label")
            }
        }
    }

    /// A pane is zero wide for a frame during a window resize.
    func testNothingIsShownAtNoWidthAndNothingCrashes() {
        let none = DuplicatesLayout(availableWidth: 0)
        XCTAssertFalse(none.labelsMarkAll)
        XCTAssertFalse(none.labelsSearch)
    }

    func testAVeryWideWindowShowsEverything() {
        let wide = pane(ofWindow: 2400)
        XCTAssertTrue(wide.labelsMarkAll)
        XCTAssertTrue(wide.labelsSearch)
    }
}
