import AppKit
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A failed launch's notice names the app; when the unlocked Hidden card locks, the window drops it, for it may name a hidden app.
/// Runs the real panel (tiny, far off the screens) over a fake prompt; the real port is never built.
@MainActor
final class ALockOfTheHiddenCardDropsANoticeThatNamesAnAppTests: XCTestCase {
    private var windows: [LaunchpadWindow] = []

    override func setUp() async throws { _ = NSApplication.shared }

    override func tearDown() async throws {
        for w in windows { w.close() }
        windows = []
        await grace(0.3)
    }

    func testTheNoticeOfAFailedLaunchGoesWhenTheUnlockedGateLocks() async {
        let rig = LaunchpadRig(self, label: "lock-notice")
        rig.model.setViewMode(.categories)
        let fake = FakeAuthPort(.immediate(.success))
        rig.model.makeAuth = { fake }
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        windows.append(window)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: 40, height: 40), display: false)
        window.present()
        await grace(0.9)
        let state = panel.state!
        state.open(folder: LaunchpadHiddenBlock.id)
        await state.hidden.settled()
        XCTAssertEqual(state.hidden.phase, .unlocked, "the control: the card is unlocked")
        _ = await rig.model.launch("a", name: "Alpha")
        XCTAssertEqual(rig.model.notice, .couldNotOpen("Alpha"), "the control: the failed launch left a notice naming the app")
        state.hidden.lock()
        XCTAssertNil(rig.model.notice, "the notice that names an app stayed after the Hidden card locked")
    }
}
