import XCTest
@testable import Module_Uninstaller_Engine

/// The review screen is the last one before deletion — there is no dialog after
/// it — and it never said the app itself was going.
///
/// `UninstallPlan.paths` is documented "bundles always go", and the screen drew
/// only the leftovers: no row, no path and no sentence for the bundle. The
/// group header carried the app's icon at 18 pt, which beside a column of
/// checkboxes reads as an unticked one — so the screen could be read honestly as
/// "nothing is selected, this will do nothing".
///
/// So the rows are a value rather than a `ForEach` over `leftovers`, and the
/// invariant is checkable: everything `paths` will trash is a row somebody was
/// shown.
final class ReviewRowsTests: XCTestCase {

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 900)

    private func leftover(_ path: String, _ bytes: Int) -> Leftover {
        Leftover(path: path, kind: .caches, sizeBytes: bytes, matchedByName: false)
    }

    private func group(_ leftovers: [Leftover]) -> UninstallGroup {
        UninstallGroup(app: tool, leftovers: leftovers, running: false)
    }

    func testTheBundleIsTheFirstRow() {
        let rows = UninstallPlan.reviewRows(group([leftover("/Users/x/Library/Caches/a", 10)]))

        XCTAssertEqual(rows.first, .bundle(app: tool),
                       "the last screen before deletion does not name the app it deletes")
    }

    /// A row with a checkbox is a row that can be declined. This one cannot.
    func testTheBundleRowIsNotTickable() {
        let rows = UninstallPlan.reviewRows(group([leftover("/Users/x/Library/Caches/a", 10)]))

        XCTAssertEqual(rows.filter(\.isTickable).map(\.id), ["/Users/x/Library/Caches/a"],
                       "the bundle row offers a choice the plan does not honour")
    }

    /// The case the old screen was emptiest in: an app with nothing beside it
    /// showed "No extra files found." and not one word about the app.
    func testAnAppWithNoLeftoversStillShowsItsBundle() {
        let rows = UninstallPlan.reviewRows(group([]))

        XCTAssertEqual(rows, [.bundle(app: tool)])
    }

    func testLeftoversKeepTheOrderTheScanPutThemIn() {
        let big = leftover("/Users/x/Library/Caches/big", 500)
        let small = leftover("/Users/x/Library/Caches/small", 5)

        let rows = UninstallPlan.reviewRows(group([big, small]))

        XCTAssertEqual(rows, [.bundle(app: tool), .leftover(big), .leftover(small)])
    }

    /// The invariant the screen exists for: nothing is trashed that was not on
    /// it. Asserted as sets of paths rather than counts — a count agrees with
    /// the wrong rows as readily as with the right ones.
    func testEveryPathTheRemovalWillTakeAppearsAsARow() {
        let ticked = leftover("/Users/x/Library/Caches/a", 10)
        let untickedByDefault = Leftover(path: "/Users/x/Library/Logs/Tool", kind: .logs,
                                         sizeBytes: 3, matchedByName: true)
        let g = group([ticked, untickedByDefault])

        let shown = Set(UninstallPlan.reviewRows(g).map(\.id))
        let taken = Set(UninstallPlan.paths([g], selectedLeftovers: [ticked.path]))

        XCTAssertTrue(taken.isSubset(of: shown),
                      "these would be trashed without appearing on the screen that authorises it: "
                      + taken.subtracting(shown).sorted().joined(separator: ", "))
        XCTAssertTrue(taken.contains(tool.path), "precondition: the bundle always goes")
    }
}
