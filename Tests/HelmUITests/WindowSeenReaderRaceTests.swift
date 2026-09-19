// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import XCTest
@testable import HelmUI

/// **On a run's first Settings open, both panes unmounted and remounted for
/// nothing.**
///
/// Measured trace: `viewDidMoveToWindow` fires while the window has not yet
/// been ordered front (`isVisible == false`), and `report()` queues that
/// reading onto the main queue. By the time the queued block ran — about
/// 220 ms later — the window had already opened correctly. The stale `false`
/// landed anyway, `seen` flipped `true → false`, both panes unmounted, and the
/// next report flipped `seen` back, rebuilding both subtrees and the toolbar
/// they carry from scratch.
///
/// **What that cost a person was never photographed, and no sentence here may
/// claim it was.** First-open recordings at 60 fps, of a build with this fix
/// and a build without it, hold no frame where the toolbar's height differs:
/// the menu bar item does not appear for seconds after launch, by which time
/// this race has long resolved. The mechanism above is measured; the visible
/// consequence is not.
///
/// **What this test drives is the race itself, not the toolbar rebuild
/// downstream of it**: `report()` reading `window.isVisible` before the hop to the main
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
    /// reader that samples at call time delivers the stale `false` this race
    /// was made of; one that samples at delivery time — the fix — delivers the
    /// window's current `true`. Asserting on the *first* delivered value rather
    /// than on the whole list is what keeps this case about the race and
    /// nothing else: in the app the window's own occlusion notification queues
    /// further reports of its own, and in a `swift test` process it never
    /// fires at all (measured — `TheWindowReaderAnswersAtDeliveryTests` records
    /// the probe), so how many reports land is not a fact this test controls.
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
    /// call and the delivery, so the level read either way is the same. Exactly
    /// one report lands, because `viewDidMoveToWindow` is the only thing that
    /// calls `report()` here: this process is never sent an occlusion
    /// notification at all (measured — see the case above).
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

    /// No window at all counts as seen — the `?? true` in `report()` and the
    /// load-bearing comment above it in `OffScreenIdle.swift`, named rather
    /// than numbered because the line moved under the fix that made this file
    /// necessary — and that must survive reading inside the hop as much as it
    /// did reading before it.
    func testReportWithNoWindowDeliversTrue() {
        let reader = WindowSeenReader.Reader(frame: .zero)
        var reported: [Bool] = []
        reader.onChange = { reported.append($0) }
        reader.report()

        drainMainQueue()

        XCTAssertEqual(reported, [true])
    }
}
