import XCTest
@testable import Module_Disk_Engine

/// The ring paints three levels at once, so a click can land two levels down.
/// Accepting only a direct child made those outer arcs decorative: they
/// highlighted on hover and did nothing at all.
final class DiskFocusChainTests: XCTestCase {
    private func entry(_ path: String, _ children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: 1,
                  isDirectory: true, noAccess: false, children: children)
    }

    private var tree: DiskEntry {
        entry("/a", [
            entry("/a/b", [entry("/a/b/c", [entry("/a/b/c/d")])]),
            entry("/a/bc", [entry("/a/bc/e")]),
        ])
    }

    func testADirectChildIsOneStep() {
        XCTAssertEqual(DiskFocus.chain(from: tree, to: "/a/b").map(\.path), ["/a/b"])
    }

    /// The whole point: two and three levels down, through the levels between,
    /// so the breadcrumbs still describe where the user is.
    func testADescendantComesBackAsTheWholeChain() {
        XCTAssertEqual(DiskFocus.chain(from: tree, to: "/a/b/c").map(\.path),
                       ["/a/b", "/a/b/c"])
        XCTAssertEqual(DiskFocus.chain(from: tree, to: "/a/b/c/d").map(\.path),
                       ["/a/b", "/a/b/c", "/a/b/c/d"])
    }

    /// The separator matters: "/a/bc" is not inside "/a/b", and following the
    /// prefix alone would walk into the wrong folder entirely.
    func testANamesakeIsNotADescendant() {
        XCTAssertEqual(DiskFocus.chain(from: tree, to: "/a/bc/e").map(\.path),
                       ["/a/bc", "/a/bc/e"])
    }

    func testAnUnknownPathHasNoChain() {
        XCTAssertTrue(DiskFocus.chain(from: tree, to: "/a/zz").isEmpty)
        XCTAssertTrue(DiskFocus.chain(from: tree, to: "/a").isEmpty)
    }
}
