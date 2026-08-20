import XCTest
@testable import HelmRuntime

/// `~/Library` is refused all the way down, not only as a place to begin.
///
/// `refusedInHome` was asked exactly one question — where a walk *starts* — and
/// the home is the commonest duplicate-scan root there is, so the whole subtree
/// the list exists to protect was reached on the very next step. Measured on the
/// owner's own machine on 2026-08-20: the journal from the last unattended
/// duplicate scan held 3895 items, 217 of them under `~/Library` and 19 under
/// `~/Library/Mobile Documents`, at 0600 — readable by every process running as
/// this user, including the ones macOS refuses.
///
/// The home is a parameter, so these are facts about the rule rather than about
/// this Mac.
final class AnUnattendedWalkStaysOutOfLibraryTests: XCTestCase {
    private let home = "/Users/tester"

    private func refused(_ path: String) -> Bool {
        ScanRoot.refusesDescentInHome(into: path, home: home)
    }

    func testTheLibraryItselfIsRefused() {
        XCTAssertTrue(refused("/Users/tester/Library"))
    }

    /// The reason the root gate could not answer this: the walk meets
    /// `~/Library` one step below a root it has already approved, and everything
    /// underneath is what the list is about.
    func testEverythingUnderTheLibraryIsRefused() {
        for path in ["/Users/tester/Library/Mail",
                     "/Users/tester/Library/Messages/Archive",
                     "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs",
                     "/Users/tester/Library/Application Support/AddressBook"] {
            XCTAssertTrue(refused(path), path)
        }
    }

    /// Case is not evidence: the boot volume is case-insensitive, and the plist
    /// that names the root is writable by any process running as this user.
    func testTheNameIsMatchedWithoutCase() {
        XCTAssertTrue(refused("/Users/tester/library"))
        XCTAssertTrue(refused("/Users/tester/LIBRARY/Caches"))
    }

    /// `enumerator` hands paths without a trailing slash and other walks compose
    /// their own; both spellings name the same directory.
    func testATrailingSlashIsTheSameDirectory() {
        XCTAssertTrue(refused("/Users/tester/Library/"))
    }

    /// The ordinary folders a duplicate scan is *for*. A gate that refused these
    /// would be a gate nobody could leave switched on.
    func testTheFoldersAScanIsForAreWalked() {
        for path in ["/Users/tester/Downloads",
                     "/Users/tester/Documents/Invoices",
                     "/Users/tester/Pictures"] {
            XCTAssertFalse(refused(path), path)
        }
    }

    /// The home itself is the root, not a thing to refuse descending into — and
    /// a folder whose name merely begins with the refused one is a different
    /// folder.
    func testTheHomeAndItsNeighboursAreNotRefused() {
        XCTAssertFalse(refused("/Users/tester"))
        XCTAssertFalse(refused("/Users/tester/Librarian"))
        XCTAssertFalse(refused("/Users/tester/Library backups"))
    }

    /// **A `Library` deeper down is somebody's own folder.** The rule names the
    /// subtrees of the home that macOS protects, and `~/Documents/Library` is
    /// not one of them — a gate that refused it by name would be the blocklist
    /// this one is deliberately not.
    func testAFolderOfTheSameNameFurtherDownIsWalked() {
        XCTAssertFalse(refused("/Users/tester/Documents/Library"))
        XCTAssertFalse(refused("/Users/tester/Projects/Library/src"))
    }

    /// **A `/private` on one side only must not open the gate.** Measured
    /// 2026-08-20: `FileManager.enumerator` handed a root spelled
    /// `/var/folders/…` yields its children spelled `/private/var/folders/…`, so
    /// the walk's paths need not carry the spelling of the root it was given. A
    /// gate comparing the two would match nothing and fail open without a word.
    func testTheGateHoldsWhenOnlyOneSideCarriesPrivate() {
        let plain = "/var/folders/x/T/fixture"
        let priv = "/private" + plain
        XCTAssertTrue(ScanRoot.refusesDescentInHome(into: priv + "/Library", home: plain))
        XCTAssertTrue(ScanRoot.refusesDescentInHome(into: plain + "/Library", home: priv))
        XCTAssertTrue(ScanRoot.refusesDescentInHome(into: priv + "/Library/Caches", home: plain))
        // And it is still a gate: the folders a scan is for pass either way.
        XCTAssertFalse(ScanRoot.refusesDescentInHome(into: priv + "/Downloads", home: plain))
    }

    /// **The two halves of the gate spell the home the same way, or neither is
    /// guarding anything.** `resolve` hands the walk a fully resolved root and
    /// the walk's own paths carry that spelling; the descent gate compares
    /// against `canonicalHome`. A name spelled twice across that seam is an
    /// error nowhere — the refusal would simply never match.
    func testTheRootGateAndTheDescentGateSpellTheHomeTheSameWay() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resolved = try XCTUnwrap(ScanRoot.resolve(home))
        XCTAssertEqual(resolved, ScanRoot.canonicalHome)
        XCTAssertTrue(ScanRoot.refusesDescentInHome(into: resolved + "/Library"))
    }

    /// Outside the home the question is not this one's to answer: an external
    /// drive holding a folder called `Library` is not the TCC-protected subtree
    /// this gate is named after.
    func testOutsideTheHomeItIsSilent() {
        XCTAssertFalse(refused("/Volumes/Backup/Library"))
        XCTAssertFalse(refused("/Library"))
        XCTAssertFalse(refused("/Users/somebody-else/Library"))
    }
}
