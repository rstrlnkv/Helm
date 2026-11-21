import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The system's Touch ID dialog takes the key from the panel and is another app coming forward: neither ends the window while the
/// prompt is up, both do once it is gone, and a window that closes inside the prompt opens nothing when the answer arrives late.
/// Runs the real panel (tiny, far off the screens) over a fake prompt; the real port is never built.
@MainActor
final class ThePromptDoesNotCloseTheWindowTests: XCTestCase {
    private var windows: [LaunchpadWindow] = []

    override func setUp() async throws { _ = NSApplication.shared }

    override func tearDown() async throws {
        for w in windows { w.close() }
        windows = []
        await grace(0.3)
    }

    private struct Made { let window: LaunchpadWindow; let panel: LaunchpadPanel; let fake: FakeAuthPort; let state: LaunchpadScreenState }

    private func make(_ label: String) async -> Made {
        let rig = LaunchpadRig(self, label: label)
        rig.model.setViewMode(.categories)
        let fake = FakeAuthPort(.slow)
        rig.model.makeAuth = { fake }
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        windows.append(window)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: 40, height: 40), display: false)
        window.present()
        await grace(0.9)
        return Made(window: window, panel: panel, fake: fake, state: panel.state!)
    }

    private func isOpen(_ m: Made) -> Bool { m.panel.state != nil }

    private func anotherApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != AppBuild.pairedLaunchpadHelperIdentifier
        }
    }

    private func activate(_ app: NSRunningApplication) {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
                                                   userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    func testTheKeyLeavingThePanelInThePromptClosesNothingAndAfterItClosesTheWindow() async {
        let m = await make("prompt-resign")
        XCTAssertFalse(m.panel.isPrompting, "the control: no prompt yet")
        m.state.open(folder: LaunchpadHiddenBlock.id)
        await m.fake.waitForAsks()
        XCTAssertEqual(m.state.hidden.phase, .asking, "the control: the prompt is up")
        XCTAssertTrue(m.panel.isPrompting)
        XCTAssertTrue(m.panel.ignoresMouseEvents, "the panel takes no click while the dialog is up")
        m.panel.resignKey()
        await grace()
        XCTAssertTrue(isOpen(m), "the dialog taking the key closed the window")
        m.fake.release(.cancelled)
        await m.state.hidden.settled()
        XCTAssertFalse(m.panel.isPrompting)
        XCTAssertFalse(m.panel.ignoresMouseEvents, "the mouse is back once the dialog is gone")
        XCTAssertTrue(isOpen(m), "the control: a cancelled prompt leaves the window open")
        m.panel.resignKey()
        XCTAssertFalse(isOpen(m), "the positive twin: after the prompt a resign closes the window")
    }

    func testAnotherAppComingForwardInThePromptEndsNothingAndAfterItEndsTheWindow() async throws {
        let app = try XCTUnwrap(anotherApp(), "no other app is running to stand for the dialog")
        let m = await make("prompt-activate")
        m.state.open(folder: LaunchpadHiddenBlock.id)
        await m.fake.waitForAsks()
        XCTAssertEqual(m.state.hidden.phase, .asking, "the control: the prompt is up")
        activate(app)
        await grace(0.4)
        XCTAssertTrue(isOpen(m), "another app coming forward in the prompt closed the window")
        m.fake.release(.failed)
        await m.state.hidden.settled()
        activate(app)
        await waitUntil("the window closes when another app comes forward after the prompt") { !isOpen(m) }
    }

    func testACloseInThePromptLeavesTheGateLockedAndALateSuccessOpensNothing() async {
        let m = await make("prompt-close")
        m.state.open(folder: LaunchpadHiddenBlock.id)
        await m.fake.waitForAsks()
        XCTAssertEqual(m.state.hidden.phase, .asking, "the control: the prompt is up")
        m.window.close()
        XCTAssertEqual(m.state.hidden.phase, .locked)
        XCTAssertEqual(m.fake.cancellations, 1, "the close cancelled the ask")
        m.fake.release(.success)
        await m.state.hidden.settled()
        XCTAssertEqual(m.state.hidden.phase, .locked, "a success after the close unlocked the gate")
        XCTAssertNil(m.state.openFolder)
        XCTAssertTrue(m.state.folderApps.isEmpty)
    }
}
