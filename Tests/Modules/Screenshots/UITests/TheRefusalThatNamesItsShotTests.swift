import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A refusal takes away only the shot whose own write it is (`showRefusal(_, ofItsWrite: true)`, the one call in
/// `ScreenshotsCapture.present`); a refusal of a Copy, an Edit or any other thing the still-writing newest shot has no
/// part in leaves it, and its result lands in its own slot.** The shots under a plaque are kept and come back with
/// it. What the code also does, pinned here because it is a person's loss and not an accident of the test: **a
/// result that arrives while a plaque is up takes the plaque down** (`showDone` says `nil`: the newest wins), so a
/// refused Copy's sentence is up for as long as the write took to finish, not for its nine seconds.
///
/// Total failure of the subject prints: a refusal of a Copy that took the writing shot with it, a result that
/// arrived as a shot of its own beside the empty one, a refusal of the write that left an empty thumbnail behind.
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

    func testARefusalOfItsOwnWriteTakesThatShotAndOnlyThatShot() throws {
        let toast = try writing()
        toast.showRefusal(.encoding, ofItsWrite: true)
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3"], "the writing shot stayed, or another went with it")
        // The plaque's nine seconds, and the three finished shots are the window again, with a life of their own.
        XCTAssertFalse(toast.advance(by: 8.5))
        XCTAssertNotNil(toast.model.refusal)
        XCTAssertFalse(toast.advance(by: 0.5))
        XCTAssertNil(toast.model.refusal)
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3"])
    }

    func testARefusalOfItsOwnWriteWithNothingWritingTakesNothing() throws {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        for i in 1...3 { toast.showDone(try ShotToastRig.picture(), caption: "done\(i)", file: nil) }
        toast.showRefusal(.encoding, ofItsWrite: true)
        XCTAssertEqual(captions(toast), ["done1", "done2", "done3"], "a refusal with no writing shot took a finished one")
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
