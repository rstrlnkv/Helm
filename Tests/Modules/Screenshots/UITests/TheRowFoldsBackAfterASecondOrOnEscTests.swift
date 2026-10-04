import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **An unfolded row folds back once the pointer has been away for a second, and on Esc; while it is open the shots'
/// life is not counted, and after it folds the life goes on from what was left.** The pointer's events are not
/// trusted in either direction: `ShotToast.pointerIsOver` is asked at every step, so an exit that never came folds
/// the row and an enter that never came keeps it. Time is in binary-exact numbers (a quarter, a half, a sixteenth), so
/// that «exactly at the delay» is a comparison and not a hope; the cases that spend the clock's own tenth of a
/// second say so, and what makes ten of them a second is `ShotShelf.isOver`
/// (`TheShelfClocksEndOnTheExactStepOfTheRunningClockTests` reads every clock of the window by it).
///
/// The toast's own clock sleeps for good: `advance(by:)` is the only thing that passes time, and a test never waits.
///
/// Total failure of the subject prints: a row that folds at the first step or never, a row that folds under a pointer
/// that came back at the last step, a life that runs while the row is open or starts over when it folds, an Esc that
/// folds twice or gives the keys back when it never had them, a scroll that comes to rest nowhere.
@MainActor
final class TheRowFoldsBackAfterASecondOrOnEscTests: XCTestCase {

    private var toasts: [ShotToast] = []
    private var stands: [StandInThumbnail] = []
    private var taken = 0, given = 0

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        stands = []
        super.tearDown()
    }

    /// A toast with no window whose clock never steps by itself, a pointer that is nowhere, and the keys counted.
    private func quiet() -> ShotToast {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toast.takeKey = { [unowned self] in taken += 1 }
        toast.yieldKey = { [unowned self] in given += 1 }
        toasts.append(toast)
        return toast
    }

    /// `count` finished shots and the row open on them, the pointer on nothing.
    private func opened(_ count: Int = 3) throws -> ShotToast {
        let toast = quiet()
        for i in 1...count { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        toast.unfold()
        XCTAssertTrue(toast.model.unfolded, "the control: the row is open")
        return toast
    }

    // MARK: What unfolds

    func testOnlyAPileUnfoldsAndTheRowTakesTheKeysOnce() throws {
        let one = quiet()
        one.showDone(try ShotToastRig.picture(), caption: "c1", file: nil)
        one.unfold()
        XCTAssertFalse(one.model.unfolded, "a single shot has no row")
        XCTAssertEqual(taken, 0)
        let empty = quiet()
        empty.unfold()
        XCTAssertFalse(empty.model.unfolded)
        XCTAssertEqual(taken, 0)

        // The pointer is on the pile when it is clicked: that is how a click on it comes.
        let two = quiet()
        for i in 1...2 { two.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        two.setHover(true)
        XCTAssertTrue(two.holds.contains(.pointer), "the control: the pointer holds the pile")
        two.unfold()
        XCTAssertTrue(two.model.unfolded)
        XCTAssertEqual(taken, 1)
        two.unfold()
        XCTAssertEqual(taken, 1, "a second click on the row took the keys again")
        XCTAssertFalse(two.model.hovering)
        XCTAssertFalse(two.holds.contains(.pointer), "the pointer's hold stayed over a row whose life is not counted")
    }

    // MARK: By the clock

    func testTheRowFoldsAtExactlyTheDelayAndNotAnInstantBefore() throws {
        let toast = try opened()
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertEqual(toast.away, 0.5)
        XCTAssertFalse(toast.advance(by: 0.4375))
        XCTAssertTrue(toast.model.unfolded, "folded 0.0625 s early")
        XCTAssertEqual(given, 0)
        XCTAssertFalse(toast.advance(by: 0.0625), "the step that folds the row is not the end of the window")
        XCTAssertFalse(toast.model.unfolded, "not folded at the delay")
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertNil(toast.model.focus)
        XCTAssertFalse(toast.model.barShown)
        XCTAssertEqual(toast.away, 0)
        XCTAssertEqual(given, 1, "the keys were not given back at the fold")
        XCTAssertTrue(toast.model.isPile)
    }

    /// The clock the running app has ticks a tenth at a time; ten of them are a second.
    func testTheRunningClocksTenTenthsOfASecondFoldTheRow() throws {
        let toast = try opened()
        for step in 1...9 {
            XCTAssertFalse(toast.advance(by: 0.1))
            XCTAssertTrue(toast.model.unfolded, "folded at step \(step), before a second")
        }
        XCTAssertFalse(toast.advance(by: 0.1))
        XCTAssertFalse(toast.model.unfolded, "ten ticks of 0.1 s are a second, and the row is still open (\(toast.away) s away)")
    }

    func testAPointerThatComesBackAtTheLastStepStartsTheDelayOver() throws {
        let toast = try opened()
        var over = false
        toast.pointerIsOver = { over }
        XCTAssertFalse(toast.advance(by: 0.75))
        XCTAssertEqual(toast.away, 0.75)
        over = true
        XCTAssertFalse(toast.advance(by: 0.25))
        XCTAssertTrue(toast.model.unfolded, "the row folded at the step that found the pointer on it")
        XCTAssertEqual(toast.away, 0)
        over = false
        XCTAssertFalse(toast.advance(by: 0.75))
        XCTAssertTrue(toast.model.unfolded, "the delay did not start over")
        XCTAssertFalse(toast.advance(by: 0.25))
        XCTAssertFalse(toast.model.unfolded)
    }

    func testAnExitThatNeverCameFoldsAndAnEnterThatNeverCameKeepsTheRowOpen() throws {
        // The pointer entered a shot (the capsule is up), left the window by a way that sent no exit.
        let gone = try opened()
        gone.model.pointer(over: true, shot: gone.model.shot(1)?.id ?? -1, view: nil)
        XCTAssertNotNil(gone.model.focus)
        XCTAssertFalse(gone.advance(by: 1))
        XCTAssertFalse(gone.model.unfolded, "the row waited for an exit that was never sent")
        XCTAssertNil(gone.model.focus)

        // The pointer is on the row and no enter was sent: it stays however long it stays.
        let there = try opened()
        there.pointerIsOver = { true }
        XCTAssertEqual(there.remaining, 5)
        for _ in 0..<100 { XCTAssertFalse(there.advance(by: 1000)) }
        XCTAssertTrue(there.model.unfolded, "the row folded under a pointer that is on it")
        XCTAssertEqual(there.remaining, 5, "an open row spent the life")
        XCTAssertEqual(there.away, 0)
    }

    func testAStepThatIsNotATimeMovesNothingOfTheRow() throws {
        let toast = try opened()
        XCTAssertFalse(toast.advance(by: 0.5))
        for odd in [Double.nan, -1, -Double.infinity, 0] {
            XCTAssertFalse(toast.advance(by: odd))
            XCTAssertEqual(toast.away, 0.5, "a step of \(odd) moved the clock")
            XCTAssertTrue(toast.model.unfolded)
        }
        XCTAssertFalse(toast.advance(by: .infinity))
        XCTAssertFalse(toast.model.unfolded, "a step that never ends is more than a second")
    }

    func testAnOpenRowSpendsNoLifeAndAFoldedOneGoesOnFromWhatWasLeft() throws {
        let toast = quiet()
        for i in 1...3 { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        XCTAssertFalse(toast.advance(by: 2))
        XCTAssertEqual(toast.remaining, 3)
        toast.unfold()
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertEqual(toast.remaining, 3, "life was counted while the row was open")
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertEqual(toast.remaining, 3, "the fold gave life back or took it")
        XCTAssertFalse(toast.advance(by: 2.5))
        XCTAssertNotNil(toast.model.shots.first, "the window went before the life that was left")
        XCTAssertTrue(toast.advance(by: 0.5), "the group's life is up")
    }

    func testANewShotWhileTheRowIsOpenLandsInTheCornerAndStartsTheLifeOver() throws {
        let toast = try opened(7)
        toast.showOldest()
        XCTAssertEqual(toast.model.offset, 4 * ShotShelf.pitch)
        XCTAssertFalse(toast.advance(by: 0.5))
        toast.showDone(try ShotToastRig.picture(), caption: "new", file: nil)
        XCTAssertTrue(toast.model.unfolded, "the row closed for a new shot")
        XCTAssertEqual(toast.model.offset, 0, "the new shot is not at the corner")
        XCTAssertEqual(toast.model.shots.last?.caption, "new")
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertEqual(given, 0)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    func testUnfoldingAgainAfterAFoldStartsTheDelayFromNothing() throws {
        let toast = try opened()
        XCTAssertFalse(toast.advance(by: 0.75))
        toast.fold()
        toast.unfold()
        XCTAssertEqual(toast.away, 0, "the second row inherited the first's time away")
        XCTAssertFalse(toast.advance(by: 0.75))
        XCTAssertTrue(toast.model.unfolded)
        XCTAssertEqual(taken, 2)
        XCTAssertEqual(given, 1)
    }

    // MARK: By Esc

    func testEscFoldsTheRowOnceAndAFoldedPileIsLeftAloneByIt() throws {
        let toast = try opened()
        toast.fold()
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertEqual(given, 1)
        toast.pointerIsOver = { true }
        toast.setHover(true)
        let remaining = toast.remaining, holds = toast.holds
        toast.fold()
        toast.fold()
        XCTAssertEqual(given, 1, "an Esc on a pile gave the keys back again")
        XCTAssertEqual(toast.remaining, remaining)
        XCTAssertEqual(toast.holds, holds)
        XCTAssertTrue(toast.model.hovering, "an Esc on a folded pile took the pointer's hold")
        XCTAssertTrue(toast.model.shots.count == 3 && toast.model.isPile)
    }

    func testEscOnASingleShotOrOnNothingDoesNothing() throws {
        let toast = quiet()
        toast.fold()
        toast.showDone(try ShotToastRig.picture(), caption: "c1", file: nil)
        toast.fold()
        XCTAssertEqual(toast.model.shots.count, 1)
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertEqual(given, 0)
        XCTAssertEqual(taken, 0)
    }

    func testEscWhilePointerIsOnTheRowLeavesTheWindowOnlyToTheLifeNotToThePointer() throws {
        let toast = try opened()
        toast.pointerIsOver = { true }
        toast.fold()
        XCTAssertFalse(toast.advance(by: 5), "the pointer is on the pile when its time is up")
        XCTAssertTrue(toast.holds.contains(.pointer))
        toast.pointerIsOver = { false }
        XCTAssertTrue(toast.advance(by: 0.5), "the hold the clock took was never let go")
    }

    func testEscWhileASheetIsOpenFoldsTheRowAndTheSheetStaysToHoldTheLife() throws {
        let toast = quiet()
        var closed = 0
        toast.presentPicker = { _, _ in }
        toast.closePicker = { _ in closed += 1 }
        let stand = StandInThumbnail()
        stands.append(stand)
        toast.model.anchor = stand.view
        toast.showDone(try ShotToastRig.picture(), caption: "c1", file: nil, share: true)
        XCTAssertTrue(toast.holds.contains(.sheet))
        for i in 2...3 { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        toast.unfold()
        toast.fold()
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertEqual(closed, 0, "an Esc closed the system's sheet")
        XCTAssertTrue(toast.holds.contains(.sheet))
        XCTAssertFalse(toast.advance(by: 100), "the sheet's hold ended with the row")
        XCTAssertEqual(toast.remaining, 5)
        toast.sheetEnded()
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertTrue(toast.advance(by: 0.5), "the life after the sheet is the life that was left")
    }

    /// The panel's own Esc: `cancelOperation` and a key-down of keyCode 53 are the same Esc, and neither is two.
    func testThePanelsEscReachesTheRowAndNothingElseDoes() throws {
        let panel = ShotPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        panel.cancelOperation(nil)
        XCTAssertEqual(escapes, 1)
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                 context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                                 isARepeat: false, keyCode: 53))
        panel.keyDown(with: esc)
        XCTAssertEqual(escapes, 2, "an Esc that reaches the panel's keyDown is lost")
        panel.close()
    }

    // MARK: The row's scroll comes to rest by itself

    func testAScrollOverAFoldedPileOrAShortRowMovesNothing() throws {
        let pile = quiet()
        for i in 1...7 { pile.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        pile.scroll(by: 300)
        pile.showOldest()
        XCTAssertEqual(pile.model.offset, 0, "a pile scrolled")
        XCTAssertFalse(pile.model.barShown)

        let short = try opened(3)
        short.scroll(by: 300)
        short.showOldest()
        XCTAssertEqual(short.model.offset, 0, "three shots are all seen: nothing to scroll to")
        XCTAssertFalse(short.model.barShown, "a bar for a row that is all there")
    }

    func testAScrollComesToRestOnAWholeSlotAfterAFifthOfASecondAndItsBarGoesAfterASecond() throws {
        let toast = try opened(7)
        toast.pointerIsOver = { true }
        toast.scroll(by: 50)
        XCTAssertEqual(toast.model.offset, 50)
        XCTAssertTrue(toast.model.barShown)
        XCTAssertFalse(toast.advance(by: 0.125))
        XCTAssertEqual(toast.model.offset, 50, "the row came to rest before the wheel had been still for a fifth of a second")
        // A step later the wheel is still: 50 is nearer the first rest than the second.
        XCTAssertFalse(toast.advance(by: 0.125))
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertTrue(toast.model.barShown, "the bar went with the rest")
        toast.scroll(by: 150)
        XCTAssertFalse(toast.advance(by: 0.25))
        XCTAssertEqual(toast.model.offset, ShotShelf.pitch)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertTrue(toast.model.barShown)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertFalse(toast.model.barShown, "the bar outlived its second")
        XCTAssertEqual(toast.model.offset, ShotShelf.pitch)
    }

    func testAScrollThatKeepsComingKeepsTheRowWhereItIsAndAStepOfSecondsRestsAndHidesAtOnce() throws {
        let toast = try opened(7)
        toast.pointerIsOver = { true }
        for _ in 0..<10 {
            toast.scroll(by: 20)
            XCTAssertFalse(toast.advance(by: 0.125))
        }
        XCTAssertEqual(toast.model.offset, 200, "a row that still had wheel under it came to rest")
        toast.scroll(by: 20)
        XCTAssertFalse(toast.advance(by: 100), "the long step was the end of the window, or the row's, though the pointer is on it")
        XCTAssertTrue(toast.model.unfolded)
        XCTAssertEqual(toast.model.offset, ShotShelf.pitch, "220 is nearer the second rest")
        XCTAssertFalse(toast.model.barShown)
    }

    func testAnOddScrollMovesNothingAndTheNotchesMoveASlotEach() throws {
        let toast = try opened(7)
        toast.scroll(by: .nan)
        toast.scroll(by: 0)
        XCTAssertEqual(toast.model.offset, 0)
        toast.scroll(by: .infinity)
        XCTAssertEqual(toast.model.offset, 4 * ShotShelf.pitch)
        toast.scroll(by: .infinity)
        XCTAssertEqual(toast.model.offset, 4 * ShotShelf.pitch)
        toast.scroll(by: -.infinity)
        XCTAssertEqual(toast.model.offset, 0)
        toast.scroll(by: 0.001, precise: false)
        toast.scroll(by: 1e9, precise: false)
        XCTAssertEqual(toast.model.offset, 2 * ShotShelf.pitch)
    }

    func testAFoldInTheMiddleOfAScrollLeavesNothingToRestOrHide() throws {
        let toast = try opened(7)
        toast.scroll(by: 150)
        toast.fold()
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertFalse(toast.model.barShown)
        XCTAssertFalse(toast.advance(by: 0.25))
        XCTAssertEqual(toast.model.offset, 0, "a rest from a scroll that was folded away moved the pile")
        XCTAssertTrue(toast.model.isPile)
    }

    func testARowWhoseShotsAreClosedUnderTheScrollRestsInsideTheShorterList() throws {
        let toast = try opened(5)
        toast.pointerIsOver = { true }
        toast.showOldest()
        toast.scroll(by: -50)
        for _ in 0..<2 {
            toast.model.focus = toast.model.shot(0)?.id ?? -1
            toast.close()
        }
        XCTAssertEqual(toast.model.shots.count, 3)
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertFalse(toast.advance(by: 1))
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertFalse(toast.model.barShown)
    }

    // MARK: Who gives the keys back

    func testTheKeysGoBackAtEveryEndOfTheRowAndEachTimeOnce() throws {
        // The fold by Esc, by the clock, by a refusal, by the editor, and by the shot that leaves the row at one.
        let esc = try opened()
        esc.fold()
        XCTAssertEqual(given, 1)
        let clock = try opened()
        XCTAssertFalse(clock.advance(by: 1))
        XCTAssertEqual(given, 2)
        let refused = try opened()
        refused.showRefusal(.pasteboard)
        XCTAssertEqual(given, 3)
        let editing = try opened()
        editing.takeForEditing(editing.model.shot(1)?.id ?? -1)
        XCTAssertEqual(given, 4)
        XCTAssertFalse(editing.model.unfolded)
        let two = try opened(2)
        two.model.focus = two.model.shot(0)?.id ?? -1
        two.close()
        XCTAssertEqual(given, 5)
        XCTAssertEqual(taken, 5, "one take for each row that was opened")
    }

    /// The end of the window while the row is open: every state the row held is gone with it, and the next shots are a
    /// pile and not a row that thinks it is open. Whether the panel was the key window is the panel's: `orderOut`.
    func testTheWindowsEndWhileTheRowIsOpenLeavesNoRowNoFocusNoHold() throws {
        let toast = try opened(7)
        toast.model.focus = toast.model.shot(2)?.id ?? -1
        toast.scroll(by: 100)
        toast.dismiss()
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertNil(toast.model.focus)
        XCTAssertEqual(toast.model.offset, 0)
        XCTAssertFalse(toast.model.barShown)
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertEqual(toast.away, 0)
        XCTAssertTrue(toast.model.shots.isEmpty)
        for i in 1...2 { toast.showDone(try ShotToastRig.picture(), caption: "n\(i)", file: nil) }
        XCTAssertTrue(toast.model.isPile, "the next shots came up as an open row")
        XCTAssertFalse(toast.advance(by: 4.5), "the next shots lived on the old row's clock")
        XCTAssertTrue(toast.advance(by: 0.5))
    }
}
