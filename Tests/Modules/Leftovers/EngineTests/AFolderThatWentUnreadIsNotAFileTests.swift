import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **The row a source leaves behind is a folder, and every rule in this module is
/// about files.**
///
/// A source the scan did not read now comes back as a row of its own
/// (`ASourceNobodyWalkedIsNotACleanMacTests` is why), and the row carries the
/// folder's own path. Everything the page offers on a row would be wrong for it: a
/// checkbox would put `~/Library/Preferences` in a batch, «Move to Trash» would
/// offer to delete it, «Turn off» is a label the folder does not have, and «Only an
/// administrator can move this» is a sentence about moving something nobody
/// proposed to move. `ItemStatus.isSource` is what every rule asks first, and this
/// is that promise with a test under it.
final class AFolderThatWentUnreadIsNotAFileTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// Both ways a source goes unread, from the scan itself rather than from a
    /// `StaleItem` typed here: what is asserted has to be a row the module can
    /// actually produce.
    private func sourceRows() -> [StaleItem] {
        var files = LeftoversFakeFiles()
        files.redirects["/Users/x/Library/QuickLook"] = "/Volumes/Elsewhere/QuickLook"
        files.unopenable = ["/Users/x/Library/Preferences"]
        return LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                extensions: LeftoversFakeLoaded()).scan()
            .filter(\.status.isSource)
    }

    func testTheScanReturnsOneRowForEachSourceItDidNotRead() {
        let rows = sourceRows()

        XCTAssertEqual(rows.map(\.path).sorted(),
                       ["/Users/x/Library/Preferences", "/Users/x/Library/QuickLook"])
        XCTAssertEqual(Set(rows.map(\.status)), [.sourceRedirected, .sourceUnreadable],
                       "a folder that is somewhere else and one that would not open are "
                       + "two different things to do something about")
        // The row spells the source as the scan was told it, and the redirected one
        // carries where it actually leads — the fact the person cannot see anywhere
        // else on the page.
        XCTAssertEqual(rows.first { $0.status == .sourceRedirected }?.leadsTo,
                       "/Volumes/Elsewhere/QuickLook")
        XCTAssertNil(rows.first { $0.status == .sourceUnreadable }?.leadsTo)
    }

    /// **The finding this file exists for.** Nothing may be done to a folder here.
    func testASourceRowOffersNothingButALook() {
        for row in sourceRows() {
            XCTAssertEqual(row.actions, [.reveal], "\(row.path) offers \(row.actions)")
            XCTAssertFalse(row.removable, "a checkbox here puts a whole folder in a batch")
            XCTAssertFalse(row.canToggle)
            XCTAssertFalse(row.writable)
            XCTAssertNil(LeftoverActions.whyDeleteIsWithheld(from: row),
                         "there is no delete button on this row, and no sentence about "
                         + "deleting is true of it either")
        }
    }

    /// And it is counted as what it is: a verdict nobody reached, which is what
    /// keeps «No leftovers found» off a scan that did not look.
    func testASourceRowIsNeverAVerdict() {
        for row in sourceRows() {
            XCTAssertFalse(row.status.judged)
            XCTAssertTrue(row.status.isSource)
        }
        // The other five are verdicts or the absence of one about a *file*, and
        // must not drift onto this side of the line.
        XCTAssertFalse(ItemStatus.orphaned.isSource)
        XCTAssertFalse(ItemStatus.inUse.isSource)
        XCTAssertFalse(ItemStatus.protectedItem.isSource)
        XCTAssertFalse(ItemStatus.unreadable.isSource)
        XCTAssertFalse(ItemStatus.undetermined.isSource)
    }

    /// **The port's third answer, over the real filesystem.**
    ///
    /// `contents(of:)` answered `[URL]`, so «this folder would not open» was a state
    /// neither the port nor a fake of it could hold — and the scan reported the
    /// folder as empty. Read at mode 000 rather than from a fixture, because the
    /// reading *is* the finding: `FileManager.contentsOfDirectory` throws for a
    /// missing folder and for a refused one alike.
    func testTheRealPortTellsARefusedFolderFromAnEmptyOne() throws {
        let root = scratchDirectory("leftovers-contents").resolvingSymlinksInPath()
        let locked = root.appendingPathComponent("locked")
        let empty = root.appendingPathComponent("empty")
        for directory in [locked, empty] {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        }
        try write("locked/inside.plist", in: root, bytes: 16)
        // Ahead of the mode change, so it runs before the scratch drain — which
        // cannot remove what it cannot enumerate.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: locked.path)
        }
        let files = FileSystemLeftovers()
        XCTAssertEqual(files.contents(of: locked).entries.count, 1,
                       "precondition: readable, the folder holds its one file")

        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: locked.path)

        XCTAssertEqual(files.contents(of: locked), .refused)
        XCTAssertEqual(files.contents(of: empty), .listed([]),
                       "an empty folder is a reading, not a refusal")
        XCTAssertEqual(files.contents(of: root.appendingPathComponent("nope")), .listed([]),
                       "and a folder that is not there stays folded into «nothing in it», "
                       + "which is what four of the scan's seven sources are on a stock Mac")
    }
}
