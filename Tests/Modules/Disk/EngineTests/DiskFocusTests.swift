import XCTest
@testable import Module_Disk_Engine

final class DiskFocusTests: XCTestCase {
    func testResolvesAnExistingPath() {
        let tree = entry("/r", 1, [
            entry("/r/a", 1, [entry("/r/a/b")]),
        ], name: "root")
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/a", "/r/a/b"], in: tree)
        XCTAssertEqual(resolved.map(\.path), ["/r", "/r/a", "/r/a/b"])
    }

    /// A refreshed tree may not (yet) contain the drilled folder — the path
    /// truncates to the deepest node that still exists instead of breaking.
    func testTruncatesAtTheFirstMissingSegment() {
        let tree = entry("/r", 1, [entry("/r/a")], name: "root")
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/a", "/r/a/gone"], in: tree)
        XCTAssertEqual(resolved.map(\.path), ["/r", "/r/a"])
    }

    func testEmptyOrForeignPathYieldsTheRoot() {
        let tree = entry("/r", name: "root")
        XCTAssertEqual(DiskFocus.resolve(paths: [], in: tree).map(\.path), ["/r"])
        XCTAssertEqual(DiskFocus.resolve(paths: ["/other"], in: tree).map(\.path), ["/r"])
    }

    // `DiskFocus.chain`: /// The ring paints three levels at once, so a click can land two levels down.
    // /// Accepting only a direct child made those outer arcs decorative: they
    // /// highlighted on hover and did nothing at all.
    private func chainEntry(_ path: String, _ children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: 1,
                  isDirectory: true, noAccess: false, children: children)
    }

    private var chainTree: DiskEntry {
        chainEntry("/a", [
            chainEntry("/a/b", [chainEntry("/a/b/c", [chainEntry("/a/b/c/d")])]),
            chainEntry("/a/bc", [chainEntry("/a/bc/e")]),
        ])
    }

    func testADirectChildIsOneStep() {
        XCTAssertEqual(DiskFocus.chain(from: chainTree, to: "/a/b").map(\.path), ["/a/b"])
    }

    /// The whole point: two and three levels down, through the levels between,
    /// so the breadcrumbs still describe where the user is.
    func testADescendantComesBackAsTheWholeChain() {
        XCTAssertEqual(DiskFocus.chain(from: chainTree, to: "/a/b/c").map(\.path),
                       ["/a/b", "/a/b/c"])
        XCTAssertEqual(DiskFocus.chain(from: chainTree, to: "/a/b/c/d").map(\.path),
                       ["/a/b", "/a/b/c", "/a/b/c/d"])
    }

    /// The separator matters: "/a/bc" is not inside "/a/b", and following the
    /// prefix alone would walk into the wrong folder entirely.
    func testANamesakeIsNotADescendant() {
        XCTAssertEqual(DiskFocus.chain(from: chainTree, to: "/a/bc/e").map(\.path),
                       ["/a/bc", "/a/bc/e"])
    }

    func testAnUnknownPathHasNoChain() {
        XCTAssertTrue(DiskFocus.chain(from: chainTree, to: "/a/zz").isEmpty)
        XCTAssertTrue(DiskFocus.chain(from: chainTree, to: "/a").isEmpty)
    }

    /// A path under a known folder that the tree does not hold is no chain at
    /// all, not a chain that stops at the last folder that exists.
    func testAnUnknownPathBelowAKnownFolderHasNoChain() {
        XCTAssertTrue(DiskFocus.chain(from: chainTree, to: "/a/b/zz").isEmpty)
        XCTAssertTrue(DiskFocus.chain(from: chainTree, to: "/a/b/c/zz").isEmpty)
    }
}
