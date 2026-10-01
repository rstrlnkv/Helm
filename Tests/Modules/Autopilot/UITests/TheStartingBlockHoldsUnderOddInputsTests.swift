import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The «Show the rules to start with» menu, fed the inputs its own test did not.**
///
/// `StartingRulesAreOfferedOnlyWhileThereAreNoneTests` holds the steady states
/// read at load. These hold the moves between them: a refused rule set with and
/// without rules in it, the refusal discarded, the last rule deleted, the folder
/// holding it removed, a disabled folder, and the preset's own save — the one
/// gesture that turns «no rules» into «a rule» while the page is drawing the
/// block.
///
/// The transitions are sampled at every point the main actor is free, which is
/// where SwiftUI may draw: a state that is published and replaced inside one
/// synchronous turn is never on screen, and one that stands across an `await`
/// is.
@MainActor
final class TheStartingBlockHoldsUnderOddInputsTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func rule(_ id: String = "mine", enabled: Bool = true) -> Rule {
        Rule(id: id, name: id, enabled: enabled, conditions: [.kind(.image)], action: .trash)
    }

    private func settled(_ model: AutopilotViewModel) async {
        await model.firstLoad?.value
    }

    // MARK: - Refused

    /// A refused rule set the engine hands back as `[]` is, to `folders`, a Mac
    /// with no rules — the one input where «no rules» alone would offer the
    /// block. The refusal must still win.
    func testARefusedSetWithNoRulesVisibleOffersNothing() async {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: wire)
        await settled(model)
        XCTAssertEqual(model.screen, .rulesRefused(.tampered), "precondition")
        XCTAssertTrue(model.folders.allSatisfy { $0.rules.isEmpty },
                      "precondition: nothing on the page counts as a rule")
        XCTAssertEqual(model.presets, [])
    }

    func testARefusedSetWithRulesOffersNothing() async {
        let wire = AutopilotWire(folders: [WatchedFolder(path: home + "/Music", rules: [rule()])],
                                 status: AutopilotStatus(refusal: .noKey))
        let model = model(on: wire)
        await settled(model)
        XCTAssertEqual(model.screen, .rulesRefused(.noKey), "precondition")
        XCTAssertEqual(model.presets, [])
    }

    /// Discarded, the page is a Mac with no rules again, and the way to begin
    /// comes back with it.
    func testDiscardingARefusedSetBringsTheBlockBack() async {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: wire)
        await settled(model)
        XCTAssertEqual(model.presets, [], "precondition")

        wire.answers(AutopilotStatus(refusal: nil))
        await model.discardRefusedRules()

        XCTAssertEqual(model.screen, .noFolders, "precondition: the refusal is gone")
        XCTAssertEqual(model.presets.map(\.preset.kind), PresetKind.allCases)
    }

    // MARK: - Deleting

    /// The last rule deleted is a page with no rules: the block is back, and
    /// back in the same turn as the deletion rather than after the engine
    /// answers — the page drew «No rules yet» under the folder at once.
    func testDeletingTheLastRuleBringsTheBlockBackAtOnce() async {
        let only = rule()
        let folder = WatchedFolder(path: home + "/Music", rules: [only])
        let wire = AutopilotWire(folders: [folder])
        let model = model(on: wire)
        await settled(model)
        XCTAssertEqual(model.presets, [], "precondition")

        model.remove(only, from: folder)
        XCTAssertFalse(model.presets.isEmpty, "the block waited for the engine")

        await waitUntil("the deletion reached the engine and was read back") {
            wire.saved.last?.first?.rules == [] && wire.commands.filter { $0 == .status }.count >= 2
        }
        await grace()
        XCTAssertFalse(model.presets.isEmpty, "the read-back took the block away again")
    }

    /// One of two deleted is still a page with a rule.
    func testDeletingOneOfTwoRulesKeepsTheBlockAway() async {
        let first = rule("a"), second = rule("b")
        let folder = WatchedFolder(path: home + "/Music", rules: [first, second])
        let wire = AutopilotWire(folders: [folder])
        let model = model(on: wire)
        await settled(model)

        model.remove(first, from: folder)

        XCTAssertEqual(model.folders.first?.rules.map(\.id), ["b"], "precondition: one was deleted")
        XCTAssertEqual(model.presets, [])
    }

    /// The folder that held the only rule, removed whole: the same fact reached
    /// by the other gesture.
    func testRemovingTheFolderThatHeldTheOnlyRuleBringsTheBlockBack() async {
        let folder = WatchedFolder(path: home + "/Music", rules: [rule()])
        let wire = AutopilotWire(folders: [folder])
        let model = model(on: wire)
        await settled(model)
        XCTAssertEqual(model.presets, [], "precondition")

        model.removeFolder(folder)

        XCTAssertEqual(model.screen, .noFolders, "precondition: the folder is gone")
        XCTAssertFalse(model.presets.isEmpty)
    }

    // MARK: - Switched off

    /// A folder switched off still holds somebody's rules: the page draws them,
    /// so the page has begun. Its rules are not `activeRules`, which is the
    /// reading a careless `hasRules` would have taken.
    func testADisabledFolderHoldingRulesKeepsTheBlockAway() async {
        let folder = WatchedFolder(path: home + "/Music", enabled: false, rules: [rule()])
        XCTAssertTrue(folder.activeRules.isEmpty, "precondition: nothing in it is active")
        let model = model(on: AutopilotWire(folders: [folder]))
        await settled(model)
        XCTAssertEqual(model.screen, .folders, "precondition")
        XCTAssertEqual(model.presets, [])
    }

    // MARK: - Never beside a rule

    /// What the page could draw at each moment the main actor was free.
    private struct Frame: Equatable {
        let hasRules: Bool
        let block: Bool
    }

    @MainActor private final class Tape {
        var seen: [Frame] = []
        var done = false
    }

    /// Samples the model at every point the main actor is handed back, until
    /// `work` returns. Yields here are the sampling, not a wait: each one lets
    /// exactly the jobs already queued run, and the sample after it is what a
    /// render in that gap would have read.
    private func frames(of model: AutopilotViewModel,
                        during work: () async -> Void) async -> [Frame] {
        let tape = Tape()
        let sampler = Task { @MainActor in
            while !tape.done {
                tape.seen.append(Frame(hasRules: model.folders.contains { !$0.rules.isEmpty },
                                       block: !model.presets.isEmpty))
                await Task.yield()
            }
        }
        await work()
        tape.done = true
        await sampler.value
        tape.seen.append(Frame(hasRules: model.folders.contains { !$0.rules.isEmpty },
                               block: !model.presets.isEmpty))
        return tape.seen
    }

    /// **The preset's own Done.** The block was on screen when it was pressed
    /// and a rule is on the page after — at no frame between may both be.
    func testAPresetsDoneNeverDrawsTheBlockBesideItsRule() async throws {
        let wire = AutopilotWire()
        let model = model(on: wire)
        await settled(model)
        let offer = try XCTUnwrap(model.presets.first { $0.preset.kind == .screenshots })

        let seen = await frames(of: model) {
            await model.save(offer.preset.rule(named: "Screenshots", in: offer.folder.path),
                             in: offer.folder)
        }

        XCTAssertTrue(wire.commands.contains(.setFolders), "precondition: the save was sent")
        XCTAssertTrue(seen.contains(Frame(hasRules: true, block: false)),
                      "precondition: the rule reached the page — \(seen)")
        XCTAssertGreaterThan(seen.count, 2, "the sampler never got a turn during the save")
        XCTAssertFalse(seen.contains(Frame(hasRules: true, block: true)),
                       "a frame drew the block beside the rule it had just added: \(seen)")
    }

    /// **A rule's Done in a folder already watched and empty** — the other
    /// branch of `save(_:in:)`, which goes through `change` rather than
    /// appending a folder.
    func testTheFirstRuleInAnEmptyWatchedFolderNeverDrawsTheBlockBesideIt() async {
        let folder = WatchedFolder(path: home + "/Music")
        let wire = AutopilotWire(folders: [folder])
        let model = model(on: wire)
        await settled(model)
        XCTAssertFalse(model.presets.isEmpty, "precondition: the block is on screen")

        let seen = await frames(of: model) { await model.save(rule(), in: folder) }

        XCTAssertTrue(seen.contains(Frame(hasRules: true, block: false)),
                      "precondition: the rule reached the page — \(seen)")
        XCTAssertGreaterThan(seen.count, 2, "the sampler never got a turn during the save")
        XCTAssertFalse(seen.contains(Frame(hasRules: true, block: true)),
                       "a frame drew the block beside the first rule: \(seen)")
    }

    // MARK: - Before the first reading

    /// Nothing read yet is not «no rules»: until the engine has answered, the
    /// page does not know whether this Mac has rules, and offering the whole menu to a
    /// person who already wrote twenty is the flash this holds against.
    func testNothingIsOfferedBeforeTheFirstReading() async {
        let wire = AutopilotWire(folders: [WatchedFolder(path: home + "/Music", rules: [rule()])])
        let model = model(on: wire)
        // Read in the same turn as construction: the first load has been
        // started and cannot have run a line on this actor yet.
        XCTAssertEqual(model.presets, [], "the block was offered before anything was read")
        await settled(model)
        XCTAssertEqual(model.screen, .folders, "precondition: the rules did arrive")
        XCTAssertEqual(model.presets, [])
    }
}
