import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ladder of windows, as the real windows stand on it.** From the bottom: a pin (`.floating`), the thumbnail and
/// the bar (`.statusBar`), the overlay (`.screenSaver`), the bar **while the person picks on an overlay** (one step above
/// that). The bar is read as the window the controller really ordered in; the overlay is built and not ordered in, and its
/// panels carry their level all the same. Never below the overlay while one is up under it, and back to the toast's
/// step at every way out: the shot, Esc, ✕, a timed shot's countdown, Screen mode, and the module's end.
@MainActor
final class TheBarStaysAboveTheOverlayTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []

    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func rig(timer: CaptureTimer = .none, tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> PanelRig.Rig {
        let box = try PanelRig.rig(timer: timer, presentBar: { $0.show() }, tick: tick)
        boxes.append(box)
        return box
    }

    private func standingBar() -> BarPanel? {
        NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible }
    }

    private func overlayLevel(_ box: PanelRig.Rig) -> NSWindow.Level? { box.held.overlay?.view(for: box.display)?.window?.level }

    private let step = NSWindow.Level.screenSaver.rawValue + 1

    func testTheLadderIsPinThenToastThenOverlayThenTheBarWhileItPicks() {
        XCTAssertLessThan(NSWindow.Level.floating.rawValue, NSWindow.Level.statusBar.rawValue, "a pin is not the lowest step")
        XCTAssertLessThan(NSWindow.Level.statusBar.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertEqual(CapturePanel.level(selecting: false), .statusBar)
        XCTAssertEqual(CapturePanel.level(selecting: true).rawValue, step)
    }

    func testTheBarStandsAtTheToastsStepUntilAnOverlayIsOpenUnderItAndAboveItWhile() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        XCTAssertEqual(standingBar()?.level, .statusBar, "the bar is not on the toast's step before anything is picked")
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(overlayLevel(box))
        XCTAssertEqual(overlay, .screenSaver)
        let bar = try XCTUnwrap(standingBar())
        XCTAssertEqual(bar.level.rawValue, step)
        XCTAssertGreaterThan(bar.level.rawValue, overlay.rawValue, "the bar lies below the overlay it picks on")
        box.controller.bar.model.choose(.window)
        XCTAssertGreaterThan(try XCTUnwrap(standingBar()).level.rawValue, overlay.rawValue, "a mode switch dropped the bar under the overlay")
        box.controller.bar.model.choose(.area)
        XCTAssertGreaterThan(try XCTUnwrap(standingBar()).level.rawValue, overlay.rawValue)
    }

    func testScreenModePutsTheOverlayAwayAndTheBarBackOnTheToastsStepAndAnotherPickRaisesItAgain() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        box.controller.bar.model.choose(.screen)
        XCTAssertEqual(standingBar()?.level, .statusBar, "the bar kept the overlay's step with no overlay under it")
        XCTAssertFalse(box.controller.bar.selecting)
        box.held.overlay = nil
        box.controller.bar.model.choose(.window)
        await waitUntil("the second overlay opened") { box.held.overlay != nil }
        XCTAssertGreaterThan(try XCTUnwrap(standingBar()).level.rawValue, try XCTUnwrap(overlayLevel(box)).rawValue)
    }

    private func assertBackOnTheGround(_ box: PanelRig.Rig, _ way: String, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertNil(standingBar(), "\(way): the bar is still on a screen", file: file, line: line)
        XCTAssertFalse(box.controller.bar.selecting, "\(way): the bar still believes an overlay is under it", file: file, line: line)
        box.held.overlay = nil
        await waitUntil("\(way): the machine was freed", file: file, line: line) { !box.controller.isBusy }
        box.controller.begin(.panel)
        XCTAssertEqual(standingBar()?.level, .statusBar, "\(way): the next bar opens on the overlay's step", file: file, line: line)
    }

    func testAfterEscTheNextBarOpensOnTheToastsStep() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        try XCTUnwrap(box.held.overlay).rightMouseDown()
        await assertBackOnTheGround(box, "Esc")
    }

    func testAfterTheCloseControlTheNextBarOpensOnTheToastsStep() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        box.controller.bar.model.cancel()
        await assertBackOnTheGround(box, "✕")
    }

    func testAfterAShotTheNextBarOpensOnTheToastsStep() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        PanelRig.drag(try XCTUnwrap(box.held.overlay), on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await waitUntil("the shot was written") { box.disk.written == 1 }
        await assertBackOnTheGround(box, "a shot")
    }

    func testDuringATimedShotsCountdownTheBarIsOnTheToastsStepAndNoOverlayIsUp() async throws {
        let gate = PromptGate()
        let box = try rig(timer: .five, tick: { _ in await gate.arrive() })
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await gate.reached()
        XCTAssertEqual(standingBar()?.level, .statusBar, "the bar counts down on the overlay's step, over another app's menu")
        XCTAssertFalse(overlay.isOpen)
        await gate.open()
        await waitUntil("the shot was written") { box.disk.written == 1 }
        await assertBackOnTheGround(box, "a timed shot")
    }

    func testWhenTheModuleGoesOffTheBarIsGoneAndForgetsTheOverlay() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        box.controller.teardown()
        XCTAssertNil(standingBar())
        XCTAssertFalse(box.controller.bar.selecting)
        XCTAssertFalse(try XCTUnwrap(box.held.overlay).isOpen)
    }

    func testTheShortcutsOverlayHasNoBarAboveItAndNoneIsLeftOver() async throws {
        let box = try rig()
        box.controller.begin(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        XCTAssertNil(standingBar(), "the area shortcut put a bar on the screen")
        XCTAssertEqual(box.held.bars, 0)
        XCTAssertFalse(box.controller.bar.selecting)
    }
}
