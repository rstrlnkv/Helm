import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A freeze that comes back late opens what the panel shows when it comes, and nothing for a panel that is gone.** The
/// first freeze of a session is held on a gate while the person presses on: Screen, Window, Area again, ✕, the module's
/// end, another shortcut, a refusal. Whatever the order, one overlay at most, in the mode the bar shows then, over a
/// machine that is free when there is none.
@MainActor
final class TheFreezeThatReturnsLateOpensWhatThePanelShowsNowTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    /// A rig whose first freeze waits on `gate`; later ones come at once.
    private func held(values: [String: Any] = [:], timer: CaptureTimer = .none) throws -> (PanelRig.Rig, PromptGate) {
        let box = try PanelRig.rig(timer: timer, values: values)
        boxes.append(box)
        let gate = PromptGate()
        box.screen.hold = { n in n == 1 ? gate : nil }
        return (box, gate)
    }

    func testTheFreezeReturningAfterTheCloseControlOpensNothingAndFreesTheMachine() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.bar.model.cancel()
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 0, "an overlay opened for a panel that was closed with ✕")
        XCTAssertFalse(box.controller.isBusy)
    }

    /// The person closed the panel and opened it again before the old freeze came back, and pressed Area on the new one.
    /// That press must not be lost: the bar shows Area, so an overlay must come.
    func testAModePressOnAPanelOpenedWhileTheOldFreezeIsStillOutIsNotLost() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.cancel()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.open()
        await grace(0.4)
        XCTAssertEqual(box.held.overlays, 1, "Area was pressed on the new panel and no overlay came: the bar shows Area with nothing behind it")
    }

    func testAnOtherShortcutBegunAfterTheCloseIsNotCrossedByTheOldFreeze() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.cancel()
        box.controller.begin(.area)
        await waitUntil("the area shortcut's overlay opened") { box.held.overlays == 1 }
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 1, "the old freeze opened a second overlay")
        XCTAssertTrue(box.controller.isBusy, "the old freeze freed a machine that the new shortcut is using")
        XCTAssertTrue(try XCTUnwrap(box.held.overlay).isOpen)
    }

    func testWindowThenAreaThenWindowAgainOpensTheWindowOverlay() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.bar.model.choose(.area)
        box.controller.bar.model.choose(.window)
        await gate.open()
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(box.held.overlays, 1)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "the overlay is not in Window mode, the last the person chose")
    }

    /// Window first, Area last: the overlay is the Area one, on the remembered selection where the option is on.
    func testTheModeComingBackToAreaOpensAreaOnTheRememberedSelection() async throws {
        let (box, gate) = try held(values: [ScreenshotsSettings.Key.rememberSelection: true])
        try XCTUnwrap(RememberedSelection(display: "UUID-0", rect: CGRect(x: 20, y: 30, width: 200, height: 150))).write(to: box.store)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.bar.model.choose(.area)
        await gate.open()
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        XCTAssertEqual(overlay.preselection?.rect, CGRect(x: 20, y: 30, width: 200, height: 150),
                       "the overlay opened for Area without the selection the option remembers")
        XCTAssertTrue(box.controller.bar.model.hasTarget)
    }

    func testAreaThenWindowThenAreaOpensAreaOnTheRememberedSelection() async throws {
        let (box, gate) = try held(values: [ScreenshotsSettings.Key.rememberSelection: true])
        try XCTUnwrap(RememberedSelection(display: "UUID-0", rect: CGRect(x: 20, y: 30, width: 200, height: 150))).write(to: box.store)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.window)
        box.controller.bar.model.choose(.area)
        await gate.open()
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        XCTAssertNotNil(try XCTUnwrap(box.held.overlay).preselection)
        XCTAssertEqual(box.held.overlays, 1)
    }

    /// The freeze comes back refused while the bar shows Window, which it did not when the press was made.
    func testAFreezeRefusedWhileTheModeIsNowWindowIsToldAndFreesTheMachine() async throws {
        let (box, gate) = try held()
        box.screen.outcome = { n in n == 1 ? .failed : nil }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.window)
        await gate.open()
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertEqual(box.held.overlays, 0)
        XCTAssertTrue(PanelRig.hasToast(box.controller))
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.captureFailed), "the refusal was not told")
    }

    func testAFreezeRefusedWhileTheModeIsUnchangedIsToldToo() async throws {
        let (box, gate) = try held()
        box.screen.outcome = { n in n == 1 ? .denied : nil }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        await gate.open()
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.noPermission))
    }

    /// Screen, then Capture on it, with the freeze for the overlay still out: the shot is taken, and the freeze that
    /// comes back afterwards opens nothing over a panel that has gone.
    func testTheFreezeReturningAfterAScreenShotWasTakenOpensNothing() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.screen)
        box.controller.capture(from: .screen)
        await waitUntil("the screen shot was written") { box.disk.written >= 1 }
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 0, "the late freeze opened an overlay after the screen shot was taken")
        XCTAssertFalse(box.controller.isBusy, "the late freeze took the machine back")
    }

    /// After Screen while the freeze was out and back, the panel is not stuck: Window opens an overlay.
    func testWindowPressedAfterScreenSwallowedTheFreezeStillOpensAnOverlay() async throws {
        let (box, gate) = try held()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.screen)
        await gate.open()
        await grace(0.2)
        XCTAssertEqual(box.held.overlays, 0)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlays == 1 }
        XCTAssertEqual(box.screen.freezes, 2)
    }
}
