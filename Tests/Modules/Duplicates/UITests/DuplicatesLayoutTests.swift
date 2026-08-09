import XCTest
@testable import Module_Duplicates_UI

/// The ladder, as numbers rather than as a feeling.
///
/// The pane is the window's content less the fixed 250 pt sidebar: **810 pt at
/// the default 1060 pt window, 610 at the 860 pt minimum**. Every rung below
/// names the language that sets it and what that rung was measured at;
/// `DuplicatesBarWidthTests` takes those measurements again from the shipped
/// strings, so what lives here are pins on the thresholds, not the measurement.
final class DuplicatesLayoutTests: XCTestCase {

    private func pane(ofWindow width: CGFloat) -> DuplicatesLayout {
        DuplicatesLayout(availableWidth: width - 250)
    }

    // MARK: - The two windows a person actually gets

    /// The defect this ladder exists for. The row wanted 977 pt in German at
    /// the size the window *opens* at, where the pane is 810 — so the page was
    /// clipped at both ends out of the box in seven of the eight languages, and
    /// the narrow window the bug was reported against only made it obvious.
    func testTheDefaultWindowKeepsEveryLabelAndDropsTheCount() {
        let layout = pane(ofWindow: 1060)
        XCTAssertFalse(layout.showsCount)
        XCTAssertTrue(layout.labelsMarkAll)
        XCTAssertTrue(layout.labelsSearch)
    }

    /// At the narrowest window the labels go and the controls stay. 502 pt in
    /// French for path, one labelled control and two symbols — inside 610 with
    /// room, which is what "no control ever disappears" costs.
    func testTheSmallestWindowKeepsBothControlsAsSymbols() {
        let layout = pane(ofWindow: 860)
        XCTAssertFalse(layout.showsCount)
        XCTAssertFalse(layout.labelsMarkAll)
        XCTAssertFalse(layout.labelsSearch)
    }

    // MARK: - A threshold each

    /// German, 1000.3 pt: `Gruppen: 12345 · 118,9 GB nach dem Leeren des
    /// Papierkorbs` beside three labelled controls. Measured with a count a
    /// photo library really produces — at "12 groups, 18,9 MB" the same row is
    /// 977.5, and a threshold set from that number would clip the moment the
    /// figures grew.
    func testTheCountArrivesOnlyAboveWhatTheGermanCountLineNeeds() {
        XCTAssertFalse(DuplicatesLayout(availableWidth: 1039).showsCount)
        XCTAssertTrue(DuplicatesLayout(availableWidth: 1040).showsCount)
    }

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
    /// threshold below its own row is the whole defect: `barWithCount` was 760
    /// for a row that needed 977, so crossing it switched the count *into* an
    /// overflow.
    func testNoThresholdIsBelowTheRowItLetsThrough() {
        let rows: [(String, CGFloat, (DuplicatesLayout) -> Bool)] = [
            ("count + three labels, de", 1000.3, { $0.showsCount }),
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
    /// the count says what the list beneath it says group by group, the
    /// mark-all label says what every group header says, and `Search again`
    /// keeps its label longest because nothing else on the page carries it.
    func testTheCountGoesFirstThenTheMarkAllLabelThenTheSearchLabel() {
        for width in stride(from: 0.0, through: 1400.0, by: 2.5) {
            let layout = DuplicatesLayout(availableWidth: width)
            if layout.showsCount {
                XCTAssertTrue(layout.labelsMarkAll,
                              "at \(width) pt the count outlived the mark-all label")
            }
            if layout.labelsMarkAll {
                XCTAssertTrue(layout.labelsSearch,
                              "at \(width) pt the mark-all label outlived the search label")
            }
        }
    }

    /// A pane is zero wide for a frame during a window resize.
    func testNothingIsShownAtNoWidthAndNothingCrashes() {
        let none = DuplicatesLayout(availableWidth: 0)
        XCTAssertFalse(none.showsCount)
        XCTAssertFalse(none.labelsMarkAll)
        XCTAssertFalse(none.labelsSearch)
    }

    func testAVeryWideWindowShowsEverything() {
        let wide = pane(ofWindow: 2400)
        XCTAssertTrue(wide.showsCount)
        XCTAssertTrue(wide.labelsMarkAll)
        XCTAssertTrue(wide.labelsSearch)
    }
}
