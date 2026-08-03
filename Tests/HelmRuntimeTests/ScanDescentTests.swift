import XCTest
@testable import HelmRuntime

/// What an unattended walk must not descend into, wherever it meets it.
///
/// The root gate (`ScanRoot.resolve`) cannot answer this: on 2026-08-03 a
/// background scan of a perfectly legitimate root met
/// `~/Pictures/Photos Library.photoslibrary` several levels down, macOS raised a
/// consent dialog, and it sat there until somebody came back to an empty desk
/// and a question with no context. Every filename inside would have gone into a
/// 0600 journal had they said yes.
final class ScanDescentTests: XCTestCase {

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    func testAPhotoLibraryIsRefused() {
        XCTAssertTrue(ScanRoot.refusesDescent(into: home + "/Pictures/Photos Library.photoslibrary"))
    }

    /// The others are the same kind of thing: an application's database, drawn
    /// by Finder as one item, meaningless as a list of files.
    func testTheOtherApplicationLibrariesAreRefused() {
        for name in ["Music.musiclibrary", "TV.tvlibrary", "Movies.imovielibrary",
                     "Old.photolibrary", "Imported.migratedphotolibrary",
                     "Aperture.aplibrary", "Final Cut.fcpbundle"] {
            XCTAssertTrue(ScanRoot.refusesDescent(into: home + "/Media/" + name), name)
        }
    }

    /// Case is not evidence: the boot volume is case-insensitive, and a library
    /// copied by a tool that upper-cases extensions is the same database.
    func testTheExtensionIsMatchedWithoutCase() {
        XCTAssertTrue(ScanRoot.refusesDescent(into: home + "/Pictures/Old.PHOTOSLIBRARY"))
    }

    /// Not only in the home. A photo library on an external drive is the same
    /// application database, and an unattended walk has the same nothing to do
    /// in it.
    func testItIsRefusedOutsideTheHomeToo() {
        XCTAssertTrue(ScanRoot.refusesDescent(into: "/Volumes/Backup/Photos Library.photoslibrary"))
    }

    /// A trailing slash is the same directory. `enumerator` hands paths without
    /// one and `readDirectory` composes its own, so both spellings arrive.
    func testATrailingSlashIsTheSameDirectory() {
        XCTAssertTrue(ScanRoot.refusesDescent(into: home + "/Pictures/Photos Library.photoslibrary/"))
    }

    /// An ordinary folder is not refused, and neither is a folder whose *name*
    /// merely contains the word — the extension is what says "database".
    func testOrdinaryFoldersAreWalked() {
        XCTAssertFalse(ScanRoot.refusesDescent(into: home + "/Pictures"))
        XCTAssertFalse(ScanRoot.refusesDescent(into: home + "/Downloads"))
        XCTAssertFalse(ScanRoot.refusesDescent(into: home + "/Pictures/photoslibrary backups"))
        XCTAssertFalse(ScanRoot.refusesDescent(into: home + "/Pictures/My.photoslibrary.old"))
    }

    /// A file that happens to carry the extension is not a directory to descend
    /// into; the callers ask only about directories, and the answer must not
    /// depend on that discipline holding.
    func testTheRuleIsAboutTheNameAndNotTheFilesystem() {
        XCTAssertTrue(ScanRoot.refusesDescent(into: "/nowhere/at/all/X.photoslibrary"))
    }
}
