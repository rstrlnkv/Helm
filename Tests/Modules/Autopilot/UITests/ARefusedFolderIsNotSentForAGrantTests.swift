import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **`WatchScope` refuses by position, and no grant changes a position.**
///
/// The refusal a person gets for pointing a rule at `~/Library`, at a whole
/// volume or outside their home used to be `ApStr.needsAccess` — the Full Disk
/// Access sentence. They could grant the permission, restart, try again and be
/// refused again, because the gate never asked about permissions at all. So the
/// refusal has its own sentence, and these hold it to saying that one and not
/// the grant's.
@MainActor
final class ARefusedFolderIsNotSentForAGrantTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func rule() -> Rule {
        Rule(id: "r", name: "Sort", enabled: true,
             conditions: [.fileExtension(["pdf"])],
             action: .sortIntoSubfolder(.kind))
    }

    /// The one save that carries its folder in with it, which is the one place a
    /// test can stand a refused path in front of the gate without a panel.
    private func saveInto(_ path: String) async -> (AutopilotViewModel, AutopilotWire) {
        let wire = AutopilotWire()
        let model = model(on: wire)
        await model.load()
        await model.save(rule(), in: WatchedFolder(path: path))
        return (model, wire)
    }

    func testAFolderInsideTheLibraryIsRefusedWithoutBeingSentForAGrant() async {
        let (model, wire) = await saveInto(home + "/Library/Mail")

        XCTAssertEqual(model.banner, ApStr.folderOutOfReach,
                       "the refusal does not say what refused it")
        XCTAssertNotEqual(model.banner, ApStr.needsAccess,
                          "a positional refusal sent somebody to grant Full Disk Access")
        XCTAssertEqual(wire.saved, [], "a refused folder still reached the engine")
    }

    func testAFolderOutsideTheHomeIsRefusedWithTheSameSentence() async {
        let (model, wire) = await saveInto("/Users/somebody-else/Files")

        XCTAssertEqual(model.banner, ApStr.folderOutOfReach)
        XCTAssertNotEqual(model.banner, ApStr.needsAccess)
        XCTAssertEqual(wire.saved, [])
    }

    /// The permission note on the page keeps the grant sentence: it is about the
    /// grant, and it is the only caller left that is.
    func testTheGrantSentenceStillExistsForThePermissionNote() {
        XCTAssertFalse(ApStr.needsAccess.isEmpty)
        XCTAssertNotEqual(ApStr.needsAccess, ApStr.folderOutOfReach,
                          "two different refusals share one sentence again")
    }
}
