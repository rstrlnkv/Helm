import XCTest
@testable import Module_Homebrew_UI

/// The width threshold, as a number rather than as a feeling.
///
/// 544 pt measured (`HomebrewSplit`'s own doc comment carries the render); the
/// threshold sits with slack above it.
final class HomebrewSplitTests: XCTestCase {

    func testTheInspectorGoesAtTheNarrowestSettingsPane() {
        // 490 pt is the settings window's own minimum pane
        // (`HostsRowsFitTheMinimumPaneTests.narrowest`) — well under the split.
        XCTAssertFalse(HomebrewSplit(availableWidth: 490).showsInspector)
    }

    func testTheInspectorIsThereAtTheDefaultWindow() {
        // 834 pt is the pane at the settings window's default width.
        XCTAssertTrue(HomebrewSplit(availableWidth: 834).showsInspector)
    }

    func testTheThresholdIsWhereTheMeasurementPutIt() {
        XCTAssertFalse(HomebrewSplit(availableWidth: 543).showsInspector)
        XCTAssertTrue(HomebrewSplit(availableWidth: 560).showsInspector)
    }

    /// A pane can be zero wide for a frame during a window resize.
    func testNothingCrashesAtNoWidth() {
        XCTAssertFalse(HomebrewSplit(availableWidth: 0).showsInspector)
    }
}
