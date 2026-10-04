import AppKit
import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **From the pick to the first second the panel keeps the width it had with the target.** `overlayFinished` lets the
/// target go (`hasTarget = false`) before the countdown starts, in Area and Window mode alike; if the room Capture took
/// went with it for a turn, the panel would shrink under the pointer and widen again when the ring came. The real window
/// is made (never ordered in) and every resize it gets is written down, from the target appearing through the ring.
@MainActor
final class ThePanelDoesNotShrinkBetweenThePickAndTheCountdownTests: XCTestCase {

    private func run(mode: PanelMode) async throws {
        let box = try PanelRig.rig(timer: .five, values: [ScreenshotsSettings.Key.panelMode: mode.rawValue], tick: { _ in try await Task.sleep(for: .seconds(60)) })
        let bar = box.controller.bar
        let panel = bar.makePanel()
        panel.setContentSize(try XCTUnwrap(panel.contentView).fittingSize)
        var widths: [CGFloat] = [panel.frame.width]
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { widths.append(panel.frame.width) }
        }
        defer { NotificationCenter.default.removeObserver(observer); box.controller.cancel() }
        let rest = widths[0]

        box.controller.begin(.panel)
        bar.model.choose(mode)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        if mode == .window {
            overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        } else {
            PanelRig.drag(overlay, on: box.display, PanelRig.area)
        }
        await waitUntil("the target made room for Capture") { bar.model.hasTarget && panel.frame.width > rest + 40 }
        let wide = panel.frame.width
        let before = widths.count
        box.controller.capture(from: mode == .window ? .window : .area)
        await waitUntil("the countdown began") { bar.model.countdown != nil }
        // Let the target's release and the ring both reach the window.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(bar.model.hasTarget, "\(mode): the target was not let go; the check watched nothing")
        XCTAssertEqual(panel.frame.width, wide, accuracy: 0.5, "\(mode): the ring runs at another width than the target's")
        XCTAssertEqual(Array(widths[before...]), [], "\(mode): the window was resized between the pick and the ring: \(widths[before...]) (was \(wide))")
    }

    func testAreaKeepsItsWidthFromThePickToTheRing() async throws { try await run(mode: .area) }
    func testWindowKeepsItsWidthFromThePickToTheRing() async throws { try await run(mode: .window) }

    /// A Esc (`cancel`) that lands in the turn of the pick, before the countdown's task has begun, leaves nothing of the
    /// ring behind: the next time the bar opens there is no countdown on it and no room kept for one.
    func testACancelInTheTurnOfThePickLeavesNoRingForTheNextOpening() async throws {
        let box = try PanelRig.rig(timer: .five, values: [ScreenshotsSettings.Key.panelMode: PanelMode.area.rawValue], tick: { _ in try await Task.sleep(for: .seconds(60)) })
        let bar = box.controller.bar
        defer { box.controller.cancel() }
        box.controller.begin(.panel)
        bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        PanelRig.drag(try XCTUnwrap(box.held.overlay), on: box.display, PanelRig.area)
        await waitUntil("the target made room for Capture") { bar.model.hasTarget }
        box.controller.capture(from: .area)
        // No suspension since the press: the task that counts has not begun.
        XCTAssertNotNil(bar.model.countdown, "the pick did not start the ring in its own turn; the check watched nothing")
        box.controller.cancel()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(bar.model.countdown, "a cancel before the countdown's task began left its ring on the closed bar")
        XCTAssertEqual(bar.model.countdownLength, 0, "a cancel before the countdown's task began left its length on the closed bar")
        XCTAssertFalse(bar.model.counting)
    }
}
