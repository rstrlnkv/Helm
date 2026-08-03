import XCTest
@testable import HelmRuntime

final class ScanRootTests: XCTestCase {

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// The commonest root there is, and the one `UserFileScope.isRemovable`
    /// refuses — which is why this gate exists separately.
    func testTheHomeItselfIsAllowed() {
        XCTAssertNotNil(ScanRoot.resolve(home))
    }

    func testAFolderInsideTheHomeIsAllowed() {
        XCTAssertNotNil(ScanRoot.resolve(home + "/Downloads"))
        XCTAssertNotNil(ScanRoot.resolve(home + "/Documents"))
    }

    /// The whole point. A rewritten plist naming the volume root would send an
    /// unattended reader across every file on the machine.
    func testTheVolumeRootIsRefused() {
        XCTAssertNil(ScanRoot.resolve("/"))
        XCTAssertNil(ScanRoot.resolve("/System"))
        XCTAssertNil(ScanRoot.resolve("/usr/bin"))
        XCTAssertNil(ScanRoot.resolve("/Library"))
    }

    /// Somebody else's home is not this person's to read, even unattended and
    /// even if the filesystem would allow it.
    func testAnotherUsersHomeIsRefused() {
        XCTAssertNil(ScanRoot.resolve("/Users"))
        XCTAssertNil(ScanRoot.resolve("/Users/somebody-else"))
    }

    /// A relative path resolves against the process's working directory, which
    /// is not a place anybody chose to scan.
    func testARelativePathIsRefused() {
        XCTAssertNil(ScanRoot.resolve("Downloads"))
        XCTAssertNil(ScanRoot.resolve(""))
        XCTAssertNil(ScanRoot.resolve("../.."))
    }

    /// The spelling is not the path. A gate that tests strings must resolve
    /// before it tests.
    func testTraversalOutOfTheHomeIsRefused() {
        XCTAssertNil(ScanRoot.resolve(home + "/../.."))
        XCTAssertNil(ScanRoot.resolve(home + "/Documents/../../../System"))
    }

    /// `standardizingPath` resolves `..` and `~` and never case, and the boot
    /// volume is case-insensitive — so a prefix test alone is fooled by the
    /// home's own name in another case.
    func testTheHomeIsMatchedRegardlessOfCase() {
        XCTAssertNotNil(ScanRoot.resolve(home.uppercased()))
    }

    /// A path that is not there is not a root. The scan would walk nothing and
    /// report a clean folder, which is the failure that must not look like an
    /// answer.
    func testAPathThatDoesNotExistIsRefused() {
        XCTAssertNil(ScanRoot.resolve(home + "/definitely-not-here-\(UUID().uuidString)"))
    }

    /// A file is not a folder to scan.
    func testAFileIsRefused() throws {
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("scan-root-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNil(ScanRoot.resolve(file.path))
    }
}
