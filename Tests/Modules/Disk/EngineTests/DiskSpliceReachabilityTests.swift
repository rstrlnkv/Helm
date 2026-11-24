import XCTest
@testable import Module_Disk_Engine

/// Grafting a measured folder in, then finding it again.
///
/// The view model splices the fresh subtree, rebuilds the focus by path, and
/// asks for the chain down to the clicked folder: a node put in by the splice
/// must be reachable by the chain, including in the shapes a whole-disk scan
/// produces.
final class DiskSpliceReachabilityTests: XCTestCase {
    /// The whole-disk scan is rooted at "/": a plain `+ "/" +` gives "//Users",
    /// the prefix test then matches nothing, and the graft does nothing.
    func testGraftingIntoARootOfSlash() {
        let tree = entry("/", 10, [
            entry("/Users", 6, [entry("/Users/me", 6, [entry("/Users/me/Code")])]),
            entry("/System", 4),
        ])
        let measured = entry("/Users/me/Code", 99, [entry("/Users/me/Code/helm", 99)])
        let result = DiskTreeSplice.replacing("/Users/me/Code", with: measured, in: tree)

        let chain = DiskFocus.chain(from: result, to: "/Users/me/Code")
        XCTAssertEqual(chain.map(\.path), ["/Users", "/Users/me", "/Users/me/Code"],
                       "the grafted folder must be reachable by the path it was grafted at")
        XCTAssertEqual(chain.last?.children.map(\.path), ["/Users/me/Code/helm"])
        XCTAssertEqual(result.children.first { $0.path == "/System" }?.bytes, 4,
                       "the other branch of the root is the tree that was already there")
    }

    /// The graft at the root itself is the measured tree, not the old one.
    func testGraftingAtTheRootIsTheNewTree() {
        let tree = entry("/a", 10, [entry("/a/b", 5)])
        XCTAssertEqual(DiskTreeSplice.replacing("/a", with: entry("/a", 42), in: tree).bytes, 42)
    }

    /// A direct child of "/", the shallowest graft there is.
    func testGraftingADirectChildOfSlash() {
        let tree = entry("/", 10, [entry("/Applications"), entry("/System")])
        let result = DiskTreeSplice.replacing("/Applications",
                                              with: entry("/Applications", 50,
                                                          [entry("/Applications/Helm.app", 50)]),
                                              in: tree)
        XCTAssertEqual(result.children.first { $0.path == "/Applications" }?.bytes, 50)
        XCTAssertEqual(result.children.count, 2)
    }

    /// Two siblings where one name is a prefix of the other, both real folders
    /// in the tree. A prefix test without the separator walks into "/a/b" while
    /// looking for something inside "/a/bc" and replaces the wrong child.
    func testANamesakeSiblingIsNotWalkedInto() {
        let tree = entry("/a", 10, [
            entry("/a/b", 5, [entry("/a/b/c", 5)]),
            entry("/a/bc", 5, [entry("/a/bc/e", 5)]),
        ])
        let result = DiskTreeSplice.replacing("/a/bc/e", with: entry("/a/bc/e", 77), in: tree)
        XCTAssertEqual(result.children.first { $0.path == "/a/b" },
                       tree.children.first { $0.path == "/a/b" },
                       "the namesake branch was rewritten while its neighbour was measured")
        XCTAssertEqual(result.children.first { $0.path == "/a/bc" }?
                        .children.first?.bytes, 77)
    }

    /// The sequence the view model performs: splice, rebuild the focus from the
    /// paths it was holding, then walk down to the folder that was clicked.
    /// The focus holds values copied out of the replaced tree, so every step
    /// goes back through paths.
    func testTheFocusSurvivesTheGraft() {
        let tree = entry("/", 10, [
            entry("/Users", 6, [entry("/Users/me", 6, [entry("/Users/me/Code", 1)])]),
        ])
        let held = ["/", "/Users", "/Users/me"]
        let grafted = DiskTreeSplice.replacing("/Users/me/Code",
                                               with: entry("/Users/me/Code", 99,
                                                           [entry("/Users/me/Code/helm", 99)]),
                                               in: tree)
        let focus = DiskFocus.resolve(paths: held, in: grafted)
        XCTAssertEqual(focus.map(\.path), held, "the drill-down path still resolves")
        XCTAssertEqual(DiskFocus.chain(from: focus.last!, to: "/Users/me/Code").map(\.path),
                       ["/Users/me/Code"])
    }

    /// Nothing in the tree is touched when the path is not in it — including
    /// the shapes that are one character away from being in it.
    func testAPathThatIsNotInTheTreeChangesNothing() {
        let tree = entry("/", 10, [entry("/Users", 6, [entry("/Users/me", 6)])])
        for path in ["/Usersme", "/Users/me/deeper", "/Users/mex", "//Users/me", "", "x/y"] {
            XCTAssertEqual(DiskTreeSplice.replacing(path, with: entry(path, 99), in: tree), tree,
                           "\"\(path)\" is not a node of this tree")
        }
    }

    /// A folder measured on demand comes back empty when it really is empty —
    /// and the graft must still put it where the placeholder was, or the next
    /// click measures it all over again.
    func testAnEmptyMeasurementStillReplacesThePlaceholder() {
        let tree = entry("/a", 10, [entry("/a/b", 5)])
        let result = DiskTreeSplice.replacing("/a/b", with: entry("/a/b", 5), in: tree)
        XCTAssertEqual(result.children.map(\.path), ["/a/b"])
        XCTAssertEqual(DiskFocus.chain(from: result, to: "/a/b").map(\.path), ["/a/b"])
    }
}
