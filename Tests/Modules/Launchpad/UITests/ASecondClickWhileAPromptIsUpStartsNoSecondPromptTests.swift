import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A click, a second click, Return on the choice and the tile's own action (which is `open(folder:)` too) while the prompt is up
/// ask the system once; the one answer opens one card.
@MainActor final class ASecondClickWhileAPromptIsUpStartsNoSecondPromptTests: XCTestCase {
    func testOnePromptAndOneCardWhateverIsPressed() async {
        let rig = HiddenRig(.slow)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        rig.chooseHiddenTile()
        XCTAssertNotNil(rig.state.selection, "the control: the tile is chosen")
        rig.state.activate()
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.fake.waitForAsks()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(rig.fake.evaluations, 1)
        rig.fake.release(.success)
        await rig.gate.settled()
        XCTAssertEqual(rig.state.openFolder, LaunchpadHiddenBlock.id)
        XCTAssertEqual(rig.fake.evaluations, 1)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        XCTAssertEqual(rig.fake.evaluations, 1, "an unlocked gate asks nobody")
    }
}
