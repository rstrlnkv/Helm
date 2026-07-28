import XCTest
@testable import HelmRuntime

/// The log answers "what did that cost", which is a delta, not a total. A total
/// on its own was what the app already had: 15 MB at launch, half a gigabyte
/// later, and nothing in between saying which operation stood between them.
final class FootprintTrackerTests: XCTestCase {

    private let mb = 1024 * 1024

    func testTheFirstReadingForALabelIsAlwaysWorthALine() {
        var tracker = FootprintTracker()
        let report = tracker.report("launch", bytes: 15 * mb)
        XCTAssertEqual(report?.bytes, 15 * mb)
        XCTAssertNil(report?.delta, "there is nothing to be a delta against yet")
        XCTAssertEqual(report?.line, "15 MB")
    }

    func testAChangeBelowTheThresholdSaysNothing() {
        var tracker = FootprintTracker(threshold: 8 * mb)
        _ = tracker.report("idle", bytes: 100 * mb)
        XCTAssertNil(tracker.report("idle", bytes: 104 * mb))
        XCTAssertNil(tracker.report("idle", bytes: 97 * mb))
    }

    func testAChangeAtOrAboveTheThresholdIsReportedWithItsDelta() {
        var tracker = FootprintTracker(threshold: 8 * mb)
        _ = tracker.report("leftovers.scan", bytes: 40 * mb)
        let report = tracker.report("leftovers.scan", bytes: 78 * mb)
        XCTAssertEqual(report?.delta, 38 * mb)
        XCTAssertEqual(report?.line, "78 MB (+38 MB)")
    }

    /// Memory coming back matters as much as memory going: a scan that frees
    /// what it took is the shape a leak does not have.
    func testAFallIsReportedTooAndReadsAsAFall() {
        var tracker = FootprintTracker(threshold: 8 * mb)
        _ = tracker.report("disk.scan", bytes: 300 * mb)
        XCTAssertEqual(tracker.report("disk.scan", bytes: 120 * mb)?.line, "120 MB (-180 MB)")
    }

    /// Each label carries its own baseline, or a scan would be measured against
    /// whatever the idle timer happened to read a second earlier.
    func testLabelsDoNotShareABaseline() {
        var tracker = FootprintTracker(threshold: 8 * mb)
        _ = tracker.report("idle", bytes: 100 * mb)
        let first = tracker.report("disk.scan", bytes: 100 * mb)
        XCTAssertNil(first?.delta, "a label's first reading is its own baseline")
        XCTAssertNil(tracker.report("idle", bytes: 101 * mb))
    }

    /// The threshold is measured from the last reported reading, not from the
    /// last one that crossed it — otherwise a drift of 7 MB every quarter of an
    /// hour is invisible forever, which is exactly the shape being hunted.
    func testDriftAccumulatesUntilItCrosses() {
        var tracker = FootprintTracker(threshold: 8 * mb)
        _ = tracker.report("idle", bytes: 100 * mb)
        XCTAssertNil(tracker.report("idle", bytes: 107 * mb))
        XCTAssertNotNil(tracker.report("idle", bytes: 115 * mb),
                        "115 is 15 above the last reported 100")
    }

    func testTheRealFootprintIsReadable() throws {
        let bytes = try XCTUnwrap(MemoryFootprint.current(), "task_info declined")
        XCTAssertGreaterThan(bytes, 1024 * 1024, "a running test process costs more than a megabyte")
    }
}
