import XCTest
@testable import HelmRuntime

/// How the cost of one scope is written down.
///
/// Separate from `FootprintTracker.Report.line` because the two answer different
/// questions at different scales. That one reports a **total** with a delta against
/// the last reading for the same label, in whole megabytes, and stays silent below
/// 8 MB — right for a leak hunt where the figures were hundreds of megabytes. This
/// one reports what a bounded piece of work cost, and building a module is single
/// digits: rendered by the other formatter, every one of the nine modules would
/// print `0 MB`, and thresholded by it, none of them would print at all.
final class ScopeCostTests: XCTestCase {

    private let mb = 1024 * 1024
    private let kb = 1024

    func testMegabytesKeepOneDecimal() {
        XCTAssertEqual(ScopeCost.line(grewBy: 3 * mb + 512 * kb), "+3.5 MB")
        XCTAssertEqual(ScopeCost.line(grewBy: 1 * mb + 800 * kb), "+1.8 MB")
    }

    /// The figure this exists for. Whole megabytes would call it zero, which reads
    /// as "measured and free" rather than "not measured finely enough".
    func testUnderAMegabyteIsKilobytesAndNotZero() {
        XCTAssertEqual(ScopeCost.line(grewBy: 640 * kb), "+640 KB")
        XCTAssertEqual(ScopeCost.line(grewBy: 40 * kb), "+40 KB")
    }

    /// Giving memory back is the interesting half: a module that costs 3 MB to
    /// switch on and returns nothing when switched off is the leak this whole
    /// instrument exists to catch.
    func testGivingItBackReadsAsNegative() {
        XCTAssertEqual(ScopeCost.line(grewBy: -(3 * mb + 100 * kb)), "-3.1 MB")
        XCTAssertEqual(ScopeCost.line(grewBy: -(256 * kb)), "-256 KB")
    }

    /// Not "0 KB" and not the empty string: a scope that cost nothing measurable
    /// is a fact worth stating plainly, and a bare zero in a log reads as a value
    /// that failed to be filled in.
    func testNoMeasurableChangeSaysSo() {
        XCTAssertEqual(ScopeCost.line(grewBy: 0), "unchanged")
        XCTAssertEqual(ScopeCost.line(grewBy: 200), "unchanged")
        XCTAssertEqual(ScopeCost.line(grewBy: -200), "unchanged")
    }

    /// The boundary between the two units, stated so it cannot drift.
    func testTheBoundaryIsOneMegabyte() {
        XCTAssertEqual(ScopeCost.line(grewBy: 1023 * kb), "+1023 KB")
        XCTAssertEqual(ScopeCost.line(grewBy: 1 * mb), "+1.0 MB")
    }

    /// Rounding does not turn a real cost into no cost.
    func testASmallCostNeverRoundsAwayToUnchanged() {
        for bytes in [1 * kb, 2 * kb, 10 * kb] {
            XCTAssertNotEqual(ScopeCost.line(grewBy: bytes), "unchanged",
                              "\(bytes) bytes disappeared from the log")
        }
    }
}
