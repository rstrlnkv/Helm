import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The pile's Copy All, pressed as the capsule presses it, puts every finished shot of the window on the clipboard in
/// one write, in the list's order, or tells why it did not and puts none.** The controller, the toast and the session
/// are the app's own, over real files; the board counts a write a call. What the engine does with a list is
/// `TheGroupIsCopiedInOneWriteTests`; read here are the shots the toast hands it (the finished ones, the held and the
/// written, oldest first, at most twenty), what the person is told, and what the window is after.
///
/// Total failure of the subject prints: a write a shot, a shot still being written that is copied as nothing, a copy
/// that did not happen and was not told, a refusal that takes the group with it, a group of twenty-five that copies
/// twenty-five.
@MainActor
final class TheGroupIsCopiedInOneWriteFromThePileTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "copy-all")
        scenes.append(scene)
        return scene
    }

    private func width(of png: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil), "a write that is no picture")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    /// A shot that was only copied: it holds its picture and has no file.
    private func copied(_ s: PileScene, width: Int) throws {
        s.toast.showDone(try ShotToastRig.picture(width: width, height: 90), caption: ScStr.copied, file: nil)
    }

    private func refusalBody(_ s: PileScene) -> String? {
        if case .refusal(_, let body, _)? = s.toast.model.refusal { body } else { nil }
    }

    // MARK: One write

    func testCopyAllIsOneWriteWhateverTheNumberOfShotsInTheListsOrderWithFilesAndHeldPicturesMixed() async throws {
        for n in [1, 3, 20] {
            let s = try scene()
            var expected: [Int] = []
            for i in 0..<n {
                let width = 300 + 7 * i
                if i % 2 == 0 { try await s.take(width: width) } else { try copied(s, width: width) }
                expected.append(width)
            }
            XCTAssertEqual(s.toast.model.shots.count, n)
            let singles = s.board.singles
            XCTAssertEqual(s.board.lists.count, 0)
            s.toast.model.copyAll()
            await waitUntil("\(n): the group was written") { s.board.lists.count >= 1 }
            await grace(0.1)
            XCTAssertEqual(s.board.lists.count, 1, "\(n) shots were \(s.board.lists.count) writes")
            XCTAssertEqual(s.board.singles, singles, "\(n): a shot went by the single write")
            XCTAssertEqual(try XCTUnwrap(s.board.lists.first).map(width(of:)), expected, "\(n): not the list's order or not every shot")
            XCTAssertNil(s.toast.model.refusal, "\(n): a copy that was made was told as a refusal")
            XCTAssertEqual(s.toast.model.shots.count, n, "the copy changed the window")
        }
    }

    func testTwentyFiveShotsInIsTwentyOnTheBoardAndTheOldestFiveAreNotThere() async throws {
        let s = try scene()
        for i in 0..<25 { try copied(s, width: 100 + i) }
        s.toast.model.copyAll()
        await waitUntil("the group was written") { s.board.lists.count >= 1 }
        await grace(0.1)
        XCTAssertEqual(s.board.lists.count, 1)
        XCTAssertEqual(try XCTUnwrap(s.board.lists.first).map(width(of:)), Array(105..<125))
    }

    func testAShotStillBeingWrittenIsNotInTheGroupAndAGroupOfNothingFinishedIsNotWrittenOrTold() async throws {
        let s = try scene()
        s.toast.showWorking(try ShotToastRig.picture())
        s.toast.model.copyAll()
        await grace(0.2)
        XCTAssertEqual(s.board.lists.count, 0, "a working thumbnail was copied")
        XCTAssertNil(s.toast.model.refusal, "a group with nothing in it said something")

        try copied(s, width: 321)
        s.toast.showWorking(try ShotToastRig.picture())
        XCTAssertEqual(s.toast.model.shots.count, 2, "the held shot took the first working shot's place; the second working one is new")
        s.toast.model.copyAll()
        await waitUntil("the finished shots were written") { s.board.lists.count >= 1 }
        XCTAssertEqual(try XCTUnwrap(s.board.lists.first).count, s.toast.model.shots.filter { $0.caption != nil }.count)
        XCTAssertEqual(try XCTUnwrap(s.board.lists.first).count, 1)
    }

    // MARK: Told, and nothing on the board

    func testAFileThatIsGoneIsToldAndTheBoardGetsNoneOfTheGroupAndTheShotsAreBackAfterThePlaque() async throws {
        let s = try scene()
        let shots = [try await s.take(width: 400), try await s.take(width: 420), try await s.take(width: 440)]
        try FileManager.default.removeItem(at: try XCTUnwrap(shots[1].file))
        s.toast.model.copyAll()
        await waitUntil("the person was told") { s.toast.model.refusal != nil }
        XCTAssertEqual(refusalBody(s), ScStr.refusal(.encoding))
        XCTAssertEqual(s.board.lists.count, 0, "a group of two of the three was written")
        XCTAssertEqual(s.toast.model.shots.count, 3, "the plaque took the group with it")
        XCTAssertFalse(s.toast.advance(by: 8.5))
        XCTAssertFalse(s.toast.advance(by: 0.5))
        XCTAssertNil(s.toast.model.refusal)
        XCTAssertTrue(s.toast.model.isPile)
        XCTAssertEqual(s.toast.sources().count, 3)
    }

    func testABoardThatRefusesIsToldAndANewTryAfterItWritesTheWholeGroup() async throws {
        let s = try scene()
        for i in 0..<3 { try copied(s, width: 200 + i) }
        s.board.accepts = false
        s.toast.model.copyAll()
        await waitUntil("the person was told") { s.toast.model.refusal != nil }
        XCTAssertEqual(refusalBody(s), ScStr.refusal(.pasteboard))
        XCTAssertEqual(s.board.lists.count, 0)
        XCTAssertEqual(s.board.singles, 0, "a refused group fell back to a write a shot")
        s.toast.close()
        XCTAssertNil(s.toast.model.refusal)
        s.board.accepts = true
        s.toast.model.copyAll()
        await waitUntil("the group was written") { s.board.lists.count >= 1 }
        XCTAssertEqual(try XCTUnwrap(s.board.lists.first).count, 3)
    }

    /// The module goes off with the group's copy in flight: the board is not written afterwards, and a refusal that
    /// would have been said is not said over a window that is gone.
    func testAGroupCopyInFlightWhenTheModuleGoesOffReachesNoBoardAndSaysNothing() async throws {
        let s = try scene()
        for i in 0..<3 { try copied(s, width: 200 + i) }
        s.toast.model.copyAll()
        s.controller.cancel()
        await grace(0.3)
        XCTAssertEqual(s.board.lists.count, 0, "a group was written after the module went off")
        XCTAssertEqual(s.board.singles, 0)
        XCTAssertNil(s.toast.model.refusal)
        XCTAssertTrue(s.toast.model.shots.isEmpty)
        XCTAssertFalse(s.toast.model.shown)
        // The control: the same press with the module on writes.
        let on = try scene()
        for i in 0..<3 { try copied(on, width: 200 + i) }
        on.toast.model.copyAll()
        await waitUntil("the control group was written") { on.board.lists.count >= 1 }
    }

    func testAnOpenRowCopiesTheSameGroupWhateverShotThePointerIsOn() async throws {
        let s = try scene()
        for i in 0..<4 { try copied(s, width: 210 + i) }
        s.toast.unfold()
        s.toast.model.focus = s.toast.model.shot(1)?.id ?? -1
        s.toast.model.copyAll()
        await waitUntil("the group was written") { s.board.lists.count >= 1 }
        XCTAssertEqual(try XCTUnwrap(s.board.lists.first).map(width(of:)), [210, 211, 212, 213])
        XCTAssertTrue(s.toast.model.unfolded, "a copy folded the row")
    }

    // MARK: The pile leaves as one

    func testADragOfThePileCarriesEveryFinishedShotButTheOneItBeganOnInTheListsOrder() async throws {
        let s = try scene()
        let first = try await s.take(width: 400)
        try copied(s, width: 410)
        let third = try await s.take(width: 420)
        s.toast.showWorking(try ShotToastRig.picture())
        let model = s.toast.model
        XCTAssertTrue(model.isPile)
        let others = model.othersDragged(with: third.id)
        XCTAssertEqual(others.count, 2, "the group's other finished shots: the file and the held one, and not the working one")
        guard others.count == 2, case .file(let url) = others[0], case .picture(let image) = others[1] else { return XCTFail("\(others)") }
        XCTAssertEqual(url, first.file)
        XCTAssertEqual(image.width, 410)
        // A file that is gone is not carried: the drop would receive a name with nothing behind it.
        try FileManager.default.removeItem(at: try XCTUnwrap(first.file))
        XCTAssertEqual(model.othersDragged(with: third.id).count, 1)
        // Not a pile: nothing but the shot itself.
        model.unfold()
        XCTAssertTrue(model.unfolded)
        XCTAssertTrue(model.othersDragged(with: third.id).isEmpty, "a drag from the row carried the row")
        s.toast.fold()
        XCTAssertFalse(model.othersDragged(with: third.id).isEmpty)
        s.toast.showRefusal(.pasteboard)
        XCTAssertTrue(model.othersDragged(with: third.id).isEmpty, "a drag from under a plaque carried the group")
        XCTAssertNil(model.dragPayload)
    }

    func testASingleShotsDragCarriesNothingBesideIt() async throws {
        let s = try scene()
        let only = try await s.take(width: 400)
        XCTAssertTrue(s.toast.model.othersDragged(with: only.id).isEmpty)
        XCTAssertNotNil(s.toast.model.dragPayload)
    }
}
