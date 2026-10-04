import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The presses nobody makes in a demo, made over the panel's new flow.** Every other control, key and shortcut pressed
/// while a timed shot counts and while the overlay is up; the module switched off while the freeze is out, while it
/// counts and while the overlay flashes; a second mode press while the first freeze is still being taken. One capture at
/// a time: the press is dropped and what is going on goes on.
@MainActor
final class ThePanelMeetsEveryOtherPressTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func rig(timer: CaptureTimer = .none, tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> PanelRig.Rig {
        let box = try PanelRig.rig(timer: timer, tick: tick)
        boxes.append(box)
        return box
    }

    /// A timed area picked and taken, the countdown standing on its first second.
    private func counting() async throws -> (PanelRig.Rig, PromptGate, BarPanel) {
        let gate = PromptGate()
        let box = try rig(timer: .five, tick: { _ in await gate.arrive() })
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        PanelRig.drag(try XCTUnwrap(box.held.overlay), on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await gate.reached()
        XCTAssertEqual(box.controller.bar.model.countdown, 5)
        return (box, gate, box.controller.bar.makePanel())
    }

    func testEveryOtherPressDuringATimedCountdownIsDroppedAndTheShotStillComesOnce() async throws {
        let (box, gate, panel) = try await counting()
        let (overlays, bars, freezes) = (box.held.overlays, box.held.bars, box.screen.freezes)
        let model = box.controller.bar.model
        for mode in [PanelMode.window, .area, .screen, .area] { model.choose(mode) }
        model.toggleTimer(); model.toggleTimer(); model.choose(.ten); model.choose(.five)
        model.capture(model.mode)
        for mode in [PanelMode.screen, .window, .area] { box.controller.capture(from: mode); box.controller.pick(in: mode) }
        panel.keyDown(with: key(36, "\r")); panel.keyDown(with: key(76, "\r"))
        for hotkey in [ScreenshotsHotkey.panel, .area, .fullScreen] { box.controller.begin(hotkey) }
        model.putBack()
        await grace(0.15)
        XCTAssertEqual(box.held.overlays, overlays, "a press during the countdown opened an overlay")
        XCTAssertEqual(box.held.bars, bars, "a shortcut during the countdown put the bar up again")
        XCTAssertEqual(box.screen.freezes, freezes, "a press during the countdown froze the screen")
        XCTAssertEqual(model.countdown, 5, "a press moved the countdown")
        XCTAssertEqual(box.disk.written, 0)
        await gate.open()
        await waitUntil("the shot was written") { box.disk.written == 1 }
        await grace(0.2)
        XCTAssertEqual(box.disk.written, 1, "the presses made a second shot")
        XCTAssertEqual(box.screen.freezes, 2)
    }

    func testEscOnTheBarDuringATimedCountdownEndsItAndTakesNothing() async throws {
        let (box, gate, panel) = try await counting()
        panel.keyDown(with: key(53, "\u{1b}"))
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertEqual(box.screen.freezes, 1, "an Esc left the second freeze to be taken")
        XCTAssertFalse(box.controller.isBusy)
        XCTAssertNil(box.controller.bar.model.countdown)
    }

    func testTheModuleEndingDuringATimedCountdownTakesNothingAndLeavesNoOverlay() async throws {
        let (box, gate, _) = try await counting()
        box.controller.teardown()
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertFalse(box.controller.isBusy)
        XCTAssertFalse(try XCTUnwrap(box.held.overlay).isOpen)
    }

    func testTheOtherShortcutsDuringThePickAreDroppedAndTheOverlayIsTheSame() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        let (overlays, bars) = (box.held.overlays, box.held.bars)
        for hotkey in [ScreenshotsHotkey.panel, .area, .fullScreen] { box.controller.begin(hotkey) }
        box.controller.bar.model.choose(.area)
        await grace(0.15)
        XCTAssertEqual(box.held.overlays, overlays)
        XCTAssertEqual(box.held.bars, bars)
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertTrue(box.held.overlay === overlay)
        XCTAssertTrue(overlay.isOpen)
        XCTAssertTrue(box.controller.bar.model.hasTarget, "pressing Area again threw the area away")
    }

    func testEscOnTheBarAndOnItsReturnWhilePickingDoWhatTheyAreFor() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        let panel = box.controller.bar.makePanel()
        panel.keyDown(with: key(36, "\r"))
        await grace(0.1)
        XCTAssertEqual(box.disk.written, 0, "Return on the bar with nothing drawn took a shot")
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        panel.keyDown(with: key(36, "\r"))
        await waitUntil("Return on the bar took the area") { box.disk.written == 1 }
        await waitUntil("the machine was freed") { !box.controller.isBusy }

        let again = try rig()
        again.controller.begin(.panel)
        again.controller.bar.model.choose(.area)
        await waitUntil("the second overlay opened") { again.held.overlay != nil }
        again.controller.bar.makePanel().keyDown(with: key(53, "\u{1b}"))
        await waitUntil("Esc on the bar freed the machine") { !again.controller.isBusy }
        XCTAssertFalse(try XCTUnwrap(again.held.overlay).isOpen, "Esc on the bar left the overlay up")
    }

    // MARK: - The freeze that has not come back

    private func heldFreeze() async throws -> (PanelRig.Rig, PromptGate) {
        let box = try rig()
        let gate = PromptGate()
        box.screen.hold = { _ in gate }
        return (box, gate)
    }

    func testTheModuleEndingWhileTheFreezeIsOutOpensNoOverlayAndFreesTheMachine() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.teardown()
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 0, "an overlay opened for a module that is off")
        XCTAssertFalse(box.controller.isBusy)
    }

    func testThreeModePressesWhileTheFreezeIsOutMakeOneOverlayInTheLastMode() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.area)
        box.controller.bar.model.choose(.window)
        await gate.open()
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        await grace(0.1)
        XCTAssertEqual(box.held.overlays, 1)
        XCTAssertEqual(box.screen.freezes, 1)
        let overlay = try XCTUnwrap(box.held.overlay)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        XCTAssertTrue(box.controller.bar.model.hasTarget, "the overlay is not in Window mode, the last the person chose")
    }

    func testScreenWhileTheFreezeIsOutOpensNoOverlayAndTheBarStays() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await gate.reached()
        box.controller.bar.model.choose(.screen)
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 0, "Screen was pressed and an overlay opened after all")
        XCTAssertTrue(box.controller.isBusy, "Screen ended the panel")
    }

    /// The person changed their mind twice: Screen, then Window, before the freeze came back. The last press is Window.
    func testScreenThenWindowWhileTheFreezeIsOutStillOpensTheWindowOverlay() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.bar.model.choose(.screen)
        box.controller.bar.model.choose(.window)
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 1, "Window was the last press and nothing opened: the bar shows Window with no overlay behind it")
    }

    // MARK: - Presses with no capture open

    func testAModePressOrCaptureWithNoCaptureOpenFreezesNothing() async throws {
        let box = try rig()
        box.controller.pick(in: .area)
        box.controller.pick(in: .window)
        box.controller.capture(from: .screen)
        box.controller.capture(from: .area)
        box.controller.bar.model.choose(.area)
        await grace(0.2)
        XCTAssertEqual(box.screen.freezes, 0)
        XCTAssertEqual(box.held.overlays, 0)
        XCTAssertFalse(box.controller.isBusy)
    }

    // MARK: - The flash

    func testTheModuleEndingDuringTheFlashClosesTheOverlayAndDeliversNothing() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        box.controller.teardown()
        await grace(0.4)
        XCTAssertFalse(overlay.isOpen, "the flash's panels outlived the module")
        XCTAssertFalse(overlay.leaving)
        XCTAssertEqual(box.disk.written, 0, "a shot was delivered after the module went off")
        XCTAssertFalse(box.controller.isBusy)
    }
}
