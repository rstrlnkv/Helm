import AppKit
import CoreGraphics
import HelmTestSupport
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The window holds twenty shots; the twenty-first pushes the oldest out, and whatever that shot was in the middle
/// of, the window goes on.** Shots come in as the running app brings them (`showWorking`, `showDone`, `showRefusal`)
/// or, where the app has no way to reach the state, straight onto the model. The inputs here are the ones nobody
/// planned a list for: twenty-five and a thousand shots, the pushed-out shot being the one the pointer is on, the one
/// a drag began on, the one a Share sheet was opened at, the one that is in the editor, the one whose write is not
/// done, the one whose write was refused after it was gone; the ✕ on the last shot, on a shot that is still being
/// written, in a row of two; and a refusal over the whole list.
///
/// Time is in binary-exact numbers (a shot lives 5 s, a refusal 9) and the toast's own clock sleeps for good, so that
/// no step comes by itself: `advance(by:)` is the only thing that passes time.
///
/// Total failure of the subject prints: a list of 21, the newest dropped in place of the oldest, a focus on a shot
/// that is not there, a sheet closed under a shot that is pushed out, a drag that carries the wrong picture, a
/// shot that is lost when its refusal was for another, a plaque that never lets the list come back.
@MainActor
final class TheShelfIsBoundedTests: XCTestCase {

    private var toasts: [ShotToast] = []
    private var stands: [StandInThumbnail] = []
    private var mounts: [MountedRender] = []

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        stands = []
        mounts = []
        super.tearDown()
    }

    /// A toast with no window, whose clock never steps by itself.
    private func quiet() -> ShotToast {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        return toast
    }

    private func fill(_ toast: ShotToast, _ range: ClosedRange<Int>) throws {
        for i in range { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
    }

    private func captions(_ toast: ShotToast) -> [String?] { toast.model.shots.map(\.caption) }
    private func expected(_ range: ClosedRange<Int>) -> [String?] { range.map { "c\($0)" } }

    // MARK: Twenty-five in, twenty counted

    func testTwentyFiveShotsInTwentyAreCountedAndTheOldestFiveAreGone() throws {
        let toast = quiet()
        for i in 1...25 {
            try fill(toast, i...i)
            XCTAssertEqual(toast.model.shots.count, min(i, 20), "after \(i) shots")
            XCTAssertEqual(toast.model.shots.last?.caption, "c\(i)", "the newest is what stands in the corner")
        }
        XCTAssertEqual(captions(toast), expected(6...25), "the oldest are the ones that went, and the list is oldest first")
        XCTAssertEqual(toast.model.shots.map(\.id), Array(6...25))
        XCTAssertTrue(toast.model.isPile)
        XCTAssertEqual(toast.sources().count, 20, "the group's Copy All reaches twenty")
        XCTAssertEqual(toast.model.current?.caption, "c25")
    }

    func testAThousandShotsLeaveTheNewestTwentyAndTheLifeOfTheLast() throws {
        let toast = quiet()
        try fill(toast, 1...1000)
        XCTAssertEqual(captions(toast), expected(981...1000))
        XCTAssertEqual(toast.remaining, 5, "each shot starts the life over")
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    func testEveryNewShotStartsTheLifeOverAtTheBoundToo() throws {
        let toast = quiet()
        try fill(toast, 1...20)
        XCTAssertFalse(toast.advance(by: 4))
        XCTAssertEqual(toast.remaining, 1)
        try fill(toast, 21...21)
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertEqual(toast.model.shots.count, 20)
    }

    // MARK: The pushed-out shot was in the middle of something

    func testTheShotThePointerIsOnInTheRowIsLetGoWhenItIsPushedOut() throws {
        let toast = quiet()
        try fill(toast, 1...20)
        toast.unfold()
        let oldest = try XCTUnwrap(toast.model.shots.first)
        toast.model.focus = oldest.id
        XCTAssertEqual(toast.model.current?.id, oldest.id, "the control: an action is about the shot the pointer is on")
        try fill(toast, 21...21)
        XCTAssertNil(toast.model.focus, "a focus on a shot that is no longer on the list")
        XCTAssertEqual(toast.model.current?.caption, "c21", "with the focused shot gone the action is about the newest")
        XCTAssertTrue(toast.model.unfolded, "a shot that arrives while the row is open leaves it open")
        XCTAssertEqual(toast.model.offset, 0, "and is shown from the corner")
        XCTAssertEqual(toast.model.shots.count, 20)
        // The pointer comes onto a shot that is still there, and leaves it.
        let next = try XCTUnwrap(toast.model.shots.first)
        toast.model.pointer(over: true, shot: next.id, view: nil)
        XCTAssertEqual(toast.model.current?.id, next.id)
        toast.model.pointer(over: false, shot: oldest.id, view: nil)
        XCTAssertEqual(toast.model.focus, next.id, "the exit of a shot that is gone took the focus of another")
    }

    func testThePointerOnThePileStillHoldsAfterAShotThatPushesOut() throws {
        let toast = quiet()
        toast.pointerIsOver = { true }
        try fill(toast, 1...20)
        toast.setHover(true)
        try fill(toast, 21...21)
        XCTAssertTrue(toast.holds.contains(.pointer), "a new shot took the hold of a pointer that never left")
        XCTAssertTrue(toast.model.hovering)
        XCTAssertFalse(toast.advance(by: 100), "the life ran under the pointer")
    }

    /// The drag view of a shot asks the model for its shot by name when a drag begins: a drag that begins on a view that
    /// is leaving carries nothing, and never the picture of the shot that took its place.
    func testADragThatBeginsOnAShotThatWasPushedOutCarriesNothingAndTheOthersCarryTheirOwn() throws {
        let toast = quiet()
        try fill(toast, 1...20)
        let mount = MountedRender(ShotToastView(model: toast.model), width: 700, height: 400, appearance: .aqua)
        mounts.append(mount)
        mount.settle(20)
        let before = dragViews(in: mount.host)
        XCTAssertEqual(before.count, 20, "the control: every shot of the list has a drag view")
        let oldest = try XCTUnwrap(toast.model.shots.first), newest = try XCTUnwrap(toast.model.shots.last)
        let leaving = try XCTUnwrap(before.first { view in
            if case .picture(let image)? = view.payload() { return image === oldest.full }
            return false
        }, "no view carries the oldest shot's picture")
        let staying = try XCTUnwrap(before.first { view in
            if case .picture(let image)? = view.payload() { return image === newest.full }
            return false
        })
        try fill(toast, 21...21)
        mount.settle(20)
        XCTAssertNil(leaving.payload(), "a drag on a shot that is gone carries a picture")
        guard case .picture(let image)? = staying.payload() else { return XCTFail("the newest of the old list lost its picture") }
        XCTAssertTrue(image === newest.full)
    }

    private func dragViews(in view: NSView) -> [ShotDragView] {
        (view as? ShotDragView).map { [$0] } ?? view.subviews.flatMap { dragViews(in: $0) }
    }

    func testASheetOpenAtAShotStaysOpenWhenThatShotIsPushedOutAndEndsOnlyWithTheWindow() throws {
        let toast = quiet()
        var presented = 0
        var closed = 0
        toast.presentPicker = { _, _ in presented += 1 }
        toast.closePicker = { _ in closed += 1 }
        let stand = StandInThumbnail()
        stands.append(stand)
        toast.model.anchor = stand.view
        toast.showDone(try ShotToastRig.picture(), caption: "c1", file: nil, share: true)
        XCTAssertEqual(presented, 1)
        XCTAssertTrue(toast.holds.contains(.sheet))
        try fill(toast, 2...25)
        XCTAssertEqual(toast.model.shots.count, 20)
        XCTAssertEqual(presented, 1, "a shot that came after opened a second sheet")
        XCTAssertEqual(closed, 0, "a new shot closed the sheet that stands at the shot that went")
        XCTAssertTrue(toast.holds.contains(.sheet))
        XCTAssertFalse(toast.advance(by: 1000), "the window closed under the sheet")
        toast.dismiss()
        XCTAssertEqual(closed, 1, "the window's end leaves the sheet open, or closes it twice")
        XCTAssertTrue(toast.holds.isEmpty)
        XCTAssertTrue(toast.model.shots.isEmpty)
    }

    func testAShotInTheEditorIsNotPushedBackByTwentyMoreAndTheEditorsHoldOutlastsThem() throws {
        let toast = quiet()
        try fill(toast, 1...3)
        let taken = try XCTUnwrap(toast.model.shot(1)?.id ?? -1)
        toast.takeForEditing(taken)
        XCTAssertEqual(captions(toast), ["c1", "c3"])
        XCTAssertTrue(toast.holds.contains(.editor))
        try fill(toast, 4...30)
        XCTAssertEqual(toast.model.shots.count, 20)
        XCTAssertTrue(toast.holds.contains(.editor), "a shot that arrived ended the editor's hold")
        XCTAssertFalse(toast.advance(by: 1000), "the group's life ran while the editor was open")
        toast.editorClosed()
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertTrue(toast.advance(by: 0.5))
    }

    func testAShotStillBeingWrittenWhenTwentyFinishAfterItGoesOnTheListWhenItsResultComes() throws {
        let toast = quiet()
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertEqual(captions(toast), [nil], "the working shot has no caption")
        // Each of these is a capture that began after the first and finished before it: the first result in takes the
        // working shot's place, and the ones after it are new shots.
        for i in 1...20 {
            toast.showWorking(try ShotToastRig.picture())
            toast.showDone(try ShotToastRig.picture(), caption: "b\(i)", file: nil)
        }
        XCTAssertEqual(toast.model.shots.count, 20)
        XCTAssertFalse(captions(toast).contains { $0 == nil })
        toast.showDone(try ShotToastRig.picture(), caption: "late", file: nil)
        XCTAssertEqual(toast.model.shots.count, 20, "the late result made a twenty-first")
        XCTAssertEqual(toast.model.shots.last?.caption, "late", "the result that came last is not the newest")
        XCTAssertEqual(captions(toast), (2...20).map { Optional("b\($0)") } + ["late"], "the oldest result went, the late one is newest")
    }

    /// The only way a working shot is pushed out is by shots put on the list while it is still working.
    func testAWorkingShotPushedOutByTwentyMoreIsReplacedByItsResultAsANewShotNotLostNotDoubled() throws {
        let toast = quiet()
        toast.showWorking(try ShotToastRig.picture())
        let working = try XCTUnwrap(toast.model.shots.first)
        for i in 1...20 { toast.model.add(try ShotToastRig.picture(), caption: "x\(i)", file: nil, full: try ShotToastRig.picture()) }
        XCTAssertFalse(toast.model.shots.contains { $0.id == working.id }, "the control: the working shot was pushed out")
        XCTAssertEqual(toast.model.shots.count, 20)
        toast.showDone(try ShotToastRig.picture(), caption: "done", file: nil)
        XCTAssertEqual(toast.model.shots.count, 20)
        XCTAssertEqual(toast.model.shots.last?.caption, "done", "a result for a shot that is gone is dropped, or filled another shot")
        XCTAssertEqual(captions(toast).filter { $0 == "done" }.count, 1)
        XCTAssertEqual(captions(toast).first, "x2", "the result took a place that was not the oldest's")
        // The slot is spent: the next shot's working thumbnail is a new shot and does not fill the one before.
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertEqual(toast.model.shots.count, 20)
        XCTAssertNil(toast.model.shots.last?.caption)
        XCTAssertEqual(captions(toast).filter { $0 == "done" }.count, 1, "a working thumbnail overwrote a finished shot")
    }

    func testARefusalForAShotAlreadyPushedOutTakesNoOtherShotWithIt() throws {
        let toast = quiet()
        toast.showWorking(try ShotToastRig.picture())
        for i in 1...20 { toast.model.add(try ShotToastRig.picture(), caption: "x\(i)", file: nil, full: try ShotToastRig.picture()) }
        let before = captions(toast)
        toast.showRefusal(.pasteboard)
        XCTAssertEqual(captions(toast), before, "a refusal for a shot that was gone took a shot that is here")
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertFalse(toast.advance(by: 8.5))
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertFalse(toast.advance(by: 0.5), "the plaque's time is up and the shots come back")
        XCTAssertNil(toast.model.refusal)
        XCTAssertEqual(captions(toast), before)
        XCTAssertEqual(toast.remaining, 5, "the group lives on from a life of its own")
    }

    // MARK: The ✕

    func testTheXInTheRowTakesTheShotThePointerIsOnAndTheRowClosesUpAroundIt() throws {
        let toast = quiet()
        try fill(toast, 1...5)
        toast.unfold()
        let middle = toast.model.shot(2)?.id ?? -1
        toast.model.focus = middle
        toast.close()
        XCTAssertEqual(captions(toast), ["c1", "c2", "c4", "c5"])
        XCTAssertTrue(toast.model.unfolded, "the row closed with the shot")
        XCTAssertNil(toast.model.focus)
        XCTAssertEqual(toast.model.offset, 0)
        // The pointer is on nothing: the capsule is not up, and a ✕ that arrives is about the newest.
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        toast.close()
        XCTAssertEqual(captions(toast), ["c2", "c4", "c5"])
    }

    func testTheXOnTheOldestOfAScrolledRowLeavesTheOffsetOnARestInsideTheShorterList() throws {
        let toast = quiet()
        try fill(toast, 1...5)
        toast.unfold()
        toast.showOldest()
        XCTAssertEqual(toast.model.offset, 2 * ShotShelf.pitch)
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        toast.close()
        XCTAssertEqual(toast.model.shots.count, 4)
        XCTAssertEqual(toast.model.offset, ShotShelf.pitch, "the row is scrolled past the end of the shorter list")
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        toast.close()
        XCTAssertEqual(toast.model.shots.count, 3)
        XCTAssertEqual(toast.model.offset, 0)
    }

    func testTheXWhileTheRowHoldsTwoLeavesOneAndTheSingleShotFoldsBackThenTheLastXEndsTheWindow() throws {
        let toast = quiet()
        var taken = 0, given = 0
        toast.takeKey = { taken += 1 }
        toast.yieldKey = { given += 1 }
        try fill(toast, 1...2)
        toast.unfold()
        XCTAssertEqual(taken, 1)
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        toast.close()
        XCTAssertEqual(captions(toast), ["c2"])
        XCTAssertFalse(toast.model.unfolded, "a row of one shot is a single shot again")
        XCTAssertEqual(given, 1, "the keys stayed with the row that is gone")
        XCTAssertFalse(toast.model.isPile)
        XCTAssertNotNil(toast.model.current)
        toast.close()
        XCTAssertTrue(toast.model.shots.isEmpty, "the ✕ of a single shot is the window's end")
        XCTAssertNil(toast.model.content)
        XCTAssertFalse(toast.model.shown)
        XCTAssertTrue(toast.holds.isEmpty)
        // And the window is not a ghost: one more shot is a window again.
        try fill(toast, 3...3)
        XCTAssertEqual(captions(toast), ["c3"])
        XCTAssertTrue(toast.model.shown)
    }

    func testTheXOnAShotStillBeingWrittenTakesItAndItsResultComesBackAsANewShot() throws {
        let toast = quiet()
        try fill(toast, 1...2)
        toast.showWorking(try ShotToastRig.picture())
        toast.unfold()
        let working = try XCTUnwrap(toast.model.shots.last)
        XCTAssertNil(working.caption)
        toast.model.focus = working.id
        toast.close()
        XCTAssertEqual(captions(toast), ["c1", "c2"])
        // What the person closed was the thumbnail; the capture it stood for goes on, and its result is a shot.
        toast.showDone(try ShotToastRig.picture(), caption: "result", file: nil)
        XCTAssertEqual(captions(toast), ["c1", "c2", "result"], "the result filled a shot that is gone, or went nowhere")
    }

    func testTheXOnAPileWithShotsInItIsTheWholeWindowAndTakesWhatTheyHeld() throws {
        let toast = quiet()
        try fill(toast, 1...7)
        toast.close()
        XCTAssertTrue(toast.model.shots.isEmpty)
        XCTAssertTrue(toast.sources().isEmpty)
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertNil(toast.model.refusal)
    }

    // MARK: A refusal over a list

    func testARefusalCoversTheListWithoutEndingItAndTheListComesBackAfterNineSeconds() throws {
        let toast = quiet()
        try fill(toast, 1...3)
        toast.showRefusal(.pasteboard)
        XCTAssertEqual(toast.model.shots.count, 3, "a refusal about another thing took the list")
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertNil(toast.model.current, "nothing of the shots can be acted on from under a plaque")
        XCTAssertNil(toast.model.dragPayload)
        XCTAssertNil(toast.model.editSource)
        XCTAssertFalse(toast.model.isPile)
        XCTAssertFalse(toast.model.showsShots)
        XCTAssertNil(toast.fullPicture())
        XCTAssertNil(toast.shareItems())
        XCTAssertEqual(toast.remaining, 9)
        XCTAssertFalse(toast.advance(by: 8.5))
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertNil(toast.model.refusal)
        XCTAssertEqual(captions(toast), expected(1...3))
        XCTAssertTrue(toast.model.isPile)
        XCTAssertEqual(toast.remaining, 5)
        XCTAssertFalse(toast.advance(by: 4.5))
        XCTAssertTrue(toast.advance(by: 0.5), "the group's life after the plaque")
    }

    func testTheXOnARefusalOverAListTakesOnlyThePlaque() throws {
        let toast = quiet()
        try fill(toast, 1...3)
        toast.showRefusal(.pasteboard)
        toast.showRefusal(.encoding)
        toast.close()
        XCTAssertNil(toast.model.refusal)
        XCTAssertEqual(captions(toast), expected(1...3), "the ✕ of a plaque took the shots it covered")
        XCTAssertEqual(toast.remaining, 5)
        toast.showRefusal(.pasteboard)
        try fill(toast, 4...4)
        XCTAssertNil(toast.model.refusal, "a shot that comes under a plaque is the window")
        XCTAssertEqual(captions(toast), expected(1...4))
    }

    func testARefusalWithNothingUnderItIsTheWindowAndItsXEndsIt() throws {
        let toast = quiet()
        toast.showRefusal(.noPermission)
        XCTAssertTrue(toast.model.shots.isEmpty)
        toast.close()
        XCTAssertNil(toast.model.refusal)
        XCTAssertFalse(toast.model.shown)
    }

    func testARefusalOverAnOpenRowFoldsItAndGivesTheKeysBack() throws {
        let toast = quiet()
        var taken = 0, given = 0
        toast.takeKey = { taken += 1 }
        toast.yieldKey = { given += 1 }
        try fill(toast, 1...4)
        toast.unfold()
        toast.model.focus = toast.model.shot(0)?.id ?? -1
        toast.showRefusal(.pasteboard)
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertNil(toast.model.focus)
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(given, 1, "the keys stayed with a row that a plaque covered")
        toast.close()
        XCTAssertTrue(toast.model.isPile, "the shots are a pile again")
        XCTAssertEqual(given, 1)
    }

    // MARK: What the window is

    func testAPictureSetAsTheContentReplacesTheListAndARefusalSetAsItLeavesTheListUnderneath() throws {
        let toast = quiet()
        try fill(toast, 1...5)
        toast.unfold()
        toast.model.focus = toast.model.shot(1)?.id ?? -1
        toast.model.content = .picture(try ShotToastRig.picture(), caption: "only", file: nil)
        XCTAssertEqual(captions(toast), ["only"], "the list stayed behind the picture")
        XCTAssertFalse(toast.model.unfolded)
        XCTAssertNil(toast.model.focus)
        XCTAssertEqual(toast.model.offset, 0)
        guard case .picture(_, let caption, _)? = toast.model.content else { return XCTFail("\(String(describing: toast.model.content))") }
        XCTAssertEqual(caption, "only")

        try fill(toast, 6...7)
        toast.model.content = .refusal(title: "t", body: "b", offersSettings: false)
        XCTAssertEqual(toast.model.shots.count, 3, "a refusal set as the content took the shots it covers: they are kept under it")
        guard case .refusal? = toast.model.content else { return XCTFail("the refusal is not the content") }
        toast.model.content = nil
        XCTAssertTrue(toast.model.shots.isEmpty)
        XCTAssertNil(toast.model.refusal)
        XCTAssertNil(toast.model.content)
        toast.model.content = .picture(try ShotToastRig.picture(), caption: nil, file: nil)
        XCTAssertEqual(toast.model.shots.count, 1)
        toast.model.say(.picture(try ShotToastRig.picture(), caption: nil, file: nil))
        XCTAssertNil(toast.model.refusal, "a picture is not a refusal")
    }
}
