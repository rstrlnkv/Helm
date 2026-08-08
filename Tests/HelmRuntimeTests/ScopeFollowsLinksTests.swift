import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The gate must judge the path the filesystem will act on, not the path as
/// it was spelled.
///
/// `RemovableScope` and `UserFileScope` standardize (`..` and `.` collapse) and
/// stop there — but `standardizedFileURL` and `standardizingPath` do **not**
/// resolve symlinks, while `HelmTrash.trashItem` follows them. So a link
/// planted inside an allowed root pointed the gate at a path it approved and
/// the Trash at a file somewhere else entirely: the gate says
/// `~/Library/Caches/com.evil.app/taxes.pdf`, the filesystem moves
/// `~/Documents/taxes.pdf`.
///
/// It is reachable: `LeftoversScanner.plugins()` enumerates four `~/Library`
/// directories that do not exist on a stock install, so any process running as
/// the user can create one as a symlink and wait.
///
/// The answer already existed in this codebase — `WatchScope.canonical`
/// resolves the deepest ancestor that exists and puts the missing tail back,
/// because "the question is where a path *leads*".
final class ScopeFollowsLinksTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("scope-links")
        for sub in ["Library/Caches", "Documents"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    /// The planted link: an allowed root holds a symlink to a protected folder.
    private func plantLink() throws -> String {
        let link = home.appendingPathComponent("Library/Caches/com.evil.app")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: home.appendingPathComponent("Documents"))
        return link.appendingPathComponent("taxes.pdf").path
    }

    func testRemovableScopeRefusesAPathThatLeadsOutOfScope() throws {
        let throughTheLink = try plantLink()
        let real = home.appendingPathComponent("Documents/taxes.pdf").path

        XCTAssertFalse(RemovableScope.isRemovable(real, home: home.path),
                       "the real path is in ~/Documents and was already refused")
        XCTAssertFalse(RemovableScope.isRemovable(throughTheLink, home: home.path),
                       "the gate approved a spelling whose file lives in ~/Documents — "
                       + "trashItem follows the link and takes the real file")
    }

    /// `UserFileScope`'s protected list is about *system* storage, so the
    /// dangerous link points the other way: an ordinary user folder holding a
    /// link into `/System`. The spelling looks like a file in `~/Downloads`;
    /// the filesystem is pointed at the system library.
    func testUserFileScopeRefusesAUserPathThatLeadsIntoSystemStorage() throws {
        let link = home.appendingPathComponent("Documents/harmless")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/System/Library"))
        let throughTheLink = link.appendingPathComponent("CoreServices").path

        XCTAssertFalse(UserFileScope.isRemovable("/System/Library/CoreServices"),
                       "the real path is refused, as it always was")
        XCTAssertFalse(UserFileScope.isRemovable(throughTheLink),
                       "the gate approved a spelling whose file is inside /System")
    }

    /// The leaf itself may be a link — trashing a symlink removes the link and
    /// leaves its target alone, which is what the user asked for. Only an
    /// *ancestor* that redirects is a lie about where the path leads.
    func testTrashingTheLinkItselfIsStillAllowed() throws {
        let link = home.appendingPathComponent("Library/Caches/com.acme.tool")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: home.appendingPathComponent("Documents"))

        XCTAssertTrue(RemovableScope.isRemovable(link.path, home: home.path),
                      "removing the link entry itself is in scope and does not touch its target")
    }

    /// A path that does not exist yet must still be judged: the scan and the
    /// removal are separated by however long the user takes to click.
    func testAPathThatDoesNotExistIsStillJudgedOnWhereItWouldLead() throws {
        let inScope = home.appendingPathComponent("Library/Caches/com.acme.tool/gone.bin").path
        XCTAssertTrue(RemovableScope.isRemovable(inScope, home: home.path))
    }

    /// Resolving must never promote a relative path to an absolute one.
    ///
    /// `URL(fileURLWithPath:)` resolves against the process's working
    /// directory, so canonicalizing before the "is this absolute" guard turned
    /// `""` and `relative/path` into paths the gate approved. That is how the
    /// first cut of this fix broke `UserFileScope`, and it is the kind of
    /// mistake a gate cannot afford to make twice.
    func testRelativePathsAreNotPromotedToAbsoluteOnes() {
        for spelling in ["", "relative/path", "..", "Library/Caches/x"] {
            XCTAssertEqual(PathCanonical.resolvingAncestors(spelling), spelling,
                           "\(spelling.debugDescription) was rewritten into something absolute")
            XCTAssertFalse(UserFileScope.isRemovable(spelling),
                           "\(spelling.debugDescription) reached the gate as a removable path")
        }
    }
}
