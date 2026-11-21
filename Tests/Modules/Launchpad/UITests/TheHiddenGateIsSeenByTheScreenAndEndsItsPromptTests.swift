import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The screen observes the window's state only, and its banner reads the gate: a gate that changes alone must publish the state.
/// The prompt has a time limit; a gate that locks says so once, for the window to drop a notice that names a hidden app.
@MainActor final class TheHiddenGateIsSeenByTheScreenAndEndsItsPromptTests: XCTestCase {
    func testAnUnavailableAnswerAloneRepublishesTheState() async {
        let rig = HiddenRig(.immediate(.unavailable))
        var published = 0
        let watch = rig.state.objectWillChange.sink { published += 1 }
        defer { watch.cancel() }
        rig.gate.ask(reason: "x") {}
        await rig.gate.settled()
        XCTAssertTrue(rig.gate.unavailable, "the control: the gate flipped")
        XCTAssertGreaterThan(published, 0, "the banner reads the gate: the state must publish for the screen to draw it")
    }

    func testAPromptLeftUpLocksAfterItsTimeAndDismissesTheDialog() async {
        let fake = FakeAuthPort(.slow)
        let gate = LaunchpadHiddenGate(port: fake, timeout: .milliseconds(50))
        var asking: [Bool] = []
        gate.onAsking = { asking.append($0) }
        gate.ask(reason: "x") { XCTFail("nothing unlocks") }
        XCTAssertEqual(gate.phase, .asking, "the control")
        for _ in 0..<2000 where gate.phase == .asking { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(gate.phase, .locked)
        fake.release(.cancelled)
        await gate.settled()
        XCTAssertEqual(fake.cancellations, 1, "the system's dialog is dismissed")
        XCTAssertEqual(asking, [true, false])
    }

    func testAnAnswerInTimeKeepsItsResultAndTheTimerGoes() async {
        let gate = LaunchpadHiddenGate(port: FakeAuthPort(.immediate(.success)), timeout: .milliseconds(50))
        gate.ask(reason: "x") {}
        await gate.settled()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(gate.phase, .unlocked, "a lock timer left behind would have locked it")
    }

    func testOnlyAnUnlockedGateReportsItsLock() async {
        let gate = LaunchpadHiddenGate(port: FakeAuthPort(.immediate(.success)))
        var locks = 0
        gate.onLocked = { locks += 1 }
        gate.lock()
        XCTAssertEqual(locks, 0, "a gate that was locked says nothing")
        gate.ask(reason: "x") {}
        await gate.settled()
        gate.lock()
        gate.lock()
        XCTAssertEqual(locks, 1)
    }
}
