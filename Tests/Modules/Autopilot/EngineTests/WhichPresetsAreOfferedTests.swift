import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// **A preset is a button that adds a folder, so the gate comes before the
/// button.**
///
/// Every other folder in this module arrives through the open panel, which means
/// a person chose it; a preset's folder arrives because `FileManager` named it.
/// `WatchScope` is the same gate either way — and a preset that failed it would
/// be a row somebody presses, an editor that opens, and a save that is refused
/// inside the engine with nothing on screen to explain it. So the refusal
/// happens where nothing has been offered yet.
final class WhichPresetsAreOfferedTests: XCTestCase {

    private let home = "/Users/x"

    private func offered(_ paths: FakePresetFolders,
                         watching folders: [WatchedFolder] = []) -> [OfferedPreset] {
        PresetOffer.offered(watching: folders, paths: paths, home: home)
    }

    // MARK: - The control

    /// Asserted first, and by name: every assertion below is «this one is not
    /// offered», and an `offered` that answered nothing at all would satisfy all
    /// of them without a gate in it.
    func testAnOrdinaryMacIsOfferedEveryPreset() {
        let all = offered(FakePresetFolders(home: home))
        XCTAssertEqual(all.map(\.preset.kind), PresetKind.allCases)
        XCTAssertTrue(all.allSatisfy(\.folderIsNew), "no folder is watched yet")
    }

    // MARK: - Where the system says the folder is

    /// A Downloads folder somebody moved to another disk. The preset follows it
    /// — the path is `FileManager`'s answer, never `~/Downloads` assembled from
    /// a home directory and a word.
    func testAMovedDownloadsFolderIsTheOneTheRuleWatches() throws {
        let moved = "/Volumes/Work/Downloads"
        let all = offered(FakePresetFolders([.desktop: home + "/Desktop", .downloads: moved]))

        let downloads = try XCTUnwrap(all.first { $0.preset.kind == .downloadsByKind })
        XCTAssertEqual(downloads.folder.path, moved)
        XCTAssertEqual(all.count, PresetKind.allCases.count, "a moved folder is still a folder")
    }

    /// A Downloads folder that is a symbolic link out of the home directory —
    /// which is what `WatchScope` resolves paths for. The two Desktop presets
    /// are untouched: one folder being out of bounds is not a reason to withhold
    /// the others.
    func testADownloadsFolderThatLeadsOutOfTheHomeDirectoryIsNotOffered() throws {
        let scratch = scratchDirectory("preset-scope")
        let home = scratch.appendingPathComponent("home")
        let outside = scratch.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = home.appendingPathComponent("Downloads")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let all = PresetOffer.offered(
            watching: [],
            paths: FakePresetFolders([.desktop: home.appendingPathComponent("Desktop").path,
                                      .downloads: link.path]),
            home: home.path)

        XCTAssertEqual(all.map(\.preset.folder), [.desktop, .desktop],
                       "a link out of the home directory was offered to a rule")
    }

    /// `FileManager` declining to name a folder is not «the usual place». A
    /// preset that guessed would watch a folder nobody meant.
    func testAFolderTheSystemWillNotNameIsNotGuessedAt() {
        let all = offered(FakePresetFolders([.desktop: home + "/Desktop"]))
        XCTAssertEqual(all.map(\.preset.folder), [.desktop, .desktop])
    }

    /// `~/Library` is refused to every rule in this module, and a preset is a
    /// rule. Stated here rather than left to `WatchScope`'s own tests, because
    /// the finding is that the gate is asked *before* the offer.
    func testAFolderInsideTheLibraryIsNotOffered() {
        let all = offered(FakePresetFolders([.desktop: home + "/Library/Desktop",
                                             .downloads: home + "/Downloads"]))
        XCTAssertEqual(all.map(\.preset.folder), [.downloads, .downloads, .downloads])
    }

    /// **A Mac with «Desktop & Documents in iCloud Drive» switched on.** `~/Desktop`
    /// is then a symbolic link into `~/Library/Mobile Documents/com~apple~CloudDocs`,
    /// and `FileManager` still answers `~/Desktop` — the link, not what it leads
    /// to. So the path the port hands over passes every test that reads it as a
    /// string: it is inside the home directory and it does not spell `Library`.
    ///
    /// It has to be refused all the same, and for a reason bigger than the gate's
    /// wording. The files under that folder are iCloud's: some of them are
    /// *evicted*, present only as a stub until something reads them, and a rule
    /// that moves them between folders on an hourly timer with nobody watching is
    /// an unattended process rearranging somebody's cloud storage. `~/Library`
    /// being refused whole is what catches it, and the only thing that makes the
    /// refusal reach this path is `WatchScope.canonical` resolving the link
    /// before it compares.
    ///
    /// The link is real rather than described, because that resolution is the
    /// whole of what is being tested — a fixture that spelled the iCloud path
    /// directly would be the case already covered two tests up.
    ///
    /// The three Downloads presets are still offered: one folder being out of
    /// bounds is not a reason to withhold the others.
    func testADesktopThatIsAnICloudLinkIsNotOffered() throws {
        let scratch = scratchDirectory("preset-icloud")
        let home = scratch.appendingPathComponent("home")
        let cloud = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Desktop")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let link = home.appendingPathComponent("Desktop")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cloud)
        // The spelling FileManager would hand over says nothing about iCloud, so
        // a gate that read the string would let this through.
        XCTAssertFalse(link.path.contains("Library"), "the fixture is not the case it claims")

        let all = PresetOffer.offered(
            watching: [],
            paths: FakePresetFolders([.desktop: link.path,
                                      .downloads: home.appendingPathComponent("Downloads").path]),
            home: home.path)

        XCTAssertEqual(all.map(\.preset.folder), [.downloads, .downloads, .downloads], """
            a Desktop that is really a folder inside ~/Library/Mobile Documents was offered to \
            an unattended rule — Autopilot would move iCloud Drive's own files, including ones \
            evicted to a stub, on an hourly timer
            """)
    }

    // MARK: - Already added

    private var screenshots: Rule {
        RulePreset(kind: .screenshots).rule(named: "n", in: home + "/Desktop")
    }

    func testAPresetAlreadyAddedIsNotOfferedAgain() {
        let desktop = WatchedFolder(path: home + "/Desktop", rules: [screenshots])
        let all = offered(FakePresetFolders(home: home), watching: [desktop])
        XCTAssertFalse(all.contains { $0.preset.kind == .screenshots })
        XCTAssertEqual(all.count, PresetKind.allCases.count - 1)
    }

    /// **By id, which is the whole reason a preset has a fixed one.** A rule
    /// renamed, re-conditioned and moved down the list is still the preset that
    /// was added, and offering it again would give somebody two rules doing
    /// nearly the same thing with no way to tell which is which.
    func testARenamedAndEditedPresetIsStillTheOneThatWasAdded() {
        var edited = screenshots
        edited.name = "My screenshots"
        edited.conditions = [.name(.contains, "shot")]
        edited.action = .trash
        edited.enabled = false
        let desktop = WatchedFolder(path: home + "/Desktop",
                                    rules: [Rule(id: "other", name: "o", action: .trash), edited])

        let all = offered(FakePresetFolders(home: home), watching: [desktop])

        XCTAssertFalse(all.contains { $0.preset.kind == .screenshots },
                       "a preset was offered a second time because its rule had been renamed")
    }

    /// And deleted, it comes back. The offer is computed from the rule set every
    /// time rather than from a list of «presets I have used», which would be a
    /// second thing to keep in step with the rules.
    func testAPresetDeletedFromTheRulesIsOfferedAgain() {
        let desktop = WatchedFolder(path: home + "/Desktop", rules: [])
        let all = offered(FakePresetFolders(home: home), watching: [desktop])
        XCTAssertTrue(all.contains { $0.preset.kind == .screenshots })
    }

    // MARK: - The folder the offer carries

    /// A folder already being watched is the folder the preset goes into,
    /// **with its own settings** — its depth included. A preset does not change
    /// how deep somebody watches their own folder; the editor says so instead.
    func testAWatchedFolderIsUsedAsItStandsRatherThanReplaced() throws {
        let deep = WatchedFolder(id: "deep", path: home + "/Downloads", depth: 8)
        let all = offered(FakePresetFolders(home: home), watching: [deep])

        let downloads = try XCTUnwrap(all.first { $0.preset.folder == .downloads })
        XCTAssertEqual(downloads.folder.id, "deep")
        XCTAssertEqual(downloads.folder.depth, 8, "a preset reached into somebody's subfolders")
        XCTAssertFalse(downloads.folderIsNew, "the folder is already watched")
    }

    /// **Two presets over one folder share one draft.** Separate `WatchedFolder`
    /// values would carry separate ids, so adding both would store `~/Downloads`
    /// twice — and the second copy's rules would never be reached, because the
    /// first folder in the list answers for the path.
    func testTwoPresetsOverOneFolderOfferTheSameDraft() {
        let all = offered(FakePresetFolders(home: home))
        let downloads = Set(all.filter { $0.preset.folder == .downloads }.map(\.folder.id))
        XCTAssertEqual(downloads.count, 1, "one folder, offered under two ids")
    }
}
