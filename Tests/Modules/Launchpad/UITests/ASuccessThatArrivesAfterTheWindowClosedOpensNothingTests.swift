import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The prompt answers `.success` after the window (or the settings page) has gone: nothing opens, the lock stays shut, and
/// the port was told to stop.
@MainActor final class ASuccessThatArrivesAfterTheWindowClosedOpensNothingTests: XCTestCase {
    func testTheWindowClosesInThePrompt() async {
        let rig = HiddenRig(.slow)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.fake.waitForAsks()
        XCTAssertEqual(rig.gate.phase, .asking, "the control: the prompt is up")
        rig.state.shutdown()
        rig.fake.release(.success)
        await rig.gate.settled()
        XCTAssertEqual(rig.gate.phase, .locked)
        XCTAssertNil(rig.state.openFolder)
        XCTAssertEqual(rig.fake.cancellations, 1)
    }

    func testThePageClosesInThePrompt() async {
        let fake = FakeAuthPort(.slow)
        let gate = LaunchpadHiddenGate(port: fake)
        var ran = false
        gate.ask(reason: "x") { ran = true }
        await fake.waitForAsks()
        XCTAssertEqual(gate.phase, .asking, "the control: the prompt is up")
        gate.lock()
        fake.release(.success)
        await gate.settled()
        XCTAssertEqual(gate.phase, .locked)
        XCTAssertFalse(ran)
        XCTAssertEqual(fake.cancellations, 1)
    }

    func testTheOldAsksSuccessDoesNotAnswerTheNewAsk() async {
        let fake = FakeAuthPort(.slow)
        let gate = LaunchpadHiddenGate(port: fake)
        var ran = 0
        gate.ask(reason: "x") { ran += 1 }
        await fake.waitForAsks()
        gate.lock()
        gate.ask(reason: "x") { ran += 1 }
        await fake.waitForAsks(2)
        XCTAssertEqual(gate.phase, .asking, "the control: the second prompt is up")
        fake.releaseFirst(.success)
        await grace()
        XCTAssertEqual(gate.phase, .asking, "the first prompt's answer is not the second's")
        XCTAssertEqual(ran, 0)
        gate.lock()
    }
}
