import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A refusal of the still-writing newest shot's own write (`showRefusal(_, keeping:)`, the one call in
/// `CaptureController.present` that passes it) leaves that shot on the list, finished, and the other shots stay as they were; a
/// refusal of a Copy, an Edit or any other thing the shot has no part in leaves it still writing, and its result lands in
/// its own slot.** The marks a person drew are in the picture of the shot whose write was refused, so it is not let go
/// with its refusal. The shots under a plaque are kept and come back with it. What the code also does, pinned here
/// because it is a person's loss and not an accident of the test: **a result that arrives while a plaque is up takes the
/// plaque down** (`showDone` says `nil`: the newest wins), so a refused Copy's sentence is up for as long as the write
/// took to finish, not for its nine seconds.
///
/// Total failure of the subject prints: a refusal of a Copy that took the writing shot with it, a result that
/// arrived as a shot of its own beside the empty one, a refusal of the write that took the shot away or left it with no caption.
@MainActor
final class TheRefusalThatNamesItsShotTests: XCTestCase {

    private var toasts: [ShotToast] = []

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        super.tearDown()
    }

    /// Three finished shots, the row open on them, a fourth that is still being written.
    private func writing() throws -> ShotToast {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        for i in 1...3 { toast.showDone(try ShotToastRig.picture(), caption: "done\(i)", file: nil) }
        toast.unfold()
        XCTAssertTrue(toast.model.unfolded, "the control: the row is open")
        toast.showWorking(try ShotToastRig.picture())
        XCTAssertEqual(toast.model.shots.count, 4, "the control: the newest is on the list, still writing")
        XCTAssertNil(toast.model.shots.last?.caption)
        return toast
    }

    private func captions(_ toast: ShotToast) -> [String?] { toast.model.shots.map(\.caption) }

    func testARefusalOfACopyLeavesTheWritingShotAndItsResultLandsInItsSlot() throws {
        let toast = try writing()
        let writingID = try XCTUnwrap(toast.model.shots.last).id
        toast.showRefusal(.pasteboard)
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertEqual(toast.model.shots.count, 4, "a refusal of a Copy took a shot with it")
        XCTAssertEqual(toast.model.shots.last?.id, writingID)
        XCTAssertFalse(toast.model.unfolded, "the plaque left the row open over the shots")

        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: nil)
        XCTAssertEqual(toast.model.shots.count, 4, "the result came as a shot of its own")
        XCTAssertEqual(toast.model.shots.last?.id, writingID, "the result did not land in the writing shot's slot")
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3", "Saved"])
    }

    /// The toast carries what it is handed into the slot of the shot that was writing: that shot, and no other, becomes
    /// finished, with the caption handed and the full picture handed (1200 x 700, which the reduced copy that is drawn is
    /// not), and no file. What the caption and the picture are is the controller's to say, and is read there
    /// (`ARefusedDeliveryKeepsTheMarksAndAnUncomposedPictureIsSaidTests`); this level reads that they arrive, in the
    /// right slot, and stay when the plaque goes.
    func testARefusalOfItsOwnWriteLeavesThatShotFinishedAndTheOthersToo() throws {
        let toast = try writing()
        let writingID = try XCTUnwrap(toast.model.shots.last).id
        toast.showRefusal(.encoding, keeping: ShotToast.Kept(image: try ShotToastRig.picture(width: 1200, height: 700), caption: "kept",
                                                              file: nil, reading: nil))
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertEqual(toast.model.shots.count, 4, "the writing shot went with the refusal of its own write, or another went with it")
        XCTAssertEqual(toast.model.shots.last?.id, writingID, "the shot that stayed is not the one that was writing")
        XCTAssertEqual(Array(captions(toast).prefix(3)), ["done1", "done2", "done3"], "a finished shot changed or went")
        func assertKept(_ when: String) {
            let shot = toast.model.shots.first { $0.id == writingID }
            XCTAssertEqual(shot?.caption, "kept", "\(when): the shot is gone or not finished with the caption it was handed")
            XCTAssertEqual(shot?.full.map { [$0.width, $0.height] }, [1200, 700], "\(when): the shot does not hold the picture it was handed")
            XCTAssertNil(shot?.file, "\(when): the shot has a file")
        }
        assertKept("under the plaque")
        // The plaque's nine seconds, and the four shots are the window again, with a life of their own.
        XCTAssertFalse(toast.advance(by: 8.5))
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertNil(toast.model.refusal)
        XCTAssertEqual(toast.model.shots.count, 4)
        XCTAssertEqual(toast.model.shots.last?.id, writingID)
        XCTAssertEqual(Array(captions(toast).prefix(3)), ["done1", "done2", "done3"])
        assertKept("after the plaque")
    }

    /// A refusal that keeps nothing, with nothing writing, takes no finished shot and adds none.
    func testARefusalThatKeepsNothingWithNothingWritingTakesNothing() throws {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        for i in 1...3 { toast.showDone(try ShotToastRig.picture(), caption: "done\(i)", file: nil) }
        toast.showRefusal(.encoding)
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3"], "a refusal with no writing shot took a finished one or added one")
    }

    /// The thumbnail was not shown, so no shot is writing: the picture that is kept comes as a shot of its own, the newest,
    /// and no finished shot is written over.
    func testARefusalThatKeepsAPictureWithNothingWritingAddsItAsTheNewestAndWritesOverNoOne() throws {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        for i in 1...3 { toast.showDone(try ShotToastRig.picture(), caption: "done\(i)", file: nil) }
        let ids = toast.model.shots.map(\.id)
        toast.showRefusal(.encoding, keeping: ShotToast.Kept(image: try ShotToastRig.picture(width: 1200, height: 700), caption: "kept",
                                                              file: nil, reading: nil))
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3", "kept"], "the kept picture overwrote a finished shot or was not added")
        XCTAssertEqual(Array(toast.model.shots.map(\.id).prefix(3)), ids, "a finished shot was replaced")
        XCTAssertEqual(toast.model.shots.last?.full.map { [$0.width, $0.height] }, [1200, 700])
        XCTAssertNotNil(toast.model.refusal)
    }

    /// The code's own reading of «newest wins»: the result of the writing shot takes down a plaque that is up.
    /// What a person loses: the sentence of a refusal of a Copy, for the time the write still had to take. The
    /// plaque is up for no minimum time; a result arriving a tenth of a second after it ends it at that step.
    func testAResultThatArrivesUnderAPlaqueTakesThePlaqueDown() throws {
        let toast = try writing()
        toast.showRefusal(.pasteboard)
        XCTAssertFalse(toast.advance(by: 0.1))
        XCTAssertNotNil(toast.model.refusal, "the control: the plaque is up a tenth of a second in")
        toast.showDone(try ShotToastRig.picture(), caption: "Saved", file: nil)
        XCTAssertNil(toast.model.refusal, "the result left the plaque up: the code changed from «newest wins», say so here")
        XCTAssertEqual(toast.remaining, 5, "the result starts the shots' life, not what was left of the plaque's")
    }
}
