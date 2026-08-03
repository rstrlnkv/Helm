import XCTest
@testable import HelmRuntime

final class ScanRootTests: XCTestCase {

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// The commonest root there is, and the one `UserFileScope.isRemovable`
    /// refuses — which is why this gate exists separately.
    func testTheHomeItselfIsAllowed() {
        XCTAssertTrue(ScanRoot.isAllowed(home))
    }

    func testAFolderInsideTheHomeIsAllowed() {
        XCTAssertTrue(ScanRoot.isAllowed(home + "/Downloads"))
        XCTAssertTrue(ScanRoot.isAllowed(home + "/Documents"))
    }

    /// The whole point. A rewritten plist naming the volume root would send an
    /// unattended reader across every file on the machine.
    func testTheVolumeRootIsRefused() {
        XCTAssertFalse(ScanRoot.isAllowed("/"))
        XCTAssertFalse(ScanRoot.isAllowed("/System"))
        XCTAssertFalse(ScanRoot.isAllowed("/usr/bin"))
        XCTAssertFalse(ScanRoot.isAllowed("/Library"))
    }

    /// Somebody else's home is not this person's to read, even unattended and
    /// even if the filesystem would allow it.
    func testAnotherUsersHomeIsRefused() {
        XCTAssertFalse(ScanRoot.isAllowed("/Users"))
        XCTAssertFalse(ScanRoot.isAllowed("/Users/somebody-else"))
    }

    /// A relative path resolves against the process's working directory, which
    /// is not a place anybody chose to scan.
    func testARelativePathIsRefused() {
        XCTAssertFalse(ScanRoot.isAllowed("Downloads"))
        XCTAssertFalse(ScanRoot.isAllowed(""))
        XCTAssertFalse(ScanRoot.isAllowed("../.."))
    }

    /// The spelling is not the path. A gate that tests strings must resolve
    /// before it tests.
    func testTraversalOutOfTheHomeIsRefused() {
        XCTAssertFalse(ScanRoot.isAllowed(home + "/../.."))
        XCTAssertFalse(ScanRoot.isAllowed(home + "/Documents/../../../System"))
    }

    /// `standardizingPath` resolves `..` and `~` and never case, and the boot
    /// volume is case-insensitive — so a prefix test alone is fooled by the
    /// home's own name in another case.
    func testTheHomeIsMatchedRegardlessOfCase() {
        XCTAssertTrue(ScanRoot.isAllowed(home.uppercased()))
    }

    /// A path that is not there is not a root. The scan would walk nothing and
    /// report a clean folder, which is the failure that must not look like an
    /// answer.
    func testAPathThatDoesNotExistIsRefused() {
        XCTAssertFalse(ScanRoot.isAllowed(home + "/definitely-not-here-\(UUID().uuidString)"))
    }

    /// A file is not a folder to scan.
    func testAFileIsRefused() throws {
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("scan-root-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(ScanRoot.isAllowed(file.path))
    }
}
