// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
@testable import HelmUI

/// The inputs `WindowSeenReaderRaceTests` did not feed `WindowSeenReader.Reader`.
///
/// That file drives one direction of the race the first-open unmount was made
/// of: a window that is **not** on screen when `report()` is called and **is**
/// by the time the queued block runs. Reading the window inside the hop rather than
/// before it is a two-sided change, and a bound proved from one side only is
/// unproved from the other — so the cases here are the brothers of that one:
///
/// - the window genuinely goes away *during* the hop (the fix must not have
///   made the reader blind to a real `orderOut`);
/// - the view leaves its window during the hop, which is the `?? true` the
///   render harnesses stand on, reached through `viewDidMoveToWindow` rather
///   than by calling `report()` on a bare view;
/// - the view moves to a **different** window during the hop, so "the window"
///   the delivery answers for is not the one the call was made in;
/// - **two** readers in one window — the shape the app actually mounts
///   (`SettingsWindow.swift:207` and `:288`, sidebar and detail), and the
///   reason the measured trace showed the unmount landing twice per launch.
///
/// Every case above is red against the pre-fix `report()`, which sampled
/// `window.isVisible` before `DispatchQueue.main.async`, as is the three-round
/// case. Two cases in this file are not, and say so in their own comments:
/// `testTheOcclusionObserverMovesWithTheViewAndLeavesTheOldWindow` and
/// `testABenchedSubtreeMountsNoWindowReaderWhileAnUnbenchedOneDoes` guard
/// bookkeeping the fix did not touch and which nothing in this tree covered.
///
/// Nothing here reads a visible string, so no case is parameterised by
/// language; the subject is an AppKit window level, which has none.
@MainActor
final class TheWindowReaderAnswersAtDeliveryTests: XCTestCase {

    // MARK: - Plumbing

    private func freshWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// Wall-clock, run-loop time — **not** `Task.yield()`, which buys a turn on
    /// the cooperative pool and no milliseconds at all, so no number of them
    /// widens the window a queued block can land in. `wait(for:)` spins the
    /// main run loop, and the main queue is FIFO: a block enqueued before this
    /// one has run by the time this one fulfils.
    private func drainMainQueue(_ turns: Int = 1) {
        for turn in 0..<turns {
            let done = expectation(description: "main queue drained, turn \(turn)")
            DispatchQueue.main.async { done.fulfill() }
            wait(for: [done], timeout: 5)
        }
    }

    /// A reader with its deliveries collected, mounted nowhere yet.
    private func reader(into reported: Recorder) -> WindowSeenReader.Reader {
        let reader = WindowSeenReader.Reader(frame: .zero)
        reader.onChange = { reported.values.append($0) }
        return reader
    }

    /// A box, so a reader's closure can write where an assertion can read
    /// without capturing a `var` the compiler will not let escape.
    private final class Recorder {
        var values: [Bool] = []
    }

    // MARK: - The window that really does go away during the hop

    /// **The other direction of the fix.** A reader mounted in a window that is
    /// on screen queues a report; the window is ordered out before the queued
    /// block runs. The report that lands must say the window is gone.
    ///
    /// Pre-fix this read `true` at call time and delivered that — which happens
    /// to be the answer a person wants in this test's *first* moment and the
    /// wrong one by the time it arrives. A fix that had simply pinned the
    /// answer to "seen" — or dropped the read — would pass the race test in
    /// `WindowSeenReaderRaceTests` and fail here, which is what this case is
    /// for: the subtree must still unmount when Settings is actually closed.
    func testAWindowOrderedOutDuringTheHopIsReportedGone() {
        let window = freshWindow()
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible, "the window has to be on screen for this to be the other direction")

        let reported = Recorder()
        let reader = reader(into: reported)
        window.contentView?.addSubview(reader)
        XCTAssertTrue(reported.values.isEmpty, "the report must not have delivered synchronously")

        // The fact the queued block will read, changed between the call and the
        // delivery: this is Settings being closed.
        window.orderOut(nil)
        XCTAssertFalse(window.isVisible, "orderOut did not take the window off screen; this test drives nothing")

        drainMainQueue()

        XCTAssertFalse(reported.values.isEmpty,
                       "no report was delivered at all, so the assertion below would pass on silence")
        XCTAssertEqual(reported.values.first, false,
                       "the reader answered for the window as it was when report() was called, not as it "
                       + "was when the report arrived — a window ordered out mid-hop went unreported and "
                       + "the subtree stayed mounted behind a closed window")
        XCTAssertEqual(reported.values.last, false,
                       "the settled answer after a close must be 'not seen'")
    }

    // MARK: - No window, reached the way the app reaches it

    /// The `?? true` the offscreen render harnesses stand on
    /// (`Tests/Support/RenderedInk.swift:235`,
    /// `Tests/HelmAppTests/ModulePageRender.swift:282`), driven through
    /// `viewDidMoveToWindow` rather than by calling `report()` on a view that
    /// never had a window — a different call site, and the only one the app
    /// itself ever takes.
    ///
    /// Red pre-fix for a reason worth stating: the reader is taken out of an
    /// **invisible** window, so the stale sample was `false` where the correct
    /// answer at delivery is "no window, therefore draw".
    func testAReaderTakenOutOfItsWindowDuringTheHopAnswersTrue() {
        let window = freshWindow()
        let reported = Recorder()
        let reader = reader(into: reported)
        window.contentView?.addSubview(reader)
        XCTAssertFalse(window.isVisible, "the window must still be unordered when the report is queued")
        XCTAssertNotNil(reader.window, "the reader has to have been in a window for its removal to mean anything")

        reader.removeFromSuperview()
        XCTAssertNil(reader.window, "the reader is still in a window; this test drives nothing")

        drainMainQueue()

        XCTAssertFalse(reported.values.isEmpty, "no report was delivered at all")
        XCTAssertEqual(reported.values.first, true,
                       "a view with no window must count as seen — a bare harness view that declined to "
                       + "draw is a measurement of nothing")
        XCTAssertEqual(Set(reported.values), [true],
                       "every report from a window-less reader must be 'seen'")
    }

    // MARK: - A view that changes windows between the call and the delivery

    /// A reader whose view moves to a **different** window during the hop. The
    /// delivery must answer for the window the view is in when it lands, not
    /// for the one it was in when the call was made.
    ///
    /// The app moves hosting views between windows (a page taken from Settings
    /// into a panel), and the pre-fix reader answered with a window it had
    /// already left.
    func testAReaderMovedToAnotherWindowDuringTheHopAnswersForTheNewOne() {
        let closed = freshWindow()
        let open = freshWindow()
        open.makeKeyAndOrderFront(nil)
        XCTAssertFalse(closed.isVisible)
        XCTAssertTrue(open.isVisible, "the destination window has to be on screen")

        let reported = Recorder()
        let reader = reader(into: reported)
        closed.contentView?.addSubview(reader)
        XCTAssertTrue(reported.values.isEmpty, "the report must not have delivered synchronously")

        reader.removeFromSuperview()
        open.contentView?.addSubview(reader)
        XCTAssertEqual(reader.window, open, "the reader did not move; this test drives nothing")

        drainMainQueue()

        XCTAssertFalse(reported.values.isEmpty, "no report was delivered at all")
        XCTAssertEqual(reported.values.first, true,
                       "the reader answered for the window it was in when report() was called, which it "
                       + "has since left, rather than for the window it is in now")
    }

    // MARK: - Two readers, which is what the app mounts

    /// Settings mounts this modifier on both panes, so both readers take the
    /// first-open race at once — which is why the measured trace showed the
    /// unmount land twice. One reader proving the fix proves it for one pane.
    func testBothPanesReadersSeeTheOpeningRatherThanTheStateBeforeIt() {
        let window = freshWindow()
        let sidebar = Recorder()
        let detail = Recorder()
        let sidebarReader = reader(into: sidebar)
        let detailReader = reader(into: detail)

        window.contentView?.addSubview(sidebarReader)
        window.contentView?.addSubview(detailReader)
        XCTAssertFalse(window.isVisible, "both readers must mount before the window is ordered in")
        XCTAssertTrue(sidebar.values.isEmpty && detail.values.isEmpty,
                      "neither report may have delivered synchronously")

        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible)

        drainMainQueue()

        XCTAssertFalse(sidebar.values.isEmpty, "the sidebar reader delivered nothing at all")
        XCTAssertFalse(detail.values.isEmpty, "the detail reader delivered nothing at all")
        XCTAssertEqual([sidebar.values.first, detail.values.first], [true, true],
                       "a pane read the window as it was before it opened, so its subtree unmounted after "
                       + "the window was already correct — the first-open unmount, once per pane")
    }

    // MARK: - Repeated openings, which is where the defect hid

    /// The defect was reported as "only the first time", which is a statement
    /// about how often the race is *lost*, not about which openings can lose
    /// it. Three consecutive close-and-open rounds, each with the report queued
    /// before the level changes and delivered after: every one must land on the
    /// level the window has when it arrives, in both directions.
    ///
    /// The poll is entered through `report()` directly rather than through the
    /// occlusion notification the app uses, because this process never gets
    /// one: measured in a throwaway probe under `bash Scripts/test.sh`, a
    /// window here goes `isVisible` true and false while
    /// `didChangeOcclusionStateNotification` is posted **zero** times and
    /// `occlusionState` stays `.visible` throughout. The window server is not
    /// answering a plain `swift test` process. `viewDidMoveToWindow` and
    /// `report()` are the two entry points that do work here, and they are
    /// the ones every case in this file uses.
    func testThreeConsecutiveRoundsEachLandOnTheLevelAtDelivery() {
        let window = freshWindow()
        let reported = Recorder()
        let reader = reader(into: reported)
        window.contentView?.addSubview(reader)
        drainMainQueue()
        let afterMount = reported.values.count
        XCTAssertGreaterThan(afterMount, 0, "mounting delivered no report at all")

        for pass in 1...3 {
            let beforeOpening = reported.values.count
            reader.report()
            window.makeKeyAndOrderFront(nil)
            XCTAssertTrue(window.isVisible, "pass \(pass): the window is not on screen")
            drainMainQueue()
            XCTAssertGreaterThan(reported.values.count, beforeOpening,
                                 "pass \(pass): the opening produced no report, so the level below is "
                                 + "whatever was left over from the previous round")
            XCTAssertEqual(reported.values.last, true,
                           "pass \(pass): a report queued before the window opened landed after it had, "
                           + "carrying the level from before — the subtree unmounts behind a window that "
                           + "is on screen, and the toolbar is rebuilt when it comes back")

            let beforeClosing = reported.values.count
            reader.report()
            window.orderOut(nil)
            XCTAssertFalse(window.isVisible, "pass \(pass): the window is still on screen")
            drainMainQueue()
            XCTAssertGreaterThan(reported.values.count, beforeClosing,
                                 "pass \(pass): the closing produced no report")
            XCTAssertEqual(reported.values.last, false,
                           "pass \(pass): a report queued before the window closed landed after it had "
                           + "and still called it 'seen', so the subtree stays mounted behind a closed "
                           + "window and goes on paying for every published change")
        }
    }

    // MARK: - Which window the observer is on after the view moves

    /// **Not a guard of the fix** — the observer bookkeeping is untouched by it.
    ///
    /// `viewDidMoveToWindow` takes the reader's occlusion observer off the
    /// window it has left and puts one on the window it has joined. Nothing in
    /// this tree checked that the first half happens, and a reader left
    /// observing a window it is no longer in is a subscription that outlives
    /// its subject — the shape `CLAUDE.md` asks about by name ("which event
    /// clears it").
    ///
    /// The notification is posted by hand because this process is never sent
    /// one (see the round-trip case above), which is also why the *positive*
    /// half is here: without it this would pass on a reader that observes
    /// nothing at all.
    func testTheOcclusionObserverMovesWithTheViewAndLeavesTheOldWindow() {
        let first = freshWindow()
        let second = freshWindow()
        second.makeKeyAndOrderFront(nil)

        let reported = Recorder()
        let reader = reader(into: reported)
        first.contentView?.addSubview(reader)
        reader.removeFromSuperview()
        second.contentView?.addSubview(reader)
        drainMainQueue()

        let settled = reported.values.count
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: first)
        drainMainQueue()
        XCTAssertEqual(reported.values.count, settled,
                       "the reader still answers occlusion from a window it has left — the observer "
                       + "registered in viewDidMoveToWindow was not removed when the view moved on")

        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: second)
        drainMainQueue()
        XCTAssertEqual(reported.values.count, settled + 1,
                       "the reader did not answer its own window's occlusion either, so the assertion "
                       + "above passed on a reader that observes nothing")
        XCTAssertEqual(reported.values.last, true, "the window it is in is on screen")
    }

    // MARK: - The branch with no reader in it at all

    /// **Not a guard of the fix** — this passes against the pre-fix `report()`
    /// too, and it is here because nothing in this tree covered it.
    ///
    /// `helmMeasuringBench()` must mount **no** reader, not merely start it at
    /// "seen": `ImageRenderer`, which one geometry probe draws through, renders
    /// a subtree holding any `NSViewRepresentable` as transparent, and a pixel
    /// walk reads transparency as ink at x = 0. The control below is what makes
    /// this fail rather than pass on an empty walk — without the bench, a
    /// reader is there.
    func testABenchedSubtreeMountsNoWindowReaderWhileAnUnbenchedOneDoes() {
        func readersUnder<V: View>(_ view: V) -> Int {
            let host = NSHostingView(rootView: AnyView(view.frame(width: 40, height: 40)))
            let window = freshWindow()
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
            window.layoutIfNeeded()
            return host.everyView(ofType: WindowSeenReader.Reader.self).count
        }

        let unbenched = readersUnder(Color.clear.helmIdlesOffScreen())
        XCTAssertGreaterThan(unbenched, 0,
                             "the control found no reader either, so the bench assertion below would pass "
                             + "on a walk that sees nothing")

        XCTAssertEqual(readersUnder(Color.clear.helmIdlesOffScreen().helmMeasuringBench()), 0,
                       "a benched subtree mounted a window reader — ImageRenderer renders a subtree "
                       + "holding an NSViewRepresentable as transparent, which a pixel walk reads as ink "
                       + "at x = 0")
    }
}
