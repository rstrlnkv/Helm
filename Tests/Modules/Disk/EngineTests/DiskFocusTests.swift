import XCTest
@testable import Module_Disk_Engine

final class DiskFocusTests: XCTestCase {
    private func entry(_ name: String, _ path: String,
                       children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: name, path: path, bytes: 1, isDirectory: true,
                  noAccess: false, children: children)
    }

    func testResolvesAnExistingPath() {
        let tree = entry("root", "/r", children: [
            entry("a", "/r/a", children: [entry("b", "/r/a/b")]),
        ])
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/a", "/r/a/b"], in: tree)
        XCTAssertEqual(resolved.map(\.path), ["/r", "/r/a", "/r/a/b"])
    }

    /// A refreshed tree may not (yet) contain the drilled folder — the path
    /// truncates to the deepest node that still exists instead of breaking.
    func testTruncatesAtTheFirstMissingSegment() {
        let tree = entry("root", "/r", children: [entry("a", "/r/a")])
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/a", "/r/a/gone"], in: tree)
        XCTAssertEqual(resolved.map(\.path), ["/r", "/r/a"])
    }

    func testEmptyOrForeignPathYieldsTheRoot() {
        let tree = entry("root", "/r")
        XCTAssertEqual(DiskFocus.resolve(paths: [], in: tree).map(\.path), ["/r"])
        XCTAssertEqual(DiskFocus.resolve(paths: ["/other"], in: tree).map(\.path), ["/r"])
    }
}
