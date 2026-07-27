import XCTest
@testable import Module_Disk_UI

/// The width thresholds, as numbers rather than as a feeling.
///
/// The measurements behind them (real font metrics, not arithmetic on
/// estimates): the ring column needs 328 pt, a comfortable list 316, the bar
/// 640 without the scan statement and 788 with it. The settings window is 940
/// wide by default and 860 at its minimum, less a 250 pt sidebar — so the
/// detail pane is 690 normally and 610 at the minimum.
final class DiskLayoutTests: XCTestCase {

    private func detail(forWindow width: CGFloat) -> DiskLayout {
        DiskLayout(availableWidth: width - 250)   // the sidebar's fixed share
    }

    /// The case that started this: at the smallest window the pair does not
    /// fit, so the ring goes and the list gets the pane.
    func testTheRingGoesAtTheSmallestWindow() {
        XCTAssertFalse(detail(forWindow: 860).showsRing)
    }

    func testTheRingIsThereAtTheDefaultWindow() {
        XCTAssertTrue(detail(forWindow: 940).showsRing)
    }

    /// 645 pt measured for the pair; the threshold sits just above it.
    func testTheRingThresholdIsWhereTheMeasurementPutIt() {
        XCTAssertFalse(DiskLayout(availableWidth: 645).showsRing)
        XCTAssertTrue(DiskLayout(availableWidth: 660).showsRing)
    }

    /// 788 pt measured for the full bar. The default window's 690 is not
    /// enough — which is why hiding the statement had to be a rule and not a
    /// one-off trim.
    func testTheScanStatementNeedsAWiderWindowThanTheDefault() {
        XCTAssertFalse(detail(forWindow: 940).showsScanStatement)
        XCTAssertTrue(detail(forWindow: 1100).showsScanStatement)
    }

    /// The statement goes before the ring does: it is neither the path nor a
    /// control, and it is the widest item in the row.
    func testTheSentenceIsGivenUpBeforeTheRing() {
        for width in stride(from: 400.0, through: 1200.0, by: 5) {
            let layout = DiskLayout(availableWidth: width)
            if layout.showsScanStatement {
                XCTAssertTrue(layout.showsRing,
                              "at \(width) pt the sentence survived the ring")
            }
        }
    }

    /// A pane can be zero wide for a frame during a window resize.
    func testNothingIsShownAtNoWidthAndNothingCrashes() {
        let none = DiskLayout(availableWidth: 0)
        XCTAssertFalse(none.showsRing)
        XCTAssertFalse(none.showsScanStatement)
    }

    func testAVeryWideWindowShowsEverything() {
        let wide = detail(forWindow: 2400)
        XCTAssertTrue(wide.showsRing)
        XCTAssertTrue(wide.showsScanStatement)
    }
}
