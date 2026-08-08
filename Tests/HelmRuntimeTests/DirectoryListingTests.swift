import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The uninstaller and the leftovers scanner each carried a byte-identical copy
/// of this. Both walk `~/Library` folders looking for what an app left behind,
/// so both need the same two properties: a hidden entry counts, and a directory
/// that is not there is empty rather than an error.
final class DirectoryListingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("listing")
    }

    func testEveryEntryComesBackAsAFullPath() throws {
        try Data().write(to: root.appendingPathComponent("a.plist"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)

        let names = DirectoryListing.children(of: root).map(\.lastPathComponent).sorted()
        XCTAssertEqual(names, ["Sub", "a.plist"])
        for child in DirectoryListing.children(of: root) {
            XCTAssertEqual(child.deletingLastPathComponent().path, root.path,
                           "a child must be a path the caller can open, not a bare name")
        }
    }

    /// A leftover is very often a dotfile, so skipping hidden entries would skip
    /// the finding.
    func testHiddenEntriesAreIncluded() throws {
        try Data().write(to: root.appendingPathComponent(".hidden"))

        XCTAssertEqual(DirectoryListing.children(of: root).map(\.lastPathComponent), [".hidden"])
    }

    /// Both scanners ask about folders that need not exist — `Group Containers`
    /// is absent on a machine that has never had a sandboxed app write one.
    func testAMissingDirectoryIsEmptyRatherThanAFailure() {
        XCTAssertEqual(DirectoryListing.children(of: root.appendingPathComponent("nope")), [])
    }
}
