import AppKit
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A model nobody wired (every test's) reveals nothing and copies nothing: the real Finder and the real pasteboard are the descriptor's
/// to set, and a test that reached them would put a path on the owner's pasteboard. The pasteboard's change count is read, which changes nothing.
@MainActor final class TheSuiteDoesNotTouchTheFinderOrThePasteboardTests: XCTestCase {
    func testAModelNobodyWiredCopiesNothingToThePasteboard() {
        let rig = LaunchpadRig(self, label: "pasteboard")
        let before = NSPasteboard.general.changeCount
        rig.model.copyPath("/Applications/a.app", false)
        rig.model.revealApp("/Applications/a.app")
        XCTAssertEqual(NSPasteboard.general.changeCount, before, "the pasteboard was not written")
    }

    func testTheTilesActionsReachOnlyWhatTheWindowWired() {
        let rig = HiddenRig(.immediate(.success))
        let app = HiddenRig.unreconciled().apps["a"]!
        var revealed: [String] = [], copied: [String] = []
        let before = NSPasteboard.general.changeCount
        let files = rig.state.fileActions(for: app)
        XCTAssertNotNil(files, "the subject: a visible app has its actions")
        files?.reveal(); files?.copyPath()
        XCTAssertEqual(NSPasteboard.general.changeCount, before, "unwired, the state's actions write nothing")
        rig.state.onRevealApp = { revealed.append($0) }
        rig.state.onCopyPath = { path, _ in copied.append(path) }
        files?.reveal(); files?.copyPath()
        XCTAssertEqual(revealed, ["/Applications/a.app"])
        XCTAssertEqual(copied, ["/Applications/a.app"], "the plain path, nothing else")
    }
}
