import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The person's arrangement is theirs: asking about a reset, cancelling it, confirming without having been asked
/// and confirming after the module stopped write nothing; a confirm after an ask overwrites once, and a second
/// confirm on the same ask writes nothing.
@MainActor
final class AResetAsksBeforeItOverwritesTests: XCTestCase {

    func testAskingWritesNothing() async {
        let rig = LaunchpadRig(self, label: "reset-ask")
        rig.arrange()
        rig.model.askToReset()
        XCTAssertTrue(rig.model.pendingReset)
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.arranged), "a question changed the arrangement")
    }

    func testCancellingAndConfirmingWithoutAnAskWriteNothing() async {
        let rig = LaunchpadRig(self, label: "reset-cancel")
        rig.arrange()
        await rig.model.confirmReset()
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.arranged), "a confirm nobody asked for reset it")
        rig.model.askToReset()
        rig.model.cancelReset()
        XCTAssertFalse(rig.model.pendingReset)
        await rig.model.confirmReset()
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.arranged), "a cancelled question was still answered yes")
    }

    func testAConfirmAfterTheModuleStoppedWritesNothing() async {
        let rig = LaunchpadRig(self, label: "reset-stopped")
        rig.arrange()
        rig.model.askToReset()
        rig.model.stop()
        await rig.model.confirmReset()
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.arranged))
    }

    func testAConfirmAfterAnAskOverwritesExactlyOnce() async {
        let rig = LaunchpadRig(self, label: "reset-once")
        rig.arrange()
        rig.model.askToReset()
        await rig.model.confirmReset()
        XCTAssertFalse(rig.model.pendingReset)
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.alphabetical), "the positive twin: the reset did happen")
        rig.arrange()
        await rig.model.confirmReset()
        XCTAssertEqual(rig.stored, .loaded(LaunchpadRig.arranged), "one answer reset twice")
    }
}
