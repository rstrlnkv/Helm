import XCTest
@testable import Module_Uninstaller_Engine

private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                path: "/Applications/Tool.app")

private func leftover(_ path: String, _ bytes: Int) -> Leftover {
    Leftover(path: path, kind: .caches, sizeBytes: bytes, matchedByName: false)
}

private func group(_ leftovers: [Leftover]) -> UninstallGroup {
    UninstallGroup(app: tool, leftovers: leftovers, running: false)
}

/// The review screen is the last one before deletion, with no dialog after it,
/// so it shows the app itself going: `UninstallPlan.paths` always takes the
/// bundle. The rows are a value, so the invariant is checkable: everything
/// `paths` will trash is a row somebody was shown.
final class ReviewRowsTests: XCTestCase {
    /// An app with no leftovers still shows its bundle.
    func testAnAppWithNoLeftoversStillShowsItsBundle() {
        let rows = UninstallPlan.reviewRows(group([]))

        XCTAssertEqual(rows, [.bundle(app: tool)])
    }

    /// Nothing is trashed that was not on the screen. Asserted as sets of paths:
    /// a count agrees with the wrong rows as readily as with the right ones.
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
