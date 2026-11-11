import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The one folder in this module that does not arrive through the panel.**
///
/// Every other one does, which is what makes the path a person's choice. A
/// preset's folder is `FileManager`'s answer instead, so the same gate is asked
/// before the row is drawn (the engine's half) and the save carries the folder
/// in with the rule rather than asking anybody to add it first.
///
/// And the folder arriving is what decides the sweep. Adding a rule to a folder
/// somebody already watches and then sweeping it would run *their* other rules
/// over everything in it — which is not what pressing Done on a preset asked
/// for.
@MainActor
final class APresetBringsItsFolderWithItTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on work: FakeAutopilotWork) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in },
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind })
    }

    /// What the row's button hands to the editor, and what the editor's Done
    /// hands back.
    private func draft(_ offer: OfferedPreset) -> Rule {
        offer.preset.rule(named: "Screenshots", in: offer.folder.path)
    }

    // MARK: - Saving one

    func testTheFolderIsSavedWithTheRuleAlreadyInIt() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.save(draft(offer), in: offer.folder)

        let saved = try XCTUnwrap(work.saved.last)
        XCTAssertEqual(saved.map(\.path), [home + "/Desktop"])
        XCTAssertEqual(saved.first?.rules.map(\.id), ["preset.screenshots"])
        XCTAssertEqual(saved.first?.rules.first?.enabled, true)
    }

    /// **Only the rule the preset was about.** The draft the editor was given is
    /// a whole `WatchedFolder`, and a dry run puts every other rule in it — so a
    /// save that stored the draft as it stood would store rules nobody agreed
    /// to.
    func testOnlyTheRuleThatWasShownIsSaved() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)
        var draft = offer.folder
        draft.rules = [Rule(id: "smuggled", name: "s", enabled: true,
                            conditions: [.kind(.image)], action: .trash)]

        await model.save(self.draft(offer), in: draft)

        XCTAssertEqual(work.saved.last?.first?.rules.map(\.id), ["preset.screenshots"])
    }

    /// A second preset over the same folder goes into the folder the first one
    /// added, rather than storing the path twice — a second `WatchedFolder` for
    /// one path would never be reached, since the first answers for it.
    func testASecondPresetOverTheSameFolderJoinsTheFirst() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        // Both taken before the first save: the block is gone from the page the
        // moment a rule exists, so the second is no longer on offer afterwards —
        // and a `save` that still arrives with one is what this holds.
        let first = try offer(model, .downloadsByKind)
        let second = try offer(model, .oldInstallers)
        await model.save(draft(first), in: first.folder)

        await model.save(draft(second), in: second.folder)

        let saved = try XCTUnwrap(work.saved.last)
        XCTAssertEqual(saved.count, 1, "one folder was stored twice")
        XCTAssertEqual(saved.first?.rules.map(\.id),
                       ["preset.downloads-by-kind", "preset.old-installers"])
    }

    // MARK: - The sweep

    /// The walk the design is built around: press Done, and the folder is swept
    /// once, straight away, with the report and its return beside it. Waited for
    /// rather than raced, so this asserts the sweep was asked for.
    func testAFolderThePresetAddedIsSweptOnce() async throws {
        let work = FakeAutopilotWork(report: SweepReport(folderID: "f", examined: 3, acted: 1,
                                                     refused: 0, failed: 0))
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.save(draft(offer), in: offer.folder)

        XCTAssertEqual(work.count("sweepNow"), 1)
        XCTAssertNotNil(model.banner, "the sweep said nothing about what it did")
    }

    /// **And a folder somebody was already watching is not.** Their other rules
    /// would run over everything in it, which nobody asked for by pressing Done
    /// on a preset.
    func testAFolderAlreadyWatchedIsNotSwept() async throws {
        let watched = WatchedFolder(id: "desktop", path: home + "/Desktop",
                                    rules: [Rule(id: "mine", name: "m", enabled: true,
                                                 conditions: [.kind(.image)], action: .trash)])
        let work = FakeAutopilotWork(folders: [watched])
        let model = model(on: work)
        await model.load()
        // Asked of the engine's own gate: the page offers nothing once a rule
        // exists, but a draft over a watched folder is still what `save` may be
        // handed, and it is the one whose sweep must not run.
        let offer = try XCTUnwrap(PresetOffer.offered(watching: [watched],
                                                      paths: FakePresetFolders(home: home),
                                                      home: home)
            .first { $0.preset.kind == .screenshots })
        XCTAssertFalse(offer.folderIsNew, "precondition: the folder is already watched")

        await model.save(draft(offer), in: offer.folder)

        XCTAssertFalse(work.calls.contains("sweepNow"),
                       "somebody else's rules were run over their folder")
        XCTAssertEqual(work.saved.last?.first?.rules.map(\.id), ["mine", "preset.screenshots"])
    }

    // MARK: - Cancel

    /// **Nothing at all.** The dry run really happened — that is asserted first,
    /// because a test of an absence over an act that never took place passes for
    /// the wrong reason — and then the window went away, and there is no folder
    /// and no rule.
    func testCancellingLeavesNeitherAFolderNorARule() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.runPreview(for: offer.folder, rule: draft(offer))
        model.clearPreview()

        XCTAssertTrue(work.calls.contains("dryRun"),
                      "precondition: the dry run this is the cancellation of")
        XCTAssertEqual(work.saved, [], "a cancelled preset wrote a folder list")
        XCTAssertEqual(model.folders, [], "a cancelled preset left a folder on the page")
    }

    /// The dry run is of the folder that is not stored anywhere, with the rule
    /// in it — which is the whole reason the editor can be opened on a preset
    /// before anything is saved.
    func testTheDryRunIsOfTheUnsavedFolder() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.runPreview(for: offer.folder, rule: draft(offer))

        let previewed = try XCTUnwrap(work.previewed)
        XCTAssertEqual(previewed.path, home + "/Desktop")
        XCTAssertEqual(previewed.rules.map(\.id), ["preset.screenshots"])
        XCTAssertEqual(work.saved, [], "a dry run saved something")
    }

    // MARK: - Rules that are not Helm's

    /// And if one were pressed anyway, nothing goes out. The offer being empty
    /// is a fact about the screen; this is a fact about the gesture.
    func testARefusedRuleSetDoesNotTakeAPreset() async {
        let work = FakeAutopilotWork(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: work)
        await model.load()
        let offer = OfferedPreset(preset: RulePreset(kind: .screenshots),
                                  folder: WatchedFolder(path: home + "/Desktop"),
                                  folderIsNew: true)

        await model.save(draft(offer), in: offer.folder)

        XCTAssertEqual(work.saved, [], "a preset was written over a refused rule set")
        XCTAssertEqual(model.folders, [], "a refused page put the folder on screen anyway")
    }
}

/// The starting rules on offer: shown to a Mac with none, gone once a rule
/// exists or the rule set is refused, and watching their folder at its own
/// default depth.
@MainActor
final class APresetOnOfferTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on work: FakeAutopilotWork) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in },
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func offer(_ model: AutopilotViewModel, _ kind: PresetKind) throws -> OfferedPreset {
        try XCTUnwrap(model.presets.first { $0.preset.kind == kind })
    }

    /// What the row's button hands to the editor, and what the editor's Done
    /// hands back.
    private func draft(_ offer: OfferedPreset) -> Rule {
        offer.preset.rule(named: "Screenshots", in: offer.folder.path)
    }

    // MARK: - The control

    func testAMacWithNoRulesIsOfferedThePresets() async {
        let model = model(on: FakeAutopilotWork())
        await model.load()
        XCTAssertEqual(model.presets.map(\.preset.kind), PresetKind.allCases)
    }

    /// The draft folder is watched with the module's own default depth, not with
    /// anything the preset chose: a preset does not decide how deep somebody
    /// watches a folder.
    func testTheFolderArrivesAtTheFoldersOwnDepth() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.save(draft(offer), in: offer.folder)

        XCTAssertEqual(work.saved.last?.first?.depth, 1)
    }

    /// Added, and the block is gone with it: the first rule on the page ends the
    /// offer.
    func testAPresetThatWasAddedIsNoLongerOffered() async throws {
        let work = FakeAutopilotWork()
        let model = model(on: work)
        await model.load()
        let offer = try offer(model, .screenshots)

        await model.save(draft(offer), in: offer.folder)

        XCTAssertEqual(model.presets, [])
    }

    /// A refused rule set has one gesture and this is not it. The engine refuses
    /// the write too; this is the half that stops the page offering a button
    /// whose only outcome is a line in the log.
    func testARefusedRuleSetIsOfferedNoPresets() async {
        let work = FakeAutopilotWork(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: work)

        await model.load()

        XCTAssertEqual(model.screen, .rulesRefused(.tampered), "precondition")
        XCTAssertEqual(model.presets, [], "a refused page offered to add a rule")
    }
}
