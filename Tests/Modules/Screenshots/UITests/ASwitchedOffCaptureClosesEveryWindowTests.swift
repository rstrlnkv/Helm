import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Switching Screenshots off closes every window a capture opened, whatever order the page and the press came in.**
///
/// The model's `stop()` is the one place that closes them. The page may open before the first press, so every scene
/// that closes a window runs twice: once with the page's `refresh()` before the first press and once without, and the
/// switch closes the same windows either way.
///
/// Windows are built and never shown: the overlay through `build()` (panels never ordered in), the bar counted
/// through its seam, the toast with no panel and a clock the test holds, the pins never presented. Each state is
/// proved present before the switch (the control) and gone after it.
@MainActor
final class ASwitchedOffCaptureClosesEveryWindowTests: XCTestCase {

    private let orders = [false, true]

    private func makeScene(held: Bool = true, buildOverlay: Bool = false) throws -> (FakeScreenshotsScene, PromptGate) {
        let gate = PromptGate()
        let screen = FakeScreen(outcome: try FakeScreen.frozen(real: buildOverlay), gate: held ? gate : nil)
        return (FakeScreenshotsScene(screen: screen, buildOverlay: buildOverlay), gate)
    }

    /// Brings the area press to an open overlay and returns it.
    private func openOverlay(_ scene: FakeScreenshotsScene, _ gate: PromptGate, pageFirst: Bool) async throws -> CaptureOverlay {
        if pageFirst { scene.model.refresh() }
        scene.model.press(.area)
        await gate.reached()
        await gate.open()
        await waitUntil("the overlay reached the seam") { scene.overlay != nil }
        let overlay = try XCTUnwrap(scene.overlay)
        XCTAssertTrue(overlay.isOpen, "the control: the overlay is up before the switch")
        XCTAssertTrue(try XCTUnwrap(scene.controller).isBusy)
        return overlay
    }

    /// Fails against a `stop` that cancels the
    /// controller's tasks and leaves the windows.
    func testAnOpenOverlayIsClosed() async throws {
        for pageFirst in orders {
            let (scene, gate) = try makeScene(buildOverlay: true)
            let overlay = try await openOverlay(scene, gate, pageFirst: pageFirst)
            scene.model.stop()
            XCTAssertFalse(overlay.isOpen, "the module went off and the overlay stayed up (page first: \(pageFirst))")
            XCTAssertFalse(try XCTUnwrap(scene.controller).isBusy)
        }
    }

    /// The shot flashing after its result: the panels are up and deaf.
    func testAFlashingOverlayIsClosedAtOnce() async throws {
        for pageFirst in orders {
            let (scene, gate) = try makeScene(buildOverlay: true)
            let overlay = try await openOverlay(scene, gate, pageFirst: pageFirst)
            let display = try XCTUnwrap(try OverlayRig.frames().first?.id)
            overlay.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
            overlay.mouseDragged(on: display, at: CGPoint(x: 400, y: 300), flags: [])
            overlay.mouseUp(on: display)
            overlay.perform(.exit(.confirm))
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "the control: the shot is flashing (page first: \(pageFirst))")
            scene.model.stop()
            XCTAssertFalse(overlay.isOpen, "the module went off in the flash and the panels stayed up (page first: \(pageFirst))")
            XCTAssertFalse(overlay.leaving)
        }
    }

    /// The bar and its countdown. `close()` clears both the countdown and the target.
    func testTheBarAndItsCountdownAreClosed() async throws {
        for pageFirst in orders {
            let (scene, _) = try makeScene(held: false)
            if pageFirst { scene.model.refresh() }
            scene.model.press(.panel)
            XCTAssertEqual(scene.barsPresented, 1, "the control: the bar was raised")
            let bar = try XCTUnwrap(scene.controller).bar
            bar.model.hasTarget = true
            bar.model.countdown = 3
            bar.model.countdownLength = 3
            scene.model.stop()
            XCTAssertNil(bar.model.countdown, "the countdown ring stayed (page first: \(pageFirst))")
            XCTAssertFalse(bar.model.hasTarget, "the bar kept its target (page first: \(pageFirst))")
            XCTAssertEqual(bar.model.countdownLength, 0)
            XCTAssertFalse(try XCTUnwrap(scene.controller).isBusy)
        }
    }

    /// The toast with its shots.
    func testTheToastIsDismissed() async throws {
        for pageFirst in orders {
            let (scene, _) = try makeScene(held: false)
            if pageFirst { scene.model.refresh() }
            scene.model.press(.panel)
            let toast = try XCTUnwrap(scene.controller).toast
            toast.showWorking(try ShotToastRig.picture(width: 40, height: 20))
            XCTAssertTrue(toast.model.shown && !toast.model.shots.isEmpty, "the control: a thumbnail is up (page first: \(pageFirst))")
            scene.model.stop()
            XCTAssertFalse(toast.model.shown, "the thumbnail stayed shown (page first: \(pageFirst))")
            XCTAssertTrue(toast.model.shots.isEmpty, "the shots stayed on the list")
        }
    }

    /// A pin outlives a capture and Esc on the bar (`cancel()`), and only the module's end closes it. The
    /// control is the `cancel()`, which leaves it. Fails against a `stop` that only cancels.
    func testAPinIsClosedByTheSwitchAndNotByACancel() async throws {
        for pageFirst in orders {
            let (scene, _) = try makeScene(held: false)
            if pageFirst { scene.model.refresh() }
            scene.model.press(.panel)
            let controller = try XCTUnwrap(scene.controller)
            controller.pins.open(try ShotToastRig.picture(width: 40, height: 20), frame: CGRect(x: 100, y: 100, width: 50, height: 50))
            XCTAssertEqual(controller.pins.pins.count, 1, "the subject: a pin is open")
            controller.cancel()
            XCTAssertEqual(controller.pins.pins.count, 1, "the control: a cancel leaves the pin (page first: \(pageFirst))")
            scene.model.stop()
            XCTAssertEqual(controller.pins.pins.count, 0, "the module went off and the pin stayed (page first: \(pageFirst))")
        }
    }

    /// A press whose freeze is still in flight when the module goes off opens nothing when the freeze returns.
    /// The control is the same press left alone, which presents its overlay.
    func testAPressInTheFreezeOpensNothingAfterTheSwitch() async throws {
        for stopped in [false, true] {
            let (scene, gate) = try makeScene()
            scene.model.press(.area)
            await gate.reached()
            XCTAssertEqual(scene.work.screen.freezes, 1, "the subject: the freeze is in flight (stopped: \(stopped))")
            if stopped { scene.model.stop() }
            await gate.open()
            await grace(0.5)
            if stopped {
                XCTAssertEqual(scene.overlaysPresented, 0, "the freeze returned into an overlay for a module that is off")
            } else {
                XCTAssertEqual(scene.overlaysPresented, 1, "the control: left alone the press reaches the overlay")
            }
        }
    }
}
