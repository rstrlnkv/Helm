import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The Hidden block's card, and the app in it, open only on the system's `.success`. The snapshot here is unreconciled (the hidden
/// app is still in `layout.items`), so what keeps it off every page is the state and the gate, not the engine.
@MainActor final class AHiddenAppIsNeverShownWithoutASuccessfulAskTests: XCTestCase {
    func testASuccessOpensTheCardWithTheHiddenApp() async {
        let rig = HiddenRig(.immediate(.success))
        XCTAssertFalse(rig.hiddenIsShown, "the control: locked, nothing of the hidden app is drawn")
        XCTAssertTrue(rig.state.pages[0].map(\.id).contains(rig.hiddenTile), "the control: the locked block is there")
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        XCTAssertEqual(rig.state.openFolder, LaunchpadHiddenBlock.id)
        XCTAssertEqual(rig.state.folderApps.map(\.id), [HiddenRig.hidden])
        XCTAssertEqual(rig.fake.evaluations, 1)
    }

    func testNoOtherAnswerShowsAnythingOfIt() async {
        for outcome in [AuthOutcome.failed, .cancelled, .unavailable] {
            let rig = HiddenRig(.immediate(outcome))
            rig.state.open(folder: LaunchpadHiddenBlock.id)
            await rig.gate.settled()
            XCTAssertEqual(rig.fake.evaluations, 1, "the control: the prompt was asked (\(outcome))")
            XCTAssertFalse(rig.hiddenIsShown, "\(outcome)")
            XCTAssertNil(rig.state.openFolder, "\(outcome)")
            XCTAssertEqual(rig.gate.phase, .locked, "\(outcome)")
            XCTAssertEqual(rig.gate.unavailable, outcome == .unavailable, "the banner is for an unavailable Mac only (\(outcome))")
        }
    }

    func testWhileThePromptIsUpNothingIsShown() async {
        let rig = HiddenRig(.slow)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.fake.waitForAsks()
        XCTAssertEqual(rig.fake.evaluations, 1, "the control: the prompt is up")
        XCTAssertEqual(rig.gate.phase, .asking)
        XCTAssertFalse(rig.hiddenIsShown)
        XCTAssertNil(rig.state.openFolder)
        rig.gate.lock()
    }

    func testASuccessThatComesAfterALockOpensNothing() async {
        let rig = HiddenRig(.slow)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.fake.waitForAsks()
        rig.state.shutdown()
        rig.fake.release(.success)
        await rig.gate.settled()
        XCTAssertEqual(rig.fake.evaluations, 1, "the control: the ask was made")
        XCTAssertFalse(rig.hiddenIsShown)
        XCTAssertNil(rig.state.openFolder)
        XCTAssertEqual(rig.gate.phase, .locked)
    }
}
