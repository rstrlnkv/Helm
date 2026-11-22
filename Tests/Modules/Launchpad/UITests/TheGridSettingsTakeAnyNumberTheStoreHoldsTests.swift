import XCTest
import HelmRuntime
@testable import Module_Launchpad_UI

/// Whatever a plist holds under the grid's keys (a number past `Int`, a string, not-a-number, infinity), the settings read
/// inside their ranges and every screen's grid is finite, fits the screen and keeps its icon between the floor and the ask.
final class TheGridSettingsTakeAnyNumberTheStoreHoldsTests: XCTestCase {
    private let hostile: [Any] = [Int.max, Int.min, 0, -1, "ten", Double.nan, Double.infinity, -Double.infinity, 1e300, -1e300]

    private func store(_ value: Any) -> NamespacedStore {
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        for key in [LaunchpadGridSettings.Key.rows, LaunchpadGridSettings.Key.columns, LaunchpadGridSettings.Key.iconSize,
                    LaunchpadGridSettings.Key.automatic] { store.set(value, for: key) }
        return store
    }

    func testAnyStoredValueReadsInsideTheRanges() {
        for value in hostile {
            let read = LaunchpadGridSettings.read(from: store(value))
            XCTAssertTrue(LaunchpadGridSettings.rowRange.contains(read.rows), "\(value)")
            XCTAssertTrue(LaunchpadGridSettings.columnRange.contains(read.columns), "\(value)")
            XCTAssertTrue(LaunchpadGridSettings.iconRange.contains(read.iconSize), "\(value)")
        }
        XCTAssertEqual(LaunchpadGridSettings.read(from: store(Double.nan)).iconSize, 80, "no number names no size: the standard one")
    }

    func testAShowNamesThatIsNoBoolReadsTheDefault() {
        XCTAssertTrue(LaunchpadGridSettings.standard.showNames, "the default is names on")
        // Not 0 or 1: a plist number that is 0 or 1 is read as a bool by the store itself (`as? Bool` on an `NSNumber`), for every bool setting alike.
        for value in hostile.filter { ($0 as? Int) != 0 } + ["false", "no", [false] as [Bool], 2] as [Any] {
            let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
            store.set(value, for: LaunchpadGridSettings.Key.showNames)
            XCTAssertTrue(LaunchpadGridSettings.read(from: store).showNames, "\(value)")
        }
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        store.set(false, for: LaunchpadGridSettings.Key.showNames)
        XCTAssertFalse(LaunchpadGridSettings.read(from: store).showNames, "the control: a stored false is read")
    }

    func testAnySettingsMakeAGridThatFitsEveryScreen() {
        let asked = hostile.compactMap { $0 as? Double }.map { LaunchpadGridSettings(automatic: false, rows: Int.max, columns: Int.min, iconSize: $0) }
            + hostile.compactMap { $0 as? Int }.map { LaunchpadGridSettings(automatic: false, rows: $0, columns: $0, iconSize: Double($0)) }
            + [.standard]
        let screens = [CGSize(width: 1, height: 1), CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 6016, height: 3384)]
        for settings in asked {
            for screen in screens {
                for top in [CGFloat.nan, -50, 10_000] {
                    let g = LaunchpadGeometry.make(for: screen, topSafe: top, settings: settings)
                    XCTAssertEqual(g.capacity, g.columns * g.rows)
                    XCTAssertTrue((3...10).contains(g.columns) && (2...8).contains(g.rows), "\(g.columns)x\(g.rows)")
                    XCTAssertTrue(g.cellWidth.isFinite && g.cellHeight.isFinite && g.icon.isFinite && g.pageHeight.isFinite)
                    XCTAssertLessThanOrEqual(g.icon, settings.automatic ? LaunchpadMetrics.automaticIconCeiling : CGFloat(settings.normalized().iconSize))
                    XCTAssertGreaterThanOrEqual(g.icon, LaunchpadMetrics.iconFloor)
                    XCTAssertLessThanOrEqual(CGFloat(g.columns) * g.cellWidth, g.size.width + 0.001)
                }
            }
        }
    }
}
