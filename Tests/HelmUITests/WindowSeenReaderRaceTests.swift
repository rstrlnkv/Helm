// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import XCTest
@testable import HelmUI

/// **The first Settings open of a run dipped from a 52 pt toolbar strip to
/// 32 pt and back, once per pane, only on the first open.**
///
/// Measured trace: `viewDidMoveToWindow` fires while the window has not yet
/// been ordered front (`isVisible == false`), and `report()` queues that
/// reading onto the main queue. By the time the queued block ran — about
/// 220 ms later — the window had already opened correctly. The stale `false`
/// landed anyway, `seen` flipped `true → false`, both panes unmounted, and the
/// genuine occlusion notification a few milliseconds later flipped `seen` back,
/// rebuilding the toolbar from scratch. That rebuild is the dip.
///
/// **What this test drives is the race itself, not the toolbar it eventually
/// moves**: `report()` reading `window.isVisible` before the hop to the main
/// queue rather than inside it. A `Reader` is built directly — internal, not
/// private, for exactly this — and the race is reproduced by calling
/// `report()` while the window is not yet visible and then making it visible
/// before the queued block has had a chance to run.
@MainActor
final class WindowSeenReaderRaceTests: XCTestCase {

    private func freshWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// Drains one turn of the main queue so a `DispatchQueue.main.async` block
    /// queued earlier in this test gets a chance to run, without giving the
    /// window's own occlusion notification a turn it was not asked for.
    private func drainMainQueue() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    /// **The finding itself.** `viewDidMoveToWindow` calls `report()` while the
    /// window is not yet on screen — the window becomes visible before that
    /// call's queued delivery runs, which is the measured trace above. A
    /// reader that samples at call time delivers the stale `false` this
    /// dip was made of; one that samples at delivery time — the fix — delivers
    /// the window's current `true`. The window's own occlusion notification
    /// then queues a second, genuine report once it fires; asserting on the
    /// *first* delivered value is what isolates the race from that second,
    /// unrelated call, whose timing this test does not control.
    func testReportReadsTheWindowAtDeliveryNotAtCallTime() {
        let window = freshWindow()
        let reader = WindowSeenReader.Reader(frame: .zero)
        var reported: [Bool] = []
        reader.onChange = { reported.append($0) }

        // Mounting queues report() #1 while the window is not on screen — the
        // exact moment `viewDidMoveToWindow` fires at t+188.7ms in the trace.
        window.contentView = reader
        XCTAssertFalse(window.isVisible, "the window must not be on screen yet for this race to exist")
        XCTAssertTrue(reported.isEmpty, "the queued report must not have delivered synchronously")

        // Mutate the fact report() #1 will read, before its queued block runs —
        // exactly the window opening between the stale sample and its delivery.
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible)

        drainMainQueue()

        XCTAssertEqual(reported.first, true,
                       "report() delivered a value it read before the hop to the main queue "
                       + "rather than the window's state at delivery, so a stale reading from "
                       + "before the window opened overwrote the correct one")
    }

    /// The ordinary case this fix must not disturb: nothing changes between the
    /// call and the delivery, so the level read either way is the same, and no
    /// occlusion state change fires because the window is already visible —
    /// so exactly one report lands, unlike the race test above.
    func testReportOnAnAlreadyVisibleWindowDeliversTrue() {
        let window = freshWindow()
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible)

        let reader = WindowSeenReader.Reader(frame: .zero)
        var reported: [Bool] = []
        reader.onChange = { reported.append($0) }
        window.contentView = reader

        drainMainQueue()

        XCTAssertEqual(reported, [true])
    }

    /// No window at all counts as seen — the bare harness case load-bearing
    /// comment at `OffScreenIdle.swift:137` — and that must survive reading
    /// inside the hop as much as it did reading before it.
    func testReportWithNoWindowDeliversTrue() {
        let reader = WindowSeenReader.Reader(frame: .zero)
        var reported: [Bool] = []
        reader.onChange = { reported.append($0) }
        reader.report()

        drainMainQueue()

        XCTAssertEqual(reported, [true])
    }
}
