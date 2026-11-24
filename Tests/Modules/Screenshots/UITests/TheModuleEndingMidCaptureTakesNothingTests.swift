import AppKit
import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The module switched off while a timed shot counts, while the freeze is out and while the overlay flashes:** nothing
/// is delivered and no overlay is left up.
@MainActor
final class TheModuleEndingMidCaptureTakesNothingTests: XCTestCase {
    /// A timed area picked and taken, the countdown standing on its first second.
    private func counting() async throws -> (PanelRig.Rig, PromptGate, BarPanel) {
        let gate = PromptGate()
        let box = try PanelRig.rig(in: self, timer: .five, tick: { _ in await gate.arrive() })
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        OverlayRig.drag(try XCTUnwrap(box.held.overlay), on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await gate.reached()
        XCTAssertEqual(box.controller.bar.model.countdown, 5)
        return (box, gate, box.controller.bar.makePanel())
    }

    func testTheModuleEndingDuringATimedCountdownTakesNothingAndLeavesNoOverlay() async throws {
        let (box, gate, _) = try await counting()
        XCTAssertNotEqual(box.controller.bar.model.countdownLength, 0, "the ring has no length to clear")
        box.controller.cancel()
        XCTAssertEqual(box.controller.bar.model.countdownLength, 0, "a cut-short ring left its length for the next shot")
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertEqual(box.screen.freezes, 1)
        XCTAssertFalse(box.controller.isBusy)
        XCTAssertFalse(try XCTUnwrap(box.held.overlay).isOpen)
    }

    // MARK: - The freeze that has not come back

    private func heldFreeze() async throws -> (PanelRig.Rig, PromptGate) {
        let box = try PanelRig.rig(in: self)
        let gate = PromptGate()
        box.screen.gate = gate
        return (box, gate)
    }

    func testTheModuleEndingWhileTheFreezeIsOutOpensNoOverlayAndFreesTheMachine() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await gate.reached()
        box.controller.cancel()
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.held.overlays, 0, "an overlay opened for a module that is off")
        XCTAssertFalse(box.controller.isBusy)
    }

    func testTheModuleEndingWhileAFullScreenFreezeIsOutDeliversNothing() async throws {
        let (box, gate) = try await heldFreeze()
        box.controller.begin(.fullScreen)
        await gate.reached()
        box.controller.cancel()
        await gate.open()
        await grace(0.3)
        XCTAssertEqual(box.disk.written, 0, "a full-screen shot was delivered after the module went off")
        XCTAssertFalse(box.controller.isBusy)
    }

    // MARK: - The flash

    func testTheModuleEndingDuringTheFlashClosesTheOverlayAndDeliversNothing() async throws {
        let box = try PanelRig.rig(in: self)
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        OverlayRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        box.controller.cancel()
        // Before any wait: the flash ends by itself, so only the instant after `cancel` tells the module's end from it.
        XCTAssertFalse(overlay.isOpen, "the flash's panels outlived the module")
        XCTAssertFalse(overlay.leaving)
        await grace(0.4)
        XCTAssertFalse(overlay.isOpen, "the flash's panels outlived the module")
        XCTAssertEqual(box.disk.written, 0, "a shot was delivered after the module went off")
        XCTAssertFalse(box.controller.isBusy)
    }
}
