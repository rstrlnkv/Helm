import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The switch-off meets the orders nobody planned: twice, with a capture open, and beside a model that is still on.**
///
/// `AStoppedScreenshotsModelReachesNoWorkTests` stops a model that never pressed, and
/// `ASwitchedOffCaptureClosesEveryWindowTests` stops one that did, once. Here the model is stopped with its overlay up
/// and then pressed at, and stopped again; and a second model (the host builds one per enable) must neither inherit
/// the first one's capture nor lose its own windows when the first is stopped.
///
/// Mutant, red here: the same guard is removed in `press`, met after a stop that found a capture open.
@MainActor
final class TheStoppedModelMeetsTheOrdersNobodyPlannedTests: XCTestCase {

    /// A second `stop` after a stop that found a capture open closes nothing twice and builds nothing.
    func testAStopTwiceWithACaptureOpenIsOneStop() async throws {
        let (scene, gate) = try FakeScreenshotsScene.withGate(in: self, buildOverlay: true)
        let overlay = try await scene.openOverlay(gate, in: self)
        scene.model.stop()
        XCTAssertFalse(overlay.isOpen, "the first stop left the overlay up")
        scene.model.stop()
        XCTAssertFalse(overlay.isOpen)
        XCTAssertEqual(scene.work.count("session"), 1, "a stop asked the engine for a session")
        XCTAssertEqual(scene.work.openStreams, 0, "the second stop reopened the stream or the first never let it go")
    }

    /// A press at a model that was stopped with a capture open reaches nothing: the controller it had is not pressed.
    func testAPressAfterAStopThatFoundACaptureOpenReachesNothing() async throws {
        let (scene, gate) = try FakeScreenshotsScene.withGate(in: self, buildOverlay: true)
        _ = try await scene.openOverlay(gate, in: self)
        scene.model.stop()
        let freezes = scene.work.screen.freezes
        for hotkey in ScreenshotsHotkey.allCases { scene.model.press(hotkey) }
        await grace(0.3)
        XCTAssertEqual(scene.work.screen.freezes, freezes, "a press after the stop froze the screen again")
        XCTAssertEqual(scene.work.count("session"), 1, "a press after the stop built another session")
        XCTAssertEqual(scene.controllersBuilt, 1, "a press after the stop built another controller")
        XCTAssertEqual(scene.overlaysPresented, 1, "a press after the stop opened another overlay")
        XCTAssertEqual(scene.barsPresented, 0, "a press after the stop put the bar up")
    }

    /// Two models at once, an order the host never builds: stopping one closes its own windows and not the
    /// other's, and the other captures on its own session.
    func testAFreshModelBesideAStoppedOneKeepsItsOwnCapture() async throws {
        let (old, oldGate) = try FakeScreenshotsScene.withGate(in: self, buildOverlay: true)
        let oldOverlay = try await old.openOverlay(oldGate, in: self)
        let (fresh, freshGate) = try FakeScreenshotsScene.withGate(in: self, buildOverlay: true)
        let freshOverlay = try await fresh.openOverlay(freshGate, in: self)
        XCTAssertFalse(old.controller === fresh.controller, "the two models share a controller")

        old.model.stop()
        XCTAssertFalse(oldOverlay.isOpen, "the control: the first model's stop closed its overlay")
        XCTAssertTrue(freshOverlay.isOpen, "stopping one model closed another model's overlay")
        XCTAssertTrue(try XCTUnwrap(fresh.controller).isBusy, "stopping one model cancelled another model's capture")
        XCTAssertEqual(fresh.work.count("session"), 1)

        fresh.model.stop()
        XCTAssertFalse(freshOverlay.isOpen)
    }
}
