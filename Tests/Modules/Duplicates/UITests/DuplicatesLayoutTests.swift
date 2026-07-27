import XCTest
@testable import Module_Duplicates_UI

/// The thresholds `Scripts/layout/measure-duplicates-bar.swift` printed, pinned
/// so a later edit to the row cannot quietly move them.
final class DuplicatesLayoutTests: XCTestCase {

    /// The settings window's detail pane: 690 pt at the default window, 610 at
    /// its minimum. Neither holds the count — which is the point of measuring
    /// rather than assuming the wide case.
    func testTheCountGoesInThePaneItDoesNotFit() {
        XCTAssertFalse(DuplicatesLayout(availableWidth: 610).showsCount)
        XCTAssertFalse(DuplicatesLayout(availableWidth: 690).showsCount)
    }

    func testTheCountStaysWhereThereIsRoom() {
        XCTAssertTrue(DuplicatesLayout(availableWidth: 760).showsCount)
        XCTAssertTrue(DuplicatesLayout(availableWidth: 1100).showsCount)
    }

    /// The measured requirement is 738 pt; the threshold carries slack over it
    /// and must never sit below it.
    func testTheThresholdIsNotBelowWhatWasMeasured() {
        XCTAssertFalse(DuplicatesLayout(availableWidth: 737).showsCount)
    }
}
