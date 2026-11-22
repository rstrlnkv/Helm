import XCTest
@testable import Module_Launchpad_UI

/// Without app names a cell is one line shorter, so a screen holds as many rows and as large an icon as before, never fewer; the
/// names setting is a part of the grid's identity, so a change of it re-pages.
final class TheGridWithoutNamesHoldsAtLeastAsMuchTests: XCTestCase {
    func testACellIsShorterAndNoScreenHoldsLess() {
        XCTAssertEqual(LaunchpadMetrics.cellChrome(names: true, scale: 1) - LaunchpadMetrics.cellChrome(names: false, scale: 1), 17, "one line of label")
        var off = LaunchpadGridSettings.standard
        off.showNames = false
        for screen in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1440)] {
            let on = LaunchpadGeometry.make(for: screen, topSafe: 0), without = LaunchpadGeometry.make(for: screen, topSafe: 0, settings: off)
            XCTAssertLessThan(without.cellHeight, on.cellHeight, "\(screen)")
            XCTAssertGreaterThanOrEqual(without.capacity, on.capacity, "\(screen)")
            XCTAssertGreaterThanOrEqual(without.icon, on.icon, "\(screen)")
            XCTAssertNotEqual(without, on)
            print("\(Int(screen.width))x\(Int(screen.height)): names on \(on.columns)x\(on.rows) icon \(on.icon) cell \(on.cellHeight); off \(without.columns)x\(without.rows) icon \(without.icon) cell \(without.cellHeight)")
        }
    }
}
