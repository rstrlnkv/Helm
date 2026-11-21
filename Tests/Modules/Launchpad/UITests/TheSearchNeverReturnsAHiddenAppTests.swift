import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Search leaves a hidden app out whether the Hidden card was open or not. The snapshot is unreconciled: the hidden app is in
/// `layout.items` and in a folder, so `search`'s own filter is the deciding line.
@MainActor final class TheSearchNeverReturnsAHiddenAppTests: XCTestCase {
    func testTheSnapshotsSearchLeavesItOut() {
        let snap = HiddenRig.unreconciled()
        XCTAssertEqual(snap.search("alpha"), ["a", "a"], "the control: the visible app is found, in the list and in the folder")
        XCTAssertFalse((snap.search("alphab") ?? []).contains(HiddenRig.hidden))
        XCTAssertEqual(snap.search("alphab"), [])
    }

    func testTheStateShowsNoHiddenAppForAQueryLockedOrUnlocked() async {
        for unlock in [false, true] {
            let rig = HiddenRig(.immediate(.success))
            if unlock {
                rig.state.open(folder: LaunchpadHiddenBlock.id)
                await rig.gate.settled()
                XCTAssertEqual(rig.gate.phase, .unlocked, "the control: unlocked")
            }
            rig.state.search = "alphab"
            XCTAssertFalse(rig.hiddenIsShown, "unlocked: \(unlock)")
            rig.state.search = "alpha"
            XCTAssertTrue(rig.everythingShown.contains("a"), "the control: a visible hit is shown")
            XCTAssertFalse(rig.hiddenIsShown, "unlocked: \(unlock)")
        }
    }
}
