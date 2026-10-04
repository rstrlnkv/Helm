import AppKit
import CoreGraphics
import HelmTestSupport
import SwiftUI
import XCTest
@testable import Module_Screenshots_UI

/// **A pointer over the thumbnail stops its life, and leaving lets it go on from what was left; neither the enter
/// nor the exit is trusted.** Whether AppKit sends an exit when the panel moves from under a still pointer, or an
/// enter when it comes up under one, is not measured here; the countdown does not rely on either. The pointer is asked
/// (`ShotToast.pointerIsOver`) at a step that only the pointer is holding, and when the time is up; where a test
/// sets a hold by hand it says so.
///
/// The clock is `ShotToast.advance(by:)` for arithmetic and a held `StepClock` for the loop that really runs: no test
/// sleeps. Time is in binary-exact numbers (a thumbnail lives 5 s) so that «exactly up» is a comparison and not a hope.
///
/// Total failure of the subject prints: a thumbnail that vanishes from under the pointer that is on it, one that never
/// leaves because an exit was missed, a hold that outlives the shot it was for, or a countdown that starts over
/// instead of going on.
@MainActor
final class TheHoverHoldsTheShotAndLeavingLetsItGoTests: XCTestCase {

    private var toasts: [ShotToast] = []
    private let clock = StepClock()

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        clock.finish()
        super.tearDown()
    }

    private func shown(pointer: @escaping () -> Bool = { false }) throws -> ShotToast {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        toast.pointerIsOver = pointer
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: try ShotToastRig.realFile(self, "h.png"))
        return toast
    }

    // MARK: The arithmetic

    func testALifeNeverHeldEndsAtItsTimeAndNotBefore() throws {
        let toast = try shown()
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertEqual(toast.remaining, 0.5)
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    func testAHoverStopsTheCountdownAndLeavingGoesOnFromTheRemainder() throws {
        var over = false
        let toast = try shown(pointer: { over })
        XCTAssertFalse(toast.advance(by: 2))
        over = true
        toast.setHover(true)
        XCTAssertTrue(toast.model.hovering)
        for _ in 0..<50 { XCTAssertFalse(toast.advance(by: 100), "the shot went from under the pointer") }
        XCTAssertEqual(toast.remaining, 3, "the hold let time pass")
        over = false
        toast.setHover(false)
        XCTAssertFalse(toast.model.hovering)
        XCTAssertFalse(toast.advance(by: 2.5), "the countdown started over or ran short")
        XCTAssertEqual(toast.remaining, 0.5, "leaving did not go on from the remainder (5 − 2 − 2.5)")
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    /// Two enters are one hold, and one exit lets it go: a count of enters would keep it for ever.
    func testTwoEntersAndOneExitLetGo() throws {
        var over = true
        let toast = try shown(pointer: { over })
        toast.setHover(true)
        toast.setHover(true)
        over = false
        toast.setHover(false)
        XCTAssertTrue(toast.holds.isEmpty, "\(toast.holds)")
        XCTAssertTrue(toast.advance(by: 5))
    }

    /// An exit with no enter is nothing.
    func testAnExitWithNoEnterChangesNothing() throws {
        let toast = try shown()
        toast.setHover(false)
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertFalse(toast.advance(by: 1))
        XCTAssertEqual(toast.remaining, 4)
    }

    // MARK: The events that did not come

    /// The panel left from under a still pointer: no exit was sent, and the first step that finds the pointer elsewhere
    /// lets go, without waiting for an event that will not come.
    func testAnExitThatNeverCameIsFoundByTheNextStep() throws {
        var over = true
        let toast = try shown(pointer: { over })
        toast.setHover(true)
        XCTAssertFalse(toast.advance(by: 100))
        over = false
        XCTAssertFalse(toast.advance(by: 1), "the first step after the pointer left still held")
        XCTAssertEqual(toast.remaining, 4, "that step did not count")
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertFalse(toast.model.hovering, "the capsule stayed up for a pointer that is gone")
        XCTAssertTrue(toast.advance(by: 4))
    }

    /// The panel came up under a still pointer: no enter was sent, and the time running out finds the pointer there.
    func testAnEnterThatNeverCameIsFoundWhenTheTimeIsUp() throws {
        var over = true
        let toast = try shown(pointer: { over })
        XCTAssertFalse(toast.advance(by: 5), "the shot went from under a pointer that is on it")
        XCTAssertEqual(toast.holds, [.pointer])
        XCTAssertTrue(toast.model.hovering, "the capsule did not come up for a pointer that is on the shot")
        XCTAssertFalse(toast.advance(by: 100))
        over = false
        XCTAssertTrue(toast.advance(by: 1), "a pointer that left a shot whose time was up did not let it go")
    }

    /// The default check reads the anchor view's rect (the thumbnail's own view, not the whole panel) against
    /// `NSEvent.mouseLocation`; asked without a window it says no, and with a view on a window that stands under the
    /// mouse it says yes, and when the window moves away it says no.
    func testTheDefaultPointerCheckReadsTheMouseAgainstTheThumbnailsFrame() throws {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        XCTAssertFalse(toast.pointerIsOver(), "no thumbnail, and the pointer is over it")
        let mouse = NSEvent.mouseLocation
        let stand = StandInThumbnail(at: CGPoint(x: mouse.x - 50, y: mouse.y - 30))
        toast.model.anchor = stand.view
        XCTAssertTrue(toast.pointerIsOver(), "the window stands under the mouse and the check says it does not")
        stand.window.setFrameOrigin(CGPoint(x: mouse.x + 500, y: mouse.y + 500))
        XCTAssertFalse(toast.pointerIsOver(), "the window moved away from the mouse and the check still says it is over")
    }

    /// Through the default check and the real step loop: hover set by an event, panel moved away, no exit.
    func testAPanelThatMovedAwayLetsTheLoopEndWithoutAnExit() async throws {
        let mouse = NSEvent.mouseLocation
        let stand = StandInThumbnail(at: CGPoint(x: mouse.x - 50, y: mouse.y - 30))
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: try ShotToastRig.realFile(self, "h.png"))
        toast.model.anchor = stand.view
        toast.model.pointer(over: true)
        for _ in 0..<60 { await clock.step(self) }
        XCTAssertNotNil(toast.model.content, "the shot went from under a pointer that is on it")
        XCTAssertTrue(toast.model.shown)
        stand.window.setFrameOrigin(CGPoint(x: mouse.x + 500, y: mouse.y + 500))
        for _ in 0..<60 where toast.model.shown { await clock.step(self) }
        XCTAssertFalse(toast.model.shown, "the shot stayed for a pointer that was no longer over it")
    }

    // MARK: The loop that really runs

    func testTheLoopHoldsWhileOverAndGoesOnWhenLeft() async throws {
        var over = true
        let toast = try shown(pointer: { over })
        toast.model.pointer(over: true)
        await waitUntil("the loop's first step") { self.clock.isWaiting }
        for _ in 0..<120 { await clock.step(self) }
        XCTAssertTrue(toast.model.shown, "the loop ended a held shot")
        XCTAssertEqual(toast.remaining, 5, "the loop spent time while held")
        over = false
        toast.model.pointer(over: false)
        var steps = 0
        while toast.model.shown, steps < 80 { await clock.step(self); steps += 1 }
        XCTAssertFalse(toast.model.shown)
        // Fifty tenths taken from five do not come to exactly nought in binary; `ShotShelf.isOver` takes the
        // remainder for nought, so the fiftieth step is the one, never the fifty-first.
        XCTAssertEqual(steps, 50, "the loop did not go on from five seconds in tenths (\(steps) steps)")
        // After the fade the content goes.
        XCTAssertNotNil(toast.model.content)
        XCTAssertTrue(clock.fire(), "the toast did not wait for its fade")
        await waitUntil("the content went after the fade") { toast.model.content == nil }
    }

    // MARK: Inputs nobody fed

    /// A new shot over a hovered thumbnail: the write's result over its working picture is the same view and no enter
    /// will come, so the hold stays; the clock is the new shot's own, whole.
    func testTheResultOverAWorkingThumbnailKeepsTheHoldAndRestartsTheLife() throws {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        toast.pointerIsOver = { true }
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertEqual(toast.remaining, 6)
        toast.setHover(true)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: try ShotToastRig.realFile(self, "i.png"))
        XCTAssertEqual(toast.holds, [.pointer], "the result lost the hold of a pointer that never left")
        XCTAssertTrue(toast.model.hovering)
        XCTAssertEqual(toast.remaining, 5, "the new shot's life is its own")
        XCTAssertFalse(toast.advance(by: 100))
    }

    /// A new shot, when the pointer is no longer over the old: the old hold must not survive on the new shot.
    func testANewShotWithThePointerGoneIsNotHeld() throws {
        var over = true
        let toast = try shown(pointer: { over })
        toast.setHover(true)
        over = false
        toast.showDone(try ShotToastRig.picture(), caption: "Saved again", file: try ShotToastRig.realFile(self, "j.png"))
        XCTAssertEqual(toast.model.shots.count, 2, "the second shot is a shot of the pile, not the first one's replacement")
        XCTAssertFalse(toast.advance(by: 1), "the first step finds the pointer gone")
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertTrue(toast.advance(by: 4))
    }

    /// A refusal over a hovered picture is another toast: the capsule is not there to be pointed at, and it is not held.
    func testARefusalOverAHoveredPictureIsNotHeld() throws {
        let toast = try shown(pointer: { true })
        toast.setHover(true)
        toast.showRefusal(.noPermission)
        XCTAssertTrue(toast.holds.isEmpty, "the refusal inherited a hold of the picture: \(toast.holds)")
        XCTAssertFalse(toast.model.hovering)
        XCTAssertEqual(toast.remaining, 9)
    }

    /// A picture over a refusal that was hovered is not held either.
    func testAPictureAfterARefusalStartsFree() throws {
        let toast = ShotToastRig.toast(clock)
        toasts.append(toast)
        toast.showRefusal(.encoding)
        toast.setHover(true)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: nil)
        XCTAssertTrue(toast.holds.isEmpty, "\(toast.holds)")
    }

    /// ✕ while held: the toast is gone, the hold with it, the loop's step is dead, and the next shot's life is whole
    /// and free.
    func testDismissWhileHeldTakesTheHoldAway() async throws {
        let toast = try shown(pointer: { true })
        toast.setHover(true)
        await waitUntil("the loop is waiting") { self.clock.isWaiting }
        toast.dismiss()
        XCTAssertNil(toast.model.content)
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertFalse(toast.model.hovering)
        XCTAssertFalse(toast.model.shown)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: nil)
        toast.pointerIsOver = { false }
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertTrue(toast.advance(by: 5), "the next shot inherited the dismissed one's hold")
    }

    /// An enter that arrives after the dismiss (whether the view sends one as it goes is not measured) must not hold
    /// the next shot.
    func testALateEnterAfterDismissDoesNotHoldTheNextShot() throws {
        let toast = try shown()
        toast.dismiss()
        toast.setHover(true)
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: nil)
        XCTAssertTrue(toast.holds.isEmpty, "an enter that came after the dismiss holds the shot after it: \(toast.holds)")
        XCTAssertFalse(toast.model.hovering)
    }

    // MARK: A step that is not a time

    /// Zero seconds is no time passing.
    func testAZeroStepSpendsNothing() throws {
        let toast = try shown()
        XCTAssertFalse(toast.advance(by: 0))
        XCTAssertEqual(toast.remaining, 5)
    }

    /// A negative step must not give life back, and a step that is not a number must not poison the remainder: after
    /// either, five seconds more still end the toast. (The loop's own step is a constant, so only a caller of the seam
    /// can feed these.)
    func testANegativeStepDoesNotLengthenTheLife() throws {
        let toast = try shown()
        _ = toast.advance(by: -3)
        XCTAssertLessThanOrEqual(toast.remaining, 5, "a negative step lengthened the life to \(toast.remaining)")
        XCTAssertTrue(toast.advance(by: 5), "a negative step made the toast live longer than it was given")
    }

    func testAStepThatIsNotANumberDoesNotPoisonTheRemainder() throws {
        let toast = try shown()
        _ = toast.advance(by: .nan)
        XCTAssertFalse(toast.remaining.isNaN, "the remainder became not-a-number: the toast can never end")
        XCTAssertTrue(toast.advance(by: 5), "after a step that was not a number the toast no longer ends")
    }

    func testAnInfiniteStepEndsTheToastAndANegativeInfiniteOneDoesNot() throws {
        let toast = try shown()
        XCTAssertTrue(toast.advance(by: .infinity), "an unending time did not end the toast")
        let other = try shown()
        _ = other.advance(by: -.infinity)
        XCTAssertTrue(other.remaining.isFinite, "a step of minus infinity gave the toast an endless life")
    }
}
