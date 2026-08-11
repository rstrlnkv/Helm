import XCTest

/// The wait before the first partial snapshot arrives.
///
/// Duplicates draws the identical event — a walk of somebody's files that has
/// not produced anything to show yet — with `HelmBusyState`: a small spinner
/// and a ten-point caption. Disk drew a large spinner under a 13 pt bold
/// headline, in the same category and one row apart in the sidebar, so the
/// quieter of the two screens was the one shouting.
///
/// It was hand-rolled because the component had nowhere to put the Stop button.
/// It has one now, and `HelmBusyState`'s own doc comment names this page as the
/// fourth shape that gap produced.
final class ScanningStateTests: XCTestCase {

    private func page() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Modules/Disk/UI/DiskSettingsPage.swift"),
                   encoding: .utf8)
    }

    func testTheScanningPhaseIsDrawnByTheDesignSystem() throws {
        XCTAssertTrue(try page().contains("HelmBusyState("),
                      "the wait is drawn by hand instead of by the one component for it")
    }

    /// The shape it had. A page that centres its own spinner between two
    /// `Spacer()`s is the defect `HelmBusyState` exists to end, and it is the
    /// one the design system's own guard cannot see — it looks for
    /// `HelmCenteredContent`, which a hand-rolled `VStack` never mentions.
    func testThePageDoesNotCentreAWaitOfItsOwn() throws {
        let source = try page()
        XCTAssertFalse(source.contains("ProgressView().controlSize(.large)"),
                       "a large spinner: the busy state's is small, and this one "
                       + "sits beside Duplicates in the sidebar")
        XCTAssertFalse(source.contains("Text(DkStr.scanning).font(.headline)"),
                       "a 13 pt bold headline for 'Scanning'")
    }
}
