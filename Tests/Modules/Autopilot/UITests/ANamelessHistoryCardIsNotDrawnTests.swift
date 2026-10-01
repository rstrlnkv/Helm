import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **A card with a title and nothing under it is not drawn**, and the block of
/// starting rules never stands beside a rule for the frame between two answers.
@MainActor
final class ANamelessHistoryCardIsNotDrawnTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func rule(enabled: Bool = true) -> Rule {
        Rule(id: "r", name: "r", enabled: enabled, conditions: [.kind(.image)], action: .trash)
    }

    private func record() -> ActionRecord {
        ActionRecord(at: Date(), rule: "r", file: "a.pdf", kind: .trashed,
                     detail: "", path: home + "/Downloads/a.pdf", run: "run")
    }

    // MARK: - The history card

    /// A watched folder with no rules and nothing done: the page says «No rules
    /// yet» itself, and a card titled «Last 30 days» over an empty list says nothing.
    func testAFolderWithNoRulesAndNoHistoryDrawsNoHistoryCard() async {
        let model = model(on: AutopilotWire(folders: [WatchedFolder(path: home + "/Downloads")]))
        await model.load()

        XCTAssertEqual(model.folders.count, 1, "precondition: a folder is on the page")
        XCTAssertTrue(model.runs.isEmpty, "precondition: nothing has happened")
        XCTAssertNil(model.historyEmpty, "precondition: and there is no reason to state")
        XCTAssertFalse(model.drawsHistory)
    }

    /// The card stays wherever it has something to say, each of the ways it can.
    func testTheHistoryCardIsDrawnWhereItHasSomethingToSay() async {
        let folder = WatchedFolder(path: home + "/Downloads", rules: [rule()])
        var off = folder
        off.rules = [rule(enabled: false)]

        // A reason to state: no folders, every rule off, nothing yet.
        for wire in [AutopilotWire(), AutopilotWire(folders: [off]), AutopilotWire(folders: [folder])] {
            let model = model(on: wire)
            await model.load()
            XCTAssertNotNil(model.historyEmpty, "precondition: an empty reason stands")
            XCTAssertTrue(model.drawsHistory)
        }

        // Passes.
        let passes = model(on: AutopilotWire(folders: [WatchedFolder(path: home + "/Downloads")],
                                             history: [record()]))
        await passes.load()
        XCTAssertFalse(passes.runs.isEmpty, "precondition: a pass is on the page")
        XCTAssertTrue(passes.drawsHistory)

        // A history something else wrote: the refusal card is the whole content.
        let refused = model(on: AutopilotWire(folders: [WatchedFolder(path: home + "/Downloads")],
                                              status: AutopilotStatus(refusal: nil, historyRefused: true)))
        await refused.load()
        XCTAssertTrue(refused.historyRefused, "precondition: the history is refused")
        XCTAssertTrue(refused.drawsHistory)
    }

    // MARK: - The order in load()

    private struct Frame: Equatable { let hasRules: Bool; let block: Bool }

    /// Rules the page did not have arrive with a reading, and the block was on
    /// screen: between the folders' answer and the status answer no frame may
    /// hold both.
    func testAReadingThatBringsRulesNeverDrawsTheBlockBesideThem() async {
        let wire = AutopilotWire()
        let model = model(on: wire)
        await model.firstLoad?.value
        XCTAssertFalse(model.presets.isEmpty, "precondition: the block is on screen")

        wire.holds([WatchedFolder(path: home + "/Music", rules: [rule()])])
        var seen: [Frame] = []
        var done = false
        let sampler = Task { @MainActor in
            while !done {
                seen.append(Frame(hasRules: model.folders.contains { !$0.rules.isEmpty },
                                  block: !model.presets.isEmpty))
                await Task.yield()
            }
        }
        await model.load()
        done = true
        await sampler.value

        XCTAssertTrue(seen.contains(Frame(hasRules: true, block: false)),
                      "precondition: the rules reached the page — \(seen)")
        XCTAssertGreaterThan(seen.count, 2, "the sampler never got a turn during the load")
        XCTAssertFalse(seen.contains(Frame(hasRules: true, block: true)),
                       "a frame drew the block beside the rules: \(seen)")
    }
}
