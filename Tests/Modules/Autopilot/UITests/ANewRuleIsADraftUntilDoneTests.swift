import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// «New rule» is a draft until Done, and Cancel takes nothing with it.
///
/// The button used to write the rule into the folder — through `update`, which
/// saves and re-seals — *before* the editor opened, and the editor's Cancel
/// only dismissed. Every abandoned attempt left an «Untitled rule» row that
/// cannot run today and can be switched on later by somebody who has forgotten
/// what it was; three abandoned attempts and the folder reads as broken. The
/// presets already have the discipline this asks for: a draft on the screen,
/// a save on Done, nothing anywhere else.
@MainActor
final class ANewRuleIsADraftUntilDoneTests: XCTestCase {

    private func loaded(on wire: AutopilotWire) async -> AutopilotViewModel {
        let model = AutopilotViewModel(vm: ModuleViewModel(transport: wire))
        await model.load()
        return model
    }

    /// Cancel is `dismiss()` and nothing else, so everything this asserts has
    /// to already be true the moment the sheet opens.
    func testPressingNewRuleWritesNothingUntilDone() async {
        let folder = WatchedFolder(id: "f", path: "/tmp/watched")
        let wire = AutopilotWire(folders: [folder])
        let model = await loaded(on: wire)
        XCTAssertEqual(model.folders.map(\.id), ["f"], "precondition: the folder is on the page")

        let draft = model.addRule(to: folder)

        XCTAssertFalse(draft.name.isEmpty, "the sheet opens on a named draft")
        XCTAssertEqual(model.folders.first?.rules, [],
                       "the rule is in the folder before anybody pressed Done")
        XCTAssertTrue(wire.saved.isEmpty,
                      "the rule was written and re-sealed before the editor opened, "
                      + "so Cancel means keep")
    }

    /// The other half, so «writes nothing» cannot be bought by a draft nobody
    /// can save: Done reaches the same `save` every rule takes.
    func testDoneSavesTheDraftIntoItsFolder() async {
        let folder = WatchedFolder(id: "f", path: "/tmp/watched")
        let wire = AutopilotWire(folders: [folder])
        let model = await loaded(on: wire)

        var draft = model.addRule(to: folder)
        draft.conditions = [.fileExtension(["pdf"])]
        await model.save(draft, in: folder)

        XCTAssertEqual(model.folders.first?.rules.map(\.id), [draft.id])
        XCTAssertEqual(wire.saved.last?.first?.rules.map(\.id), [draft.id],
                       "Done saved the page and not the store")
    }
}
