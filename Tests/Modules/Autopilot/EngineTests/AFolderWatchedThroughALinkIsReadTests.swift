import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A watched folder stored as a link to the folder — `~/DL` for `~/Downloads`.
///
/// Every gate in the module reads it as Downloads: `WatchScope.allows` lets it
/// through, the root check passes it, `WatchScope.sameFolder` calls it the
/// watched Downloads, so `PresetOffer.offered` hands a starting rule *that*
/// folder rather than a new one. What reads the folder is the one part that
/// does not: `FolderReader` enumerates the link itself, and an enumerator
/// started on a link to a directory does not descend — so the dry run shows
/// nothing, every sweep examines nothing, and the rules in it never run while
/// the folder they name is full.
///
/// On disk: a scratch home, a real link, a real file.
final class AFolderWatchedThroughALinkIsReadTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try write("Downloads/photo.jpg", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("DL"),
            withDestinationURL: home.appendingPathComponent("Downloads"))
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    /// A rule that takes the one file there — the preset's own conditions look
    /// at a file's age, and a file written a moment ago is too young for them.
    private let photos = Rule(id: "p", name: "Photos", enabled: true,
                              conditions: [.fileExtension(["jpg"])], action: .addTag("Photo"))

    /// The preset lands in the link-spelled folder, and that folder is read.
    func testAStartingRuleGivenTheLinkSpelledFolderSeesItsFiles() throws {
        let stored = WatchedFolder(id: "mine", path: home.appendingPathComponent("DL").path)
        let offer = try XCTUnwrap(PresetOffer.offered(
            watching: [stored], paths: FakePresetFolders(home: home.path), home: home.path)
            .first { $0.preset.kind == .downloadsByKind })
        XCTAssertFalse(offer.folderIsNew, "precondition: the offer joins the stored folder")

        var folder = offer.folder
        folder.rules = [photos]
        engine.folders = [folder]

        XCTAssertEqual(engine.preview(folder).count, 1,
                       "the dry run over the folder the preset joined shows nothing")
        let report = engine.sweep(folder)
        XCTAssertEqual(report.folder, .read, "precondition: nothing refused the folder")
        XCTAssertEqual(report.examined, 1, "the sweep over a link to Downloads examined nothing")
    }

    /// The control: the same rule on the same folder under its own name works,
    /// so the test above is about the spelling and not about the rule.
    func testTheSameRuleOnDownloadsItselfSeesItsFiles() throws {
        let offer = try XCTUnwrap(PresetOffer.offered(
            watching: [], paths: FakePresetFolders(home: home.path), home: home.path)
            .first { $0.preset.kind == .downloadsByKind })
        var folder = offer.folder
        folder.rules = [photos]
        engine.folders = [folder]

        XCTAssertEqual(engine.preview(folder).count, 1)
        XCTAssertEqual(engine.sweep(folder).examined, 1)
    }
}
