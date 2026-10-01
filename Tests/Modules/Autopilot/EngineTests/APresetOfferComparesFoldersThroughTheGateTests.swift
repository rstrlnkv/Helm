import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// «Is this folder already watched» is asked of the gate's own reading of a
/// path, not of its spelling.
///
/// `WatchScope` judges where a path *leads*, so a link to Downloads and the
/// `/private` spelling of it are one directory to the gate and two strings to a
/// comparison. The offer then called the watched folder new, took a second
/// `WatchedFolder` for it and, on Done, swept it — which runs the person's own
/// rules over everything in it on behalf of a preset.
final class APresetOfferComparesFoldersThroughTheGateTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("preset-offer")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("DL"),
            withDestinationURL: home.appendingPathComponent("Downloads"))
    }

    private func watched(_ path: String) -> WatchedFolder {
        WatchedFolder(id: "mine", path: path, rules: [
            Rule(id: "own", name: "Own", conditions: [.fileExtension(["pdf"])], action: .trash),
        ])
    }

    private func downloads(watching path: String) throws -> OfferedPreset {
        let all = PresetOffer.offered(watching: [watched(path)],
                                      paths: FakePresetFolders(home: home.path), home: home.path)
        return try XCTUnwrap(all.first { $0.preset.kind == .downloadsByKind })
    }

    /// The control: the same folder, spelled the same, is found — so the three
    /// below are about the spelling and not about a lookup that finds nothing.
    func testTheSameSpellingIsTheWatchedFolder() throws {
        let offer = try downloads(watching: home.appendingPathComponent("Downloads").path)
        XCTAssertFalse(offer.folderIsNew)
        XCTAssertEqual(offer.folder.id, "mine")
    }

    func testALinkToTheFolderIsTheWatchedFolder() throws {
        let offer = try downloads(watching: home.appendingPathComponent("DL").path)

        XCTAssertFalse(offer.folderIsNew, "a link to a watched folder was offered as a new one")
        XCTAssertEqual(offer.folder.id, "mine")
    }

    func testThePrivateSpellingIsTheWatchedFolder() throws {
        let spelled = "/private" + home.appendingPathComponent("Downloads").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: spelled),
                          "this scratch directory has no /private spelling")

        let offer = try downloads(watching: spelled)

        XCTAssertFalse(offer.folderIsNew, "the /private spelling was offered as a new folder")
        XCTAssertEqual(offer.folder.id, "mine")
    }

    /// And a different folder is still a different folder: a comparison that
    /// called everything the same would pass all of the above.
    func testAnotherFolderIsStillNew() throws {
        let all = PresetOffer.offered(
            watching: [watched(home.appendingPathComponent("Desktop").path)],
            paths: FakePresetFolders(home: home.path), home: home.path)
        let downloads = try XCTUnwrap(all.first { $0.preset.kind == .downloadsByKind })
        XCTAssertTrue(downloads.folderIsNew)
    }
}
