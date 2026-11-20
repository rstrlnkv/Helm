import HelmRuntime
import XCTest
@testable import Module_Launchpad_UI

/// The grid the settings make: automatic is the grid before the settings existed, manual is what was chosen, and a grid that
/// does not fit shrinks its icons.
final class LaunchpadGridSettingsTests: XCTestCase {
    private let screens = [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080),
                           CGSize(width: 1024, height: 640), CGSize(width: 2560, height: 1440), CGSize(width: 800, height: 500)]

    /// The counts as the one `make` computed before pass 9: width over 132, height over 132, at most 8 and 6.
    private func before(_ size: CGSize) -> (columns: Int, rows: Int) {
        let width = size.width * (1 - 2 * LaunchpadMetrics.sideMargin)
        let gridTop = LaunchpadMetrics.searchTop + LaunchpadMetrics.searchHeight + LaunchpadMetrics.gridGap
        let height = max(0, size.height - gridTop - LaunchpadMetrics.dotsRoom)
        return (max(3, min(8, Int(width / 132))), max(2, min(6, Int(height / 132))))
    }

    func testAutomaticAtTheDefaultIconIsTheGridItWasBefore() {
        for screen in screens {
            let g = LaunchpadGeometry.make(for: screen, topSafe: 0)
            XCTAssertEqual(g.columns, before(screen).columns, "\(screen)")
            XCTAssertEqual(g.rows, before(screen).rows, "\(screen)")
        }
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
        XCTAssertEqual(g.icon, 80)
        XCTAssertEqual(g.cellHeight, LaunchpadMetrics.cellHeight(icon: LaunchpadMetrics.windowIcon))
        XCTAssertEqual(g.columns, 8)
        XCTAssertEqual(g.rows, 4)
    }

    func testManualIsWhatWasChosenWhereTheScreenHoldsIt() {
        for rows in LaunchpadGridSettings.rowRange {
            for columns in LaunchpadGridSettings.columnRange {
                let g = LaunchpadGeometry.make(for: CGSize(width: 2560, height: 1600), topSafe: 0,
                                               settings: LaunchpadGridSettings(automatic: false, rows: rows, columns: columns, iconSize: 80))
                XCTAssertEqual(g.rows, rows)
                XCTAssertEqual(g.columns, columns)
                XCTAssertLessThanOrEqual(g.pageHeight, g.size.height - g.gridTop - LaunchpadMetrics.dotsRoom + 0.001, "\(rows)x\(columns) fits")
            }
        }
    }

    func testAGridTooBigShrinksTheIconAndAShortScreenCapsTheRows() {
        let size = CGSize(width: 1024, height: 640)
        let settings = LaunchpadGridSettings(automatic: false, rows: 8, columns: 10, iconSize: 128)
        let g = LaunchpadGeometry.make(for: size, topSafe: 0, settings: settings)
        XCTAssertLessThan(g.rows, 8, "the labels do not shrink: the rows are capped")
        XCTAssertEqual(g.rows, 6)
        XCTAssertLessThan(g.icon, 128)
        XCTAssertGreaterThanOrEqual(g.icon, LaunchpadMetrics.iconFloor)
        XCTAssertLessThanOrEqual(g.pageHeight, size.height - g.gridTop - LaunchpadMetrics.dotsRoom + 0.001)
    }

    func testAutomaticFollowsTheIconAsked() {
        let size = CGSize(width: 1920, height: 1080)
        var small = LaunchpadGridSettings.standard, large = LaunchpadGridSettings.standard
        small.iconSize = 48
        large.iconSize = 128
        let base = LaunchpadGeometry.make(for: size, topSafe: 0)
        XCTAssertGreaterThanOrEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: small).rows, base.rows)
        XCTAssertLessThanOrEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: large).columns, base.columns)
        XCTAssertLessThan(LaunchpadGeometry.make(for: size, topSafe: 0, settings: large).columns, base.columns + 1)
        XCTAssertEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: large).icon, 128, "automatic grids hold the icon asked for")
    }

    func testTheSettingsReadBackWhatWasWrittenAndWriteOnlyWhatChanged() {
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        XCTAssertEqual(LaunchpadGridSettings.read(from: store), .standard)
        var next = LaunchpadGridSettings.standard
        next.iconSize = 100
        next.write(changedFrom: .standard, to: store)
        XCTAssertNil(store.object(LaunchpadGridSettings.Key.rows), "an unchanged key is not written")
        XCTAssertEqual(LaunchpadGridSettings.read(from: store).iconSize, 100)
    }
}
