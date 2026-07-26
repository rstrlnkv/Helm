import XCTest
@testable import Module_Disk_Engine

/// Grafting a measured folder in, then finding it again.
///
/// These two units are used one after the other — the view model splices the
/// fresh subtree, rebuilds the focus by path, and then asks for the chain down
/// to the folder the user clicked. Each is tested on its own elsewhere; what
/// matters here is that a node put in by one is reachable by the other, and
/// that the shapes the whole-disk scan produces are among them.
final class DiskSpliceReachabilityTests: XCTestCase {
    private func entry(_ path: String, _ bytes: Int = 1,
                       _ children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: true, noAccess: false, children: children)
    }

    /// The whole-disk scan is rooted at "/", where every other path arithmetic
    /// bug in this codebase has started: joining a child onto "/" with a plain
    /// `+ "/" +` gives "//Users", and the prefix test then matches nothing at
    /// all — the graft would silently do nothing on the one scan people
    /// actually run.
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

    /// A direct child of "/" is the shallowest graft there is, and the one the
    /// special case for "/" is easiest to get wrong on.
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
    /// The entries in the focus are values copied out of a tree that has just
    /// been replaced, so every step has to go back through paths.
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
