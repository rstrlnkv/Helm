import XCTest
@testable import Module_Uninstaller_Engine

/// The order of the Apps tab. A pure function, so every case here is a table
/// and no window: each order, its direction, ties, a size that was never
/// measured against one measured as nothing, an app Spotlight has no date for,
/// and a stored value nobody should trust.
final class AppSortTests: XCTestCase {

    private func app(_ name: String, _ path: String? = nil) -> InstalledApp {
        InstalledApp(name: name, bundleID: "com.x.\(name.lowercased())",
                     path: path ?? "/Applications/\(name).app", sizeBytes: 0)
    }
    private func names(_ list: [InstalledApp]) -> [String] { list.map(\.name) }
    private func path(_ name: String) -> String { "/Applications/\(name).app" }

    private lazy var apps = [app("gamma"), app("Beta"), app("alpha"), app("Delta")]

    func testNameIsAToZIgnoringCase() {
        let out = AppSort.sorted(apps, order: .name, sizes: [:], opened: nil)
        XCTAssertEqual(names(out), ["alpha", "Beta", "Delta", "gamma"])
    }

    func testSizeIsLargestFirst() {
        let sizes = [path("gamma"): 10, path("Beta"): 3_000, path("alpha"): 200, path("Delta"): 40]
        let out = AppSort.sorted(apps, order: .size, sizes: sizes, opened: nil)
        XCTAssertEqual(names(out), ["Beta", "alpha", "Delta", "gamma"])
    }

    func testEqualSizesFallToTheName() {
        let sizes = [path("gamma"): 5, path("Beta"): 5, path("alpha"): 5, path("Delta"): 5]
        let out = AppSort.sorted(apps, order: .size, sizes: sizes, opened: nil)
        XCTAssertEqual(names(out), ["alpha", "Beta", "Delta", "gamma"])
    }

    /// Nothing measured yet is the name order — the list must not rebuild under
    /// the pointer, and there is nothing to rank by.
    func testSizeBeforeAnyMeasurementStandsByName() {
        let out = AppSort.sorted(apps, order: .size, sizes: [:], opened: nil)
        XCTAssertEqual(names(out), ["alpha", "Beta", "Delta", "gamma"])
    }

    /// Not measured (absent) and measured as nothing (zero) are two facts: the
    /// zero goes last, the absent one is not ranked as if it were big or nothing.
    func testAMeasuredZeroGoesLastAndAnUnmeasuredOneIsNotAZero() {
        // Delta measured as nothing, gamma absent: by name alone Delta would lead
        // gamma, so the order can only come from telling the two apart.
        let sizes = [path("Delta"): 0, path("Beta"): 900, path("alpha"): 20]
        let out = AppSort.sorted(apps, order: .size, sizes: sizes, opened: nil)
        XCTAssertEqual(names(out), ["Beta", "alpha", "gamma", "Delta"])
    }

    func testDateIsLongestAgoFirstAndNoRecordBeforeAll() {
        let now = Date()
        let opened = [path("gamma"): now.addingTimeInterval(-100),
                      path("Beta"): now.addingTimeInterval(-9_000),
                      path("alpha"): now.addingTimeInterval(-500)]      // Delta: no record
        let out = AppSort.sorted(apps, order: .dateLastOpened, sizes: [:], opened: opened)
        XCTAssertEqual(names(out), ["Delta", "Beta", "alpha", "gamma"])
    }

    func testNoRecordRowsAndEqualDatesFallToTheName() {
        let same = Date(timeIntervalSince1970: 1_000)
        let opened = [path("gamma"): same, path("Beta"): same]          // alpha, Delta: no record
        let out = AppSort.sorted(apps, order: .dateLastOpened, sizes: [:], opened: opened)
        XCTAssertEqual(names(out), ["alpha", "Delta", "Beta", "gamma"])
    }

    func testDateBeforeSpotlightHasBeenAskedStandsByName() {
        let out = AppSort.sorted(apps, order: .dateLastOpened, sizes: [:], opened: nil)
        XCTAssertEqual(names(out), ["alpha", "Beta", "Delta", "gamma"])
    }

    /// Spotlight answered for nobody: every row would read "no record" and the
    /// date order would be the name order dressed as a measurement. It is
    /// reported unavailable, and what is drawn as chosen is the name order.
    func testSpotlightSilentForEveryAppMakesTheDateOrderUnavailable() {
        XCTAssertFalse(AppSort.dateOrderAvailable([:]))
        XCTAssertFalse(AppSort.dateOrderAvailable(nil))
        XCTAssertTrue(AppSort.dateOrderAvailable([path("Beta"): Date()]))
        XCTAssertEqual(AppSort.effective(.dateLastOpened, opened: [:]), .name)
        XCTAssertEqual(AppSort.effective(.dateLastOpened, opened: [path("Beta"): Date()]), .dateLastOpened)
        XCTAssertEqual(AppSort.effective(.size, opened: [:]), .size)
    }

    /// Two copies of one app keep a fixed order between them.
    func testTwoCopiesOfOneNameKeepAStableOrder() {
        let a = app("Tool", "/Applications/Tool.app"), b = app("Tool", "/Applications/Setapp/Tool.app")
        XCTAssertEqual(AppSort.sorted([a, b], order: .name, sizes: [:], opened: nil).map(\.path),
                       AppSort.sorted([b, a], order: .name, sizes: [:], opened: nil).map(\.path))
    }

    // MARK: - What is stored

    func testAStoredValueOutOfRangeReadsAsTheStandardOrder() {
        XCTAssertEqual(AppSortOrder(stored: "size"), .size)
        XCTAssertEqual(AppSortOrder(stored: "dateLastOpened"), .dateLastOpened)
        for bad in [nil, "", "Size", "bogus", "size ", "\u{0}", String(repeating: "x", count: 100_000)] {
            XCTAssertEqual(AppSortOrder(stored: bad), .name, "\(String(describing: bad).prefix(20))")
        }
        XCTAssertEqual(AppSortOrder.standard, .name)
    }
}
