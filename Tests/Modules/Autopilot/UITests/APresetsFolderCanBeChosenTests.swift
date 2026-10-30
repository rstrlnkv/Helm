import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **A preset's editor can be pointed at another folder, and the gate is asked
/// before the editor believes it.**
///
/// The chooser is a third way a folder gets in, after the panel and a preset's
/// own. The engine's dry run reads whatever folder it is handed with Helm's Full
/// Disk Access, so the refusal has to come at the moment of choosing — a save
/// that refused afterwards would already have listed the file names of the
/// folder in the sheet.
///
/// The panel itself cannot be driven from a test; everything it decides is in
/// `RuleEditor.pointing` and the view model's `draftFolder`, which is what is
/// held here.
@MainActor
final class APresetsFolderCanBeChosenTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on work: FakeAutopilotWork) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in },
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind })
    }

    private func pointed(_ rule: Rule, at path: String, from offer: OfferedPreset,
                         on model: AutopilotViewModel) -> (folder: WatchedFolder, rule: Rule)? {
        RuleEditor.pointing(rule, at: path, from: offer.folder, preset: offer.preset, rvm: model)
    }

    // MARK: - The gate

    /// Refused, and **nothing is handed back to change** — the editor keeps its
    /// folder, its rule and the dry run it already has. The control first: a gate
    /// that refused every path would pass the refusal below for the wrong reason.
    func testARefusedFolderChangesNothingAndAsksForNoDryRun() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        XCTAssertNotNil(pointed(offer.draft, at: home + "/Pictures", from: offer, on: model),
                        "precondition: the gate lets an ordinary folder in the home through")

        for path in [home + "/Library/Messages", home, "/", "/System"] {
            XCTAssertNil(pointed(offer.draft, at: path, from: offer, on: model),
                         "\(path) was taken as the preset's folder")
            XCTAssertNil(model.draftFolder(at: path), "\(path) was drafted")
        }
        XCTAssertFalse(work.calls.contains("dryRun"),
                       "a refused folder was read by a dry run")
        XCTAssertNil(work.previewed)
        XCTAssertEqual(work.saved, [], "a refused choice wrote a folder list")
    }

    // MARK: - A folder that is already watched

    /// The stored folder comes back, with its own id, so the save takes the
    /// «folder exists» branch: the rule joins it, nothing is stored twice and
    /// nobody's other rules are swept.
    func testAnAlreadyWatchedFolderIsReusedAndNotSwept() async throws {
        let watched = WatchedFolder(id: "dl", path: home + "/Downloads")
        let work = FakeAutopilotWork(folders: [watched])
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)
        XCTAssertTrue(offer.folderIsNew, "precondition: the preset began in a folder not yet watched")

        let next = try XCTUnwrap(pointed(offer.draft, at: home + "/Downloads", from: offer, on: model))

        XCTAssertEqual(next.folder.id, "dl", "a second WatchedFolder was made for one path")
        XCTAssertFalse(model.sweepsAfterSaving(next.rule, in: next.folder))

        await model.save(next.rule, in: next.folder)

        let saved = try XCTUnwrap(work.saved.last)
        XCTAssertEqual(saved.map(\.path), [home + "/Downloads"], "the folder was stored twice")
        XCTAssertEqual(saved.first?.rules.map(\.id), ["preset.screenshots"])
        XCTAssertFalse(work.calls.contains("sweepNow"), "a watched folder was swept")
    }

    // MARK: - The action goes with the folder

    func testTheScreenshotsActionMovesWithTheFolder() async throws {
        let model = model(on: FakeAutopilotWork())
        await model.load()
        let offer = try offer(model, .screenshots)
        XCTAssertEqual(offer.draft.action, .move(to: home + "/Desktop/Screenshots"),
                       "precondition: the preset's action names its own folder")

        let next = try XCTUnwrap(pointed(offer.draft, at: home + "/Pictures", from: offer, on: model))

        XCTAssertEqual(next.folder.path, home + "/Pictures")
        XCTAssertEqual(next.rule.action, .move(to: home + "/Pictures/Screenshots"))
        var expected = offer.draft
        expected.action = next.rule.action
        XCTAssertEqual(next.rule, expected, "something besides the action changed")
    }

    func testAnEditedActionStaysWhereThePersonPutIt() async throws {
        let model = model(on: FakeAutopilotWork())
        await model.load()
        let offer = try offer(model, .screenshots)
        var edited = offer.draft
        edited.action = .move(to: home + "/Elsewhere")
        edited.name = "Mine"

        let next = try XCTUnwrap(pointed(edited, at: home + "/Pictures", from: offer, on: model))

        XCTAssertEqual(next.rule, edited, "an edited rule was rebuilt under the person")
        XCTAssertEqual(next.folder.path, home + "/Pictures")
    }

    /// A rule that is not a preset has no chooser and no action of the preset's
    /// to rebuild.
    func testARuleThatIsNotAPresetKeepsItsActionWhateverFolder() async throws {
        let model = model(on: FakeAutopilotWork())
        await model.load()
        let rule = Rule(id: "r", name: "r", conditions: [.fileExtension(["pdf"])],
                        action: .move(to: home + "/Desktop/Screenshots"))

        let next = try XCTUnwrap(RuleEditor.pointing(rule, at: home + "/Pictures",
                                                     from: WatchedFolder(path: home + "/Desktop"),
                                                     preset: nil, rvm: model))

        XCTAssertEqual(next.rule, rule)
    }

    // MARK: - Done, and what it promises

    /// One expression decides the sweep and the sentence, so each answer is held
    /// against what the engine was actually asked.
    func testDoneSweepsExactlyWhenTheSheetSaidItWould() async throws {
        for enabled in [true, false] {
            let work = FakeAutopilotWork(report: SweepReport(folderID: "f", examined: 3, acted: 1,
                                                         refused: 0, failed: 0))
            let model = model(on: work)
            await model.load()
            let offer = try offer(model, .screenshots)
            var rule = offer.draft
            rule.enabled = enabled

            let promised = model.sweepsAfterSaving(rule, in: offer.folder)
            await model.save(rule, in: offer.folder)

            XCTAssertEqual(promised, enabled, "a new folder with the rule on is swept, with it off is not")
            XCTAssertNotNil(work.saved.last, "precondition: the save happened (enabled \(enabled))")
            XCTAssertEqual(work.count("sweepNow"), promised ? 1 : 0,
                           "the sweep and the sentence disagree (enabled \(enabled))")
        }
    }

    func testAFolderAlreadyWatchedPromisesNoSweep() async throws {
        let watched = WatchedFolder(id: "d", path: home + "/Desktop")
        let model = model(on: FakeAutopilotWork(folders: [watched]))
        await model.load()

        XCTAssertFalse(model.sweepsAfterSaving(Rule(name: "r", action: .trash), in: watched))
    }
}
