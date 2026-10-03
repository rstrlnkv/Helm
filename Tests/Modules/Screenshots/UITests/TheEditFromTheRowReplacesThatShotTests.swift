import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Edit» on a shot of the row opens the editor on that shot, and «Done» replaces that shot's file and no other;
/// the shots beside it are as they were.** Real files in a scratch folder written by the module's own writer, a Trash
/// that is a folder, the controller as the running app builds it, an overlay built and worked by hand. Three shots are
/// taken, the row is opened and the middle one is edited; what is read afterwards is every file's bytes, every
/// shot's reading, the Trash's own list and what the window holds.
///
/// Total failure of the subject prints: the file of another shot replaced, a neighbour whose bytes or reading moved,
/// a shot that is in the window twice or not at all, an editor opened on the shot the pointer had moved to by the time
/// the screen was frozen, a stranger's file moved to the Trash.
@MainActor
final class TheEditFromTheRowReplacesThatShotTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "edit-row")
        scenes.append(scene)
        return scene
    }

    private func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    private func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }
    private func files(_ s: PileScene) -> [URL?] { s.toast.model.shots.map(\.file) }

    private func finish(_ s: PileScene, _ exit: EditorExit = .confirm) async throws {
        let overlay = try XCTUnwrap(s.overlay)
        overlay.perform(.exit(exit))
        await waitUntil("the edit was delivered") { !s.controller.isBusy }
    }

    private func edit(_ s: PileScene, _ shot: ShotToastModel.Shot, opened count: Int, drawing: Bool = true) async throws {
        s.press(shot)
        await waitUntil("the editor opened") { s.editors == count }
        if drawing { draw(s) }
    }

    private func draw(_ s: PileScene) {
        if let overlay = s.overlay { s.draw(overlay) }
    }

    /// Three shots, written and on the list, the row open.
    private func three(_ s: PileScene) async throws -> [ShotToastModel.Shot] {
        let shots = [try await s.take(width: 400), try await s.take(width: 420), try await s.take(width: 440)]
        XCTAssertEqual(Set(shots.compactMap { $0.file }).count, 3, "three shots are three files")
        s.toast.unfold()
        XCTAssertTrue(s.toast.model.unfolded, "the control: the row is open")
        return shots
    }

    // MARK: The middle one

    func testEditingTheMiddleShotReplacesItsFileAndTheOtherTwoAreByteForByteWhatTheyWere() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (try XCTUnwrap(shots[0].file), try XCTUnwrap(shots[1].file), try XCTUnwrap(shots[2].file))
        let before = (try bytes(first), try bytes(middle), try bytes(last))
        let folder = names(s.desktop)
        XCTAssertEqual(folder.count, 3)

        try await edit(s, shots[1], opened: 1)
        XCTAssertEqual(files(s), [first, last], "the shot that is in the editor is still in the window, or another one left")
        XCTAssertTrue(s.toast.holds.contains(.editor))
        XCTAssertFalse(s.toast.model.unfolded, "what is left of the group lies under the editor folded")
        try await finish(s)

        XCTAssertEqual(s.trash.moved, [middle], "the Trash took a file that is not the edited shot's")
        XCTAssertEqual(names(s.desktop), folder, "a file was added or lost: the edit takes the name of the one it replaces")
        XCTAssertEqual(try bytes(first), before.0, "the first shot's file moved")
        XCTAssertEqual(try bytes(last), before.2, "the last shot's file moved")
        XCTAssertNotEqual(try bytes(middle), before.1, "the edited shot's file is what it was")
        XCTAssertEqual(FileShotWriter().reading(of: first), shots[0].reading, "the first shot's reading is no longer its file's")
        XCTAssertEqual(FileShotWriter().reading(of: last), shots[2].reading, "the last shot's reading is no longer its file's")

        // The window holds three shots again: the two that stayed, and the edit, which is the newest.
        XCTAssertEqual(files(s), [first, last, middle], "the edited shot did not return to the window, or did twice")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced)
        XCTAssertEqual(s.toast.model.shots.last?.reading, FileShotWriter().reading(of: middle), "the edit is read as the file it is now")
        XCTAssertNotEqual(s.toast.model.shots.last?.reading, shots[1].reading)
        XCTAssertEqual(s.toast.model.shot(0)?.reading, shots[0].reading, "a neighbour's reading was spent")
        XCTAssertFalse(s.toast.holds.contains(.editor), "the editor's hold outlived the editor")
        XCTAssertFalse(s.controller.isBusy)

        // Another shot of the row, edited after: only that one is replaced, the first edit's file stays as it was.
        let afterFirst = try bytes(middle)
        s.toast.unfold()
        XCTAssertTrue(s.toast.model.unfolded)
        let second = try XCTUnwrap(s.toast.model.shot(0))
        try await edit(s, second, opened: 2)
        XCTAssertEqual(files(s), [last, middle])
        try await finish(s)
        XCTAssertEqual(s.trash.moved, [middle, first], "the second edit moved a file that is not the first shot's")
        XCTAssertEqual(try bytes(last), before.2, "the last shot's file moved at the second edit")
        XCTAssertEqual(try bytes(middle), afterFirst, "the first edit's file was touched by the second")
        XCTAssertNotEqual(try bytes(first), before.0)
        XCTAssertEqual(names(s.desktop), folder)
        XCTAssertEqual(files(s), [last, middle, first])
        XCTAssertEqual(s.toast.model.shots.map(\.caption), [ScStr.savedAndCopied, ScStr.replaced, ScStr.replaced])
    }

    /// The press is about the shot the pointer was on when it was pressed; by the time the screen is frozen the pointer
    /// may be on another, and the editor still opens on the one that was pressed.
    func testTheEditorTakesTheShotThatWasPressedNotTheOneThePointerIsOnWhenItOpens() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (try XCTUnwrap(shots[0].file), try XCTUnwrap(shots[1].file), try XCTUnwrap(shots[2].file))
        let before = (try bytes(first), try bytes(last))
        s.capture.hold()
        s.press(shots[1])
        await waitUntil("the freeze is held open") { s.capture.isHeld }
        s.toast.model.focus = shots[2].id
        XCTAssertEqual(s.toast.model.current?.id, shots[2].id, "the control: the pointer is on another shot now")
        s.capture.release()
        await waitUntil("the editor opened") { s.editors == 1 }
        XCTAssertEqual(files(s), [first, last], "the shot the pointer had moved to left the window under the editor")
        draw(s)
        try await finish(s)
        XCTAssertEqual(s.trash.moved, [middle], "the editor's Done replaced the shot the pointer had moved to")
        XCTAssertEqual(try bytes(first), before.0)
        XCTAssertEqual(try bytes(last), before.1)
    }

    /// The person closes the shot that is being opened in the editor, between the press and the editor's coming up.
    func testAShotClosedWhileTheEditorIsOpeningTakesNoOtherShotAndLeavesNoHold() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, last) = (try XCTUnwrap(shots[0].file), try XCTUnwrap(shots[2].file))
        s.capture.hold()
        s.press(shots[1])
        await waitUntil("the freeze is held open") { s.capture.isHeld }
        s.toast.model.focus = shots[1].id
        s.toast.close()
        XCTAssertEqual(files(s), [first, last])
        s.capture.release()
        await waitUntil("the editor opened") { s.editors == 1 }
        XCTAssertEqual(files(s), [first, last], "an unknown shot took another with it")
        try await finish(s, .confirm)
        XCTAssertFalse(s.toast.holds.contains(.editor), "an editor that took no shot left a hold behind")
        XCTAssertEqual(s.toast.model.shots.count, 3, "the edit of the shot that was closed came back as a shot")
    }

    // MARK: The edge of the row

    func testEditingTheOnlyShotLeftEndsTheWindowAndTheEditComesBackAsTheWindow() async throws {
        let s = try scene()
        let shot = try await s.take(width: 400)
        let url = try XCTUnwrap(shot.file)
        try await edit(s, shot, opened: 1)
        XCTAssertTrue(s.toast.model.shots.isEmpty)
        XCTAssertFalse(s.toast.model.shown, "the window stayed up over an editor with nothing in it")
        XCTAssertFalse(s.toast.holds.contains(.editor), "a hold that nothing would end")
        try await finish(s)
        XCTAssertEqual(s.trash.moved, [url])
        XCTAssertEqual(files(s), [url])
        XCTAssertTrue(s.toast.model.shown)
    }

    func testACancelledEditLeavesEveryFileAsItWasTheShotOutOfTheWindowAndTheLifeRunning() async throws {
        let s = try scene()
        let shots = try await three(s)
        let urls = try shots.map { try XCTUnwrap($0.file) }
        let before = try urls.map { try bytes($0) }
        try await edit(s, shots[1], opened: 1, drawing: false)
        XCTAssertTrue(s.toast.holds.contains(.editor))
        try XCTUnwrap(s.overlay).perform(.close)
        await waitUntil("the editor was closed") { !s.controller.isBusy }
        XCTAssertEqual(s.trash.asked, [], "a cancel replaced a file")
        XCTAssertEqual(try urls.map { try bytes($0) }, before, "a cancel changed a file")
        XCTAssertEqual(names(s.desktop).count, 3)
        XCTAssertFalse(s.toast.holds.contains(.editor), "the editor is closed and its hold stays")
        XCTAssertEqual(files(s), [urls[0], urls[2]], "the shot that went into the editor is not in the window")
        XCTAssertFalse(s.toast.advance(by: 4.5))
        XCTAssertTrue(s.toast.advance(by: 0.5), "the life of what is left did not run once the editor was closed")
    }

    // MARK: A stranger under the name

    func testAStrangerUnderTheEditedShotsNameIsNeverTrashedAndTheEditIsKept() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (try XCTUnwrap(shots[0].file), try XCTUnwrap(shots[1].file), try XCTUnwrap(shots[2].file))
        let before = (try bytes(first), try bytes(last))
        try await edit(s, shots[1], opened: 1)
        // While the editor is open somebody saves their own picture over the name the shot has.
        let stranger = try ShotToastRig.writePNG(try ShotToastRig.picture(width: 77, height: 33), in: s.desktop,
                                                 named: middle.lastPathComponent)
        XCTAssertEqual(stranger, middle)
        let strangerBytes = try bytes(middle)
        try await finish(s)

        XCTAssertEqual(s.trash.asked, [], "a file that is not the shot's was handed to the Trash")
        XCTAssertEqual(try bytes(middle), strangerBytes, "the stranger's file was overwritten")
        XCTAssertEqual(try bytes(first), before.0)
        XCTAssertEqual(try bytes(last), before.1)
        XCTAssertGreaterThan(names(s.desktop).count, 3, "the edit is nowhere: it was lost")
        XCTAssertFalse(s.toast.holds.contains(.editor))
        XCTAssertFalse(s.controller.isBusy)
    }

    // MARK: A shot that is not written yet

    func testEditOnAShotStillBeingWrittenOpensNothingAndTakesNoShot() async throws {
        let s = try scene()
        _ = try await three(s)
        s.toast.showWorking(try ShotToastRig.picture())
        let working = try XCTUnwrap(s.toast.model.shots.last)
        XCTAssertNil(working.caption)
        let count = s.toast.model.shots.count
        s.press(working)
        XCTAssertFalse(s.controller.isBusy, "an edit of nothing is a press that is busy")
        XCTAssertEqual(s.editors, 0)
        XCTAssertEqual(s.toast.model.shots.count, count)
    }
}
