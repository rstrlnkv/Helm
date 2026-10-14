import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A display that comes or goes ends the capture on the panel at every stage before the picture is being taken, and says
/// so.** The notification is `NSApplication.didChangeScreenParametersNotification`, posted in the test process on the default
/// centre as AppKit posts it; no display of the Mac is changed and no window moves. Each case of a stage puts the panel in
/// it, posts, and reads what is wanted: the press is over (the controller is free, the bar's model is reset, the overlay is
/// closed, the next press opens a bar again), nothing more was taken (no second freeze, nothing written, nothing in the
/// after-shot window but what was there), and the after-shot window holds the plaque. The stages are an overlay open to pick
/// a window, an overlay open to pick an area and the same with an area drawn, the Screen mode with no overlay, and the
/// countdowns: Screen's, an area's after the pick, a window's after the pick.
///
/// A countdown is held on a clock that stands still (`DisplayChange.Clock`): the notification comes in the middle of a
/// second, then the clock is opened and every second after it passes at once. The case then reads that the clock was asked
/// for one second only, and that no freeze, no window ask and no write came after it. The reading waits for the held second
/// to come back first, so the absences are read after the thing that would have broken them had its chance; a fixed pause
/// follows it.
///
/// **Which call ends it.** The module's end (`teardown`) dismisses the after-shot window and closes the pins; a press's end
/// (`cancel`) leaves both. `testAShotAlreadyInTheWindowBeforeTheChangeIsThereAfterIt` reads that a shot in the window before
/// the change is in it after; `testCancelLeavesTheShotAndTeardownTakesItOut` answers the same notification with `cancel` on
/// one controller and `teardown` on another: the shot stays in the first window and is gone from the second.
///
/// The panel is a controller over fake ports whose bar seam puts nothing on a screen (`PanelRig.rig`), so "the bar is
/// closed" is read from what closing resets in its model, and the next press is what shows the controller is free.
/// `testTheMovedFlagIsReadAndTurnsOnAMoveOfThePanel` and `testTheNotificationAloneMovesNothingAndStoresNoOffset` read the
/// bar's moved flag: posting the notification moves no panel, so what they show is that nothing of the controller or the
/// bar sets that flag by itself, and not what AppKit does with a panel when the desk changes. The first of them builds the
/// bar's panel without ordering it in and posts the move notification for it, and the flag turns: the reading is not looking
/// at nothing.
///
/// **Outside a press, and once one is over.** The controller's `displayObserver` is read through a mirror: nil with no press
/// under way, set while one is (the control), nil again after `cancel` (the call the bar's close control makes), Esc on an
/// overlay, a taken shot and the change itself. Posted outside a press, after Esc, after a taken shot and a second time after
/// the change, the notification is asserted to give the window no plaque; the next press after a change is asserted to be
/// heard, one plaque for each change.
///
/// **When the picture is already being taken.** A change while the shortcut's freeze is held, and one after the countdown
/// has run out with the freeze held, are asserted to let the shot be written and to give the window no plaque. A change in the
/// fifth second of five ends the press with the plaque and nothing taken. A change in the same turn that lets the fifth second
/// go is asserted to leave one outcome whole (a shot and no plaque, or a plaque and no shot), which of the two is not asked.
/// A shortcut cancelled before its task's body ran, the panel opened and Window chosen on it in the same turn, then a change
/// with that panel's overlay open: the press is asserted to end, with the plaque for a capture that was not taken.
/// Every plaque is counted as the window is given it, and the title and the sentence are asserted through `DisplayChange`.
///
/// **Which row was shown red by taking a piece of the fix back.** `displayChanged` calling `teardown` where it calls `cancel`:
/// `testAShotAlreadyInTheWindowBeforeTheChangeIsThereAfterIt` and `testCancelLeavesTheShotAndTeardownTakesItOut`. `busy`'s
/// `didSet` leaving the observer in place when the press ends: `testOutsideACaptureTheNotificationSaysNothingAndNobodyListens`,
/// `testAPressThatEndedByEscOrByATakenShotLeavesNoListenerAndNoPlaqueFollows` and
/// `testEachChangeIsOnePlaqueAndTheNextPressIsHeardAgain` (all three by the mirror read of `displayObserver`; a leftover
/// observer is harmless to the plaque count, because the `busy` guard stops it). The `delivering` guard gone:
/// `testAChangeWhileTheShortcutIsFreezingTheScreenLetsTheShotBeTakenAndSaysNothing` and
/// `testAChangeAfterTheLastSecondHasRunOutLetsTheShotBeTaken`. The sentence of `.displayChanged` answering `.displayGone`'s:
/// `testAnAreaBeingPickedEndsAndTheWindowSaysSo`. `fullScreen` writing `delivering` and `busy` without asking whether its
/// task was cancelled: `testAShortcutCancelledBeforeItsTaskRanDoesNotDeafenTheNextPress`. The other rows of this family
/// assert what their text says; none of the pieces taken back turned them red.
///
/// Total failure of the subject prints: a precondition line that says the stage was not reached (no overlay, no ring, no
/// shot in the window to start from); otherwise the expectations: a controller still busy, an overlay still open, a ring
/// still counting, a clock asked for more than one second, a freeze or a file after the notification, an empty window where
/// a shot stood, no plaque.
@MainActor
final class TheCaptureEndsWhenADisplayComesOrGoesTests: XCTestCase {
    typealias Rig = PanelRig.Rig

    private var boxes: [Rig] = []
    private var clocks: [DisplayChange.Clock] = []
    private var plaques: [ObjectIdentifier: DisplayChange.Plaques] = [:]

    override func tearDown() async throws {
        for clock in clocks { await clock.open() }
        for box in boxes { box.controller.teardown() }
        clocks = []
        boxes = []
        plaques = [:]
        try await super.tearDown()
    }

    private struct PreconditionFailed: Error {}

    private func require(_ ok: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard ok else {
            XCTFail("precondition: \(message)", file: file, line: line)
            throw PreconditionFailed()
        }
    }

    private func rig(timer: CaptureTimer = .none, thumbnail: Bool = false, clock: DisplayChange.Clock? = nil) throws -> Rig {
        let box = try PanelRig.rig(timer: timer, values: [ScreenshotsSettings.Key.thumbnail: thumbnail], tick: clock?.tick ?? DisplayChange.Clock.idle)
        boxes.append(box)
        plaques[ObjectIdentifier(box.controller)] = DisplayChange.Plaques(box.controller.toast)
        return box
    }

    /// Every plaque the box's window was given, counted from the box's birth.
    private func given(_ box: Rig) -> DisplayChange.Plaques { plaques[ObjectIdentifier(box.controller)]! }

    /// The plaque of a press that was under way: titled for a capture that was not taken, once.
    private func assertPlaque(_ box: Rig, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        DisplayChange.assertPlaque(of: box.controller.toast, given(box), what, titled: .notTaken, file: file, line: line)
    }

    private func clock() -> DisplayChange.Clock {
        let clock = DisplayChange.Clock()
        clocks.append(clock)
        return clock
    }

    /// The panel is up in `mode`; for Window and Area the panel's overlay is open on a freeze (the first), picking.
    @discardableResult
    private func panelUp(_ box: Rig, in mode: PanelMode) async throws -> CaptureOverlay? {
        box.controller.begin(.panel)
        box.controller.bar.model.choose(mode)
        try require(box.controller.isBusy && box.held.bars == 1, "the panel did not come up")
        guard mode != .screen else {
            try require(box.held.overlay == nil && !box.controller.bar.selecting, "an overlay is open in Screen mode")
            return nil
        }
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        let overlay = try XCTUnwrap(box.held.overlay)
        try require(overlay.isOpen && box.controller.bar.selecting && box.screen.freezes == 1, "the picking overlay is not open on one freeze")
        return overlay
    }

    /// The press is over, as the bar's close control or Esc leaves it, and the next press is taken.
    private func assertEnded(_ box: Rig, _ overlay: CaptureOverlay?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let bar = box.controller.bar
        XCTAssertFalse(box.controller.isBusy, "\(what): the controller is still busy with the capture", file: file, line: line)
        if let overlay { XCTAssertFalse(overlay.isOpen, "\(what): the overlay is still open", file: file, line: line) }
        XCTAssertFalse(bar.selecting, "\(what): the bar still stands over a picking overlay", file: file, line: line)
        XCTAssertFalse(bar.model.hasTarget, "\(what): the bar still holds a target", file: file, line: line)
        XCTAssertFalse(bar.model.counting, "\(what): the ring is still counting", file: file, line: line)
        XCTAssertEqual(bar.model.countdownLength, 0, "\(what): the ring's length is left behind", file: file, line: line)
        box.controller.begin(.panel)
        XCTAssertEqual(box.held.bars, 2, "\(what): the next press was dropped, so no bar came up again", file: file, line: line)
    }

    /// Nothing was taken or written for a press that was over, and nothing stands in the window but the plaque.
    private func assertNothingWasTaken(_ box: Rig, freezes: Int, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(box.screen.freezes, freezes, "\(what): the screen was frozen again", file: file, line: line)
        XCTAssertEqual(box.screen.windowAsks, 0, "\(what): a window was asked for", file: file, line: line)
        XCTAssertEqual(box.disk.written, 0, "\(what): a file was written", file: file, line: line)
        XCTAssertTrue(box.controller.toast.model.shots.isEmpty, "\(what): the window holds a shot", file: file, line: line)
    }

    // MARK: The overlay open to pick

    func testAWindowBeingPickedEndsAndTheWindowSaysSo() async throws {
        let box = try rig()
        let overlay = try await panelUp(box, in: .window)
        await DisplayChange.happens()
        assertEnded(box, overlay, "Window picking")
        assertNothingWasTaken(box, freezes: 1, "Window picking")
        assertPlaque(box, "Window picking")
    }

    func testAnAreaBeingPickedEndsAndTheWindowSaysSo() async throws {
        let box = try rig()
        let overlay = try await panelUp(box, in: .area)
        await DisplayChange.happens()
        assertEnded(box, overlay, "Area picking")
        assertNothingWasTaken(box, freezes: 1, "Area picking")
        assertPlaque(box, "Area picking")
    }

    func testAnAreaDrawnAndNotYetTakenEndsAndTheWindowSaysSo() async throws {
        let box = try rig()
        let picking = try await panelUp(box, in: .area)
        let overlay = try XCTUnwrap(picking)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        try require(box.controller.bar.model.hasTarget, "the drawn area is no target of the bar")
        await DisplayChange.happens()
        assertEnded(box, overlay, "Area drawn")
        assertNothingWasTaken(box, freezes: 1, "Area drawn")
        assertPlaque(box, "Area drawn")
    }

    // MARK: Screen mode, no overlay

    func testThePanelInScreenModeEndsAndTheWindowSaysSo() async throws {
        let box = try rig()
        try await panelUp(box, in: .screen)
        await DisplayChange.happens()
        assertEnded(box, nil, "Screen mode")
        assertNothingWasTaken(box, freezes: 0, "Screen mode")
        assertPlaque(box, "Screen mode")
    }

    // MARK: A countdown

    /// The notification comes in the middle of the first second; then the clock is opened and runs out.
    private func runTheClockOut(_ clock: DisplayChange.Clock) async {
        await clock.open()
        await waitUntil("the held second came back") { clock.returned >= 1 }
        await grace(0.25)
    }

    func testTheScreenCountdownEndsAndNothingIsTakenAfterTheLastSecond() async throws {
        let clock = clock()
        let box = try rig(timer: .five, clock: clock)
        try await panelUp(box, in: .screen)
        box.controller.capture(from: .screen)
        await clock.reached()
        try require(box.controller.bar.model.counting && clock.calls == 1, "the ring is not running on the first second")

        await DisplayChange.happens()
        assertEnded(box, nil, "Screen countdown")
        assertPlaque(box, "Screen countdown")

        await runTheClockOut(clock)
        XCTAssertEqual(clock.calls, 1, "Screen countdown: the clock was asked for \(clock.calls) seconds, the ring went on after the change")
        assertNothingWasTaken(box, freezes: 0, "Screen countdown, after the last second")
    }

    func testAnAreaCountdownAfterThePickEndsAndNothingIsTakenAfterTheLastSecond() async throws {
        let clock = clock()
        let box = try rig(timer: .five, clock: clock)
        let picking = try await panelUp(box, in: .area)
        let overlay = try XCTUnwrap(picking)
        PanelRig.drag(overlay, on: box.display, PanelRig.area)
        box.controller.capture(from: .area)
        await clock.reached()
        try require(box.controller.bar.model.counting && clock.calls == 1 && !overlay.isOpen, "the ring is not running on the first second of a picked area")

        await DisplayChange.happens()
        assertEnded(box, nil, "Area countdown")
        assertPlaque(box, "Area countdown")

        await runTheClockOut(clock)
        XCTAssertEqual(clock.calls, 1, "Area countdown: the clock was asked for \(clock.calls) seconds, the ring went on after the change")
        assertNothingWasTaken(box, freezes: 1, "Area countdown, after the last second")
    }

    func testAWindowCountdownAfterThePickEndsAndNothingIsTakenAfterTheLastSecond() async throws {
        let clock = clock()
        let box = try rig(timer: .five, clock: clock)
        let picking = try await panelUp(box, in: .window)
        let overlay = try XCTUnwrap(picking)
        overlay.mouseMoved(on: box.display, at: CGPoint(x: 150, y: 150))
        box.controller.capture(from: .window)
        await clock.reached()
        try require(box.controller.bar.model.counting && clock.calls == 1 && !overlay.isOpen, "the ring is not running on the first second of a picked window")

        await DisplayChange.happens()
        assertEnded(box, nil, "Window countdown")
        assertPlaque(box, "Window countdown")

        await runTheClockOut(clock)
        XCTAssertEqual(clock.calls, 1, "Window countdown: the clock was asked for \(clock.calls) seconds, the ring went on after the change")
        assertNothingWasTaken(box, freezes: 1, "Window countdown, after the last second")
    }

    // MARK: Where the panel stands

    private func moved(_ bar: CapturePanel) -> Bool? {
        Mirror(reflecting: bar).children.first { $0.label == "moved" }?.value as? Bool
    }

    /// The reading is not looking at nothing: the flag is there, it starts false, and a move of the bar's panel turns it.
    func testTheMovedFlagIsReadAndTurnsOnAMoveOfThePanel() async throws {
        let box = try rig()
        let bar = box.controller.bar
        XCTAssertEqual(moved(bar), false, "the bar has no `moved` flag to read, or it starts true")
        let panel = bar.makePanel()
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        await grace(0.1)
        XCTAssertEqual(moved(bar), true, "a move of the bar's panel did not turn the flag")
        panel.contentView = nil
    }

    func testTheNotificationAloneMovesNothingAndStoresNoOffset() async throws {
        let box = try rig()
        let bar = box.controller.bar
        try await panelUp(box, in: .screen)
        let before = bar.model.settings.panelOffset
        await DisplayChange.happens()
        XCTAssertEqual(moved(bar), false, "the notification alone turned the bar's moved flag")
        box.controller.cancel()
        bar.model.reload()
        XCTAssertEqual(bar.model.settings.panelOffset, before, "closing the bar after the notification stored an offset nobody made")
    }

    // MARK: A shot that was in the window before

    /// One shot in the after-shot window, then the panel up in Area mode with its overlay open.
    private func aShotAndAPickingPanel() async throws -> (box: Rig, overlay: CaptureOverlay?, ids: [Int]) {
        let box = try rig(thumbnail: true)
        await box.controller.handOff(CapturedShot(image: PanelRig.solid(0, 0, 1, width: 200, height: 100), kind: .area))
        let ids = box.controller.toast.model.shots.map(\.id)
        try require(ids.count == 1 && box.disk.written == 1, "the shot before the change is not in the window")
        let overlay = try await panelUp(box, in: .area)
        return (box, overlay, ids)
    }

    /// The control of the decision: a shot that was in the window before the change is there after it.
    func testAShotAlreadyInTheWindowBeforeTheChangeIsThereAfterIt() async throws {
        let (box, overlay, ids) = try await aShotAndAPickingPanel()
        await DisplayChange.happens()
        // The capture ended, so the change was answered; the shot is read after that and not instead of it.
        XCTAssertFalse(box.controller.isBusy, "the change was not answered: the controller is still busy")
        XCTAssertFalse(try XCTUnwrap(overlay).isOpen, "the change was not answered: the overlay is still open")
        XCTAssertEqual(box.controller.toast.model.shots.map(\.id), ids, "the shot that was in the window before the change is not there after it")
    }

    /// The two calls a listener could make, answering the same notification: `cancel` leaves the shot, `teardown` takes it
    /// with the window. What this pair shows is which call the previous case would turn red under.
    func testCancelLeavesTheShotAndTeardownTakesItOut() async throws {
        let kept = try await aShotAndAPickingPanel()
        let taken = try await aShotAndAPickingPanel()
        let keptController = kept.box.controller, takenController = taken.box.controller
        let cancelling = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { keptController.cancel() }
        }
        let tearingDown = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { takenController.teardown() }
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(cancelling)
            NotificationCenter.default.removeObserver(tearingDown)
        }
        await DisplayChange.happens()
        XCTAssertFalse(kept.box.controller.isBusy, "cancel did not end the press")
        XCTAssertFalse(taken.box.controller.isBusy, "teardown did not end the press")
        XCTAssertEqual(kept.box.controller.toast.model.shots.map(\.id), kept.ids, "cancel took the shot out of the window")
        XCTAssertTrue(taken.box.controller.toast.model.shots.isEmpty, "teardown left the shot in the window")
    }

    // MARK: Outside a capture, and once one is over

    private func esc() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    /// The controller listens while a press is under way and at no other time; the reading is not looking at nothing.
    func testOutsideACaptureTheNotificationSaysNothingAndNobodyListens() async throws {
        let box = try rig()
        XCTAssertEqual(DisplayChange.listening(box.controller), false, "the controller has no displayObserver to read, or listens with no press under way")
        await DisplayChange.happens()
        XCTAssertEqual(given(box).count, 0, "a plaque was given with no press under way")
        XCTAssertNil(DisplayChange.plaque(of: box.controller.toast), "the window holds a plaque with no press under way")
        XCTAssertFalse(box.controller.isBusy)

        box.controller.begin(.panel)
        XCTAssertEqual(DisplayChange.listening(box.controller), true, "control: a press under way is not listened for")
        box.controller.cancel()
        XCTAssertEqual(DisplayChange.listening(box.controller), false, "the press was closed and the controller still listens")
        await DisplayChange.happens()
        XCTAssertEqual(given(box).count, 0, "a plaque was given for a press that was over")
    }

    /// Esc on the picking overlay, a shot that was taken: each leaves no listener, and a change after it says nothing.
    func testAPressThatEndedByEscOrByATakenShotLeavesNoListenerAndNoPlaqueFollows() async throws {
        let picking = try rig()
        picking.controller.begin(.area)
        await waitUntil("the overlay opened") { picking.held.overlay != nil }
        let overlay = try XCTUnwrap(picking.held.overlay)
        try require(picking.controller.isBusy && overlay.isOpen, "the area shortcut did not open its overlay")
        overlay.keyDown(esc())
        await waitUntil("the press ended") { !picking.controller.isBusy }
        try require(!overlay.isOpen, "Esc on the overlay did not close it")
        XCTAssertEqual(DisplayChange.listening(picking.controller), false, "Esc ended the press and the controller still listens")
        await DisplayChange.happens()
        XCTAssertEqual(given(picking).count, 0, "a change after Esc gave a plaque")

        let taking = try rig()
        taking.controller.begin(.fullScreen)
        await waitUntil("the shot was taken") { !taking.controller.isBusy }
        try require(taking.disk.written == 1, "no file was written by the shortcut")
        XCTAssertEqual(DisplayChange.listening(taking.controller), false, "the shot was taken and the controller still listens")
        await DisplayChange.happens()
        XCTAssertEqual(given(taking).count, 0, "a change after a taken shot gave a plaque")
    }

    /// The change ends one press with one plaque, leaves no listener, says nothing more for a second change, and the next
    /// press is heard once again: one plaque for each change.
    func testEachChangeIsOnePlaqueAndTheNextPressIsHeardAgain() async throws {
        let box = try rig()
        try await panelUp(box, in: .window)
        await DisplayChange.happens()
        assertPlaque(box, "the first change")
        XCTAssertEqual(DisplayChange.listening(box.controller), false, "the change ended the press and the controller still listens")
        await DisplayChange.happens()
        XCTAssertEqual(given(box).count, 1, "a second change with no press under way gave another plaque")

        box.controller.begin(.panel)
        XCTAssertEqual(DisplayChange.listening(box.controller), true, "the next press is not listened for")
        await DisplayChange.happens()
        XCTAssertEqual(given(box).count, 2, "the next press's change did not give its own plaque")
        XCTAssertFalse(box.controller.isBusy)
        XCTAssertEqual(DisplayChange.listening(box.controller), false)
    }

    // MARK: When the picture is already being taken

    /// The shortcut for the whole screen is frozen and the change comes while the freeze is out: the shot is taken and
    /// delivered from that freeze, and the window does not say it was not taken.
    func testAChangeWhileTheShortcutIsFreezingTheScreenLetsTheShotBeTakenAndSaysNothing() async throws {
        let box = try rig(thumbnail: true)
        let gate = box.gate
        box.screen.hold = { n in n == 1 ? gate : nil }
        box.controller.begin(.fullScreen)
        await gate.reached()
        try require(box.controller.isBusy && box.screen.freezes == 1 && box.disk.written == 0, "the freeze is not out and held")

        await DisplayChange.happens()
        XCTAssertTrue(box.controller.isBusy, "the change ended a press whose picture was being taken")
        XCTAssertEqual(given(box).count, 0, "a plaque was given over a shot that is being taken")
        await gate.open()
        await waitUntil("the shot was delivered") { !box.controller.isBusy }
        XCTAssertEqual(box.disk.written, 1, "the file was not written")
        XCTAssertEqual(box.controller.toast.model.shots.count, 1, "the shot is not in the window")
        XCTAssertEqual(given(box).count, 0, "a plaque was given over a shot that was saved")
        XCTAssertNil(DisplayChange.plaque(of: box.controller.toast))
    }

    /// The shortcut pressed and cancelled before its task's body ran, and the panel opened and Window chosen on it in the same
    /// turn: the cancelled task's body runs while the new press is under way, and writes neither `delivering` nor `busy`, which
    /// are the new press's by then (`fullScreen` asks whether its task was cancelled before each). A change then ends the new
    /// press and says so.
    func testAShortcutCancelledBeforeItsTaskRanDoesNotDeafenTheNextPress() async throws {
        let box = try rig()
        box.controller.begin(.fullScreen)
        box.controller.cancel()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        try require(box.controller.isBusy && box.held.overlay?.isOpen == true && box.controller.bar.selecting,
                    "the new press is not under way with its overlay open: busy \(box.controller.isBusy)")

        await DisplayChange.happens()
        assertEnded(box, box.held.overlay, "a pick after a cancelled shortcut")
        assertPlaque(box, "a pick after a cancelled shortcut")
    }

    /// The border at the last tick of a countdown, on the side of the tick: while the last second is still running the
    /// press is a countdown and ends with the plaque, and nothing is taken after it.
    func testAChangeDuringTheLastSecondOfTheCountdownEndsItAndNothingIsTaken() async throws {
        let clock = DisplayChange.Clock(passing: 4)
        clocks.append(clock)
        let box = try rig(timer: .five, clock: clock)
        try await panelUp(box, in: .screen)
        box.controller.capture(from: .screen)
        await clock.reached()
        try require(clock.calls == 5 && clock.returned == 4 && box.controller.bar.model.counting, "the ring is not on its fifth second")

        await DisplayChange.happens()
        assertEnded(box, nil, "the last second")
        assertPlaque(box, "the last second")
        await clock.open()
        await waitUntil("the held second came back") { clock.returned >= 5 }
        await grace(0.25)
        assertNothingWasTaken(box, freezes: 0, "the last second, after it ran out")
    }

    /// The border on the side of the shot: the clock has run out and the freeze is out. The shot is taken, no plaque.
    func testAChangeAfterTheLastSecondHasRunOutLetsTheShotBeTaken() async throws {
        let box = try rig(timer: .five, thumbnail: true)
        let gate = box.gate
        box.screen.hold = { n in n == 1 ? gate : nil }
        try await panelUp(box, in: .screen)
        box.controller.capture(from: .screen)
        await gate.reached()
        try require(box.controller.isBusy && !box.controller.bar.model.counting && box.screen.freezes == 1, "the countdown is not over with the freeze out")

        await DisplayChange.happens()
        XCTAssertTrue(box.controller.isBusy, "the change ended a press whose picture was being taken")
        await gate.open()
        await waitUntil("the shot was delivered") { !box.controller.isBusy }
        XCTAssertEqual(box.disk.written, 1)
        XCTAssertEqual(box.controller.toast.model.shots.count, 1)
        XCTAssertEqual(given(box).count, 0, "a plaque was given over a shot that was saved")
    }

    /// The border itself: the last second is let go and the change comes in the same turn. Which of the two happens first is
    /// not asked; what is asked is that it is one of them whole: a shot and no plaque, or no shot and one plaque, and a
    /// controller that is free.
    func testTheLastSecondLetGoAndTheChangeInOneTurnIsOneOutcomeWhole() async throws {
        let clock = DisplayChange.Clock(passing: 4)
        clocks.append(clock)
        let box = try rig(timer: .five, thumbnail: true, clock: clock)
        try await panelUp(box, in: .screen)
        box.controller.capture(from: .screen)
        await clock.reached()
        try require(clock.calls == 5 && clock.returned == 4, "the ring is not on its fifth second")

        await clock.open()
        await DisplayChange.happens()
        await waitUntil("the press was over") { !box.controller.isBusy }
        await grace(0.25)
        let shots = box.controller.toast.model.shots.count, plaques = given(box).count
        XCTAssertTrue((box.disk.written == 1 && shots == 1 && plaques == 0) || (box.disk.written == 0 && shots == 0 && plaques == 1),
                      "neither a shot with no plaque nor a plaque with no shot: written \(box.disk.written), shots \(shots), plaques \(plaques)")
    }
}
