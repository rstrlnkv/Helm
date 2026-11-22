import HelmRuntime
import XCTest
@testable import Module_Launchpad_UI

/// The grid the settings make: automatic is seven by five scaled to the screen, manual is what was chosen, and a grid that
/// does not fit shrinks its icons.
final class LaunchpadGridSettingsTests: XCTestCase {
    private let screens = [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080),
                           CGSize(width: 1024, height: 640), CGSize(width: 2560, height: 1440), CGSize(width: 800, height: 500)]

    func testAutomaticIsSevenByFiveAndTheIconTheScaleGivesWhereTheScreenHoldsIt() {
        for screen in screens where screen.height >= 800 {
            let g = LaunchpadGeometry.make(for: screen, topSafe: 0)
            XCTAssertEqual(g.columns, 7, "\(screen)")
            XCTAssertEqual(g.rows, 5, "\(screen)")
            XCTAssertEqual(g.scale, LaunchpadMetrics.scale(for: screen, topSafe: 0), "\(screen)")
            XCTAssertLessThanOrEqual(g.icon, (LaunchpadMetrics.windowIcon * g.scale).rounded(.down), "\(screen): the ask is a ceiling")
        }
        let g = LaunchpadGeometry.make(for: CGSize(width: 1440, height: 900), topSafe: 0)
        XCTAssertEqual(g.scale, 1, "the reference screen is scale 1")
        XCTAssertEqual(g.cellHeight, LaunchpadMetrics.cellHeight(icon: g.icon, names: true, scale: 1))
    }

    func testManualIsWhatWasChosenWhereTheScreenHoldsIt() {
        for rows in LaunchpadGridSettings.rowRange {
            for columns in LaunchpadGridSettings.columnRange {
                let g = LaunchpadGeometry.make(for: CGSize(width: 2560, height: 1600), topSafe: 0,
                                               settings: LaunchpadGridSettings(automatic: false, rows: rows, columns: columns, iconSize: 80))
                XCTAssertEqual(g.rows, rows)
                XCTAssertEqual(g.columns, columns)
                XCTAssertLessThanOrEqual(g.pageHeight, g.size.height - g.gridTop - g.dotsRoom + 0.001, "\(rows)x\(columns) fits")
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
        XCTAssertLessThanOrEqual(g.pageHeight, size.height - g.gridTop - g.dotsRoom + 0.001)
    }

    func testAutomaticFollowsTheMultiplierAndKeepsItsGrid() {
        let size = CGSize(width: 1920, height: 1080)
        var small = LaunchpadGridSettings.standard, large = LaunchpadGridSettings.standard
        small.sizeMultiplier = LaunchpadGridSettings.multiplierRange.lowerBound
        large.sizeMultiplier = LaunchpadGridSettings.multiplierRange.upperBound
        let base = LaunchpadGeometry.make(for: size, topSafe: 0)
        let least = LaunchpadGeometry.make(for: size, topSafe: 0, settings: small), most = LaunchpadGeometry.make(for: size, topSafe: 0, settings: large)
        XCTAssertLessThan(least.icon, base.icon)
        XCTAssertGreaterThan(most.icon, base.icon)
        for g in [least, base, most] { XCTAssertEqual(g.columns, 7); XCTAssertEqual(g.rows, 5) }
        XCTAssertLessThan(least.scale, base.scale, "the multiplier scales everything, not the icon only")
        XCTAssertGreaterThan(most.scale, base.scale)
        XCTAssertLessThanOrEqual(most.scale, base.scale * 1.25 + 0.0001)
        var hidden = LaunchpadGridSettings.standard
        hidden.iconSize = 128
        XCTAssertEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: hidden), base, "the points Manual asks for mean nothing under Automatic")
        var manual = LaunchpadGridSettings.standard
        manual.automatic = false
        var manualLarge = manual
        manualLarge.sizeMultiplier = 1.25
        XCTAssertEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: manual), LaunchpadGeometry.make(for: size, topSafe: 0, settings: manualLarge), "and the multiplier means nothing under Manual")
        XCTAssertEqual(LaunchpadGeometry.make(for: size, topSafe: 0, settings: manual).scale, 1, "Manual is drawn at scale 1")
    }

    func testTheMultiplierIsKeptInItsRangeAndNotANumberIsTheAutomaticSize() {
        for (value, expected) in [(0.0, 0.8), (-3, 0.8), (9, 1.25), (Double.infinity, 1.25), (-Double.infinity, 0.8), (Double.nan, 1), (1.234, 1.23)] {
            var s = LaunchpadGridSettings.standard
            s.sizeMultiplier = value
            XCTAssertEqual(s.normalized().sizeMultiplier, expected, accuracy: 0.0001, "\(value)")
        }
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        store.set("not a number", for: LaunchpadGridSettings.Key.sizeMultiplier)
        XCTAssertEqual(LaunchpadGridSettings.read(from: store).sizeMultiplier, 1, "a key of another type is the default")
        store.set(1e300, for: LaunchpadGridSettings.Key.sizeMultiplier)
        XCTAssertEqual(LaunchpadGridSettings.read(from: store).sizeMultiplier, 1.25)
        XCTAssertEqual(LaunchpadGridSettings.Key.iconSize, "grid.iconSize", "a new setting has its own key; this one never moves")
        XCTAssertEqual(LaunchpadGridSettings.Key.sizeMultiplier, "grid.sizeMultiplier")
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
