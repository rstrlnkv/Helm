import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Show in Finder and Copy Path hand an app's path to a closure. A hidden app's path is as private as its name: only the open Hidden
/// card, after the system's answer, may offer them; a locked or asking gate, a closed card, a window that holds no snapshot, never.
@MainActor final class AHiddenAppsFileIsOfferedOnlyByTheUnlockedHiddenCardTests: XCTestCase {
    private let hiddenApp = HiddenRig.unreconciled().apps[HiddenRig.hidden]!

    func testLockedAskingAndClosedGiveNothingAndUnlockedGivesThePath() async {
        let rig = HiddenRig(.immediate(.success))
        var copied: [String] = []
        rig.state.onCopyPath = { path, _ in copied.append(path) }
        XCTAssertNil(rig.state.fileActions(for: hiddenApp), "locked, card shut")

        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        XCTAssertEqual(rig.gate.phase, .unlocked, "the subject: unlocked and the card open")
        XCTAssertEqual(rig.state.openFolder, LaunchpadHiddenBlock.id)
        let files = rig.state.fileActions(for: hiddenApp)
        XCTAssertNotNil(files)
        files?.copyPath()
        XCTAssertEqual(copied, ["/Applications/h.app"])

        rig.state.closeFolder()
        XCTAssertNil(rig.state.fileActions(for: hiddenApp), "the card closed and locked the gate again")
    }

    func testAnUnlockedGateWithTheCardShutAndAnAskingGateGiveNothing() async {
        let rig = HiddenRig(.immediate(.success))
        rig.gate.ask(reason: "x") {}
        await rig.gate.settled()
        XCTAssertEqual(rig.gate.phase, .unlocked, "the subject: unlocked, as the settings page leaves it")
        XCTAssertNil(rig.state.openFolder)
        XCTAssertNil(rig.state.fileActions(for: hiddenApp), "unlocked is not enough: the card must be the one drawing it")

        let asking = HiddenRig(.slow)
        asking.state.open(folder: LaunchpadHiddenBlock.id)
        XCTAssertEqual(asking.gate.phase, .asking, "the subject: the prompt is up")
        XCTAssertNil(asking.state.fileActions(for: hiddenApp))
    }

    func testAVisibleAppHasThemEverywhereAndNoSnapshotHasNone() {
        let rig = HiddenRig(.immediate(.success))
        let visible = HiddenRig.unreconciled().apps["a"]!
        XCTAssertNotNil(rig.state.fileActions(for: visible), "the control")
        rig.state.update(snapshot: nil)
        XCTAssertNil(rig.state.fileActions(for: visible), "no snapshot: nothing says the app is not hidden")
    }
}
