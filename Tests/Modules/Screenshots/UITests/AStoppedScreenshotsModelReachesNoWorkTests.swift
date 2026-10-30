import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A model the host has stopped asks the engine for nothing and draws nothing.**
///
/// The host stops a module's model and then the engine; a hotkey, a page that is still on screen or a late
/// state can reach the model in between and after. A test that asserts a call is absent first has a running
/// model make it, over a fake of its own: that shows the call goes through (without it, "no call" is what a fake that
/// records nothing would say too); the stopped model must not make it. The fake is `FakeScreenshotsWork`:
/// nothing constructs `SCKCapture` and no window is shown.
@MainActor
final class AStoppedScreenshotsModelReachesNoWorkTests: XCTestCase {

    private func makeScene() throws -> FakeScreenshotsScene {
        FakeScreenshotsScene(screen: FakeScreen(outcome: try FakeScreen.frozen(real: false)))
    }

    private func state(_ folder: String) -> ScreenshotsState {
        ScreenshotsState(folder: folder, folderRefused: nil, boxes: [])
    }

    /// Fails against a model whose init also refreshes or builds a session (`calls` is longer): a launch would
    /// then read preferences and raise the capture ports before any page or press asked.
    func testBuildingTheModelAsksTheEngineNothing() async throws {
        let scene = try makeScene()
        XCTAssertEqual(scene.work.calls, ["stream"], "the init asked the engine for more than its stream")
        XCTAssertEqual(scene.controllersBuilt, 0, "the init built the capture controller: a panel, a toast and ports at every launch")
        // The control: what the engine says on the stream is what the model draws.
        scene.work.say(state("/drawn"))
        await waitUntil("the model drew the state the engine said") { scene.model.state.folder == "/drawn" }
        // And the fake records a call when one is made.
        scene.model.refresh()
        XCTAssertEqual(scene.work.calls, ["stream", "refresh"])
    }

    /// Fails against a model that reads `work` and not the door after `stop()`: the stopped model builds one.
    func testAPressAfterStopBuildsNoSession() async throws {
        let running = try makeScene()
        running.model.press(.fullScreen)
        XCTAssertEqual(running.work.count("session"), 1, "the control: a press on a running model builds its session")
        XCTAssertEqual(running.controllersBuilt, 1)

        let stopped = try makeScene()
        stopped.model.stop()
        for hotkey in ScreenshotsHotkey.allCases { stopped.model.press(hotkey) }
        await grace(0.3)
        XCTAssertEqual(stopped.work.count("session"), 0, "a press after stop built a session on the real ports")
        XCTAssertEqual(stopped.controllersBuilt, 0, "a press after stop built a controller")
        XCTAssertEqual(stopped.work.screen.freezes, 0, "a press after stop froze the screen")
        XCTAssertEqual(stopped.barsPresented + stopped.overlaysPresented, 0)
    }

    func testARefreshAfterStopReachesNoWork() async throws {
        let running = try makeScene()
        running.model.refresh()
        XCTAssertEqual(running.work.count("refresh"), 1, "the control: a refresh on a running model reaches the engine")

        let stopped = try makeScene()
        stopped.model.stop()
        stopped.model.refresh()
        stopped.model.refresh()
        XCTAssertEqual(stopped.work.count("refresh"), 0, "a page still on screen woke the engine of a module that is off")
    }

    /// A `stop` that only leaves the event task running stays green here: the `closed` check in the loop keeps the late state out. The cancel is held by `testStopLetsTheStreamGo`.
    func testNewsAfterStopIsNotDrawn() async throws {
        let scene = try makeScene()
        scene.work.say(state("/before"))
        await waitUntil("the control: news before stop is drawn") { scene.model.state.folder == "/before" }
        scene.model.stop()
        let saidBefore = scene.work.said
        scene.work.say(state("/after"))
        XCTAssertEqual(scene.work.said, saidBefore + 1, "the fake said nothing, so the absence below is no evidence")
        await grace(0.3)
        XCTAssertEqual(scene.model.state.folder, "/before", "a state that came after stop was drawn")
    }

    /// Fails against a `stop` that does not end the event task, because the engine's stream stays open and the
    /// transport keeps its subscriber.
    func testStopLetsTheStreamGo() async throws {
        let scene = try makeScene()
        await grace(0.1)
        XCTAssertEqual(scene.work.streamsOpened, 1)
        XCTAssertEqual(scene.work.openStreams, 1, "the control: a running model holds its stream")
        scene.model.stop()
        await waitUntil("the stream was let go") { scene.work.openStreams == 0 }
    }
}
