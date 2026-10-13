import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Esc, a Return that changed nothing and ⌘C of a saved shot give the shot back as it was, and the first two write
/// nothing.** Three ways out of an editor opened from the thumbnail, each on a shot that was really taken: Esc, which brings the
/// thumbnail back with what it held (a saved shot's file and reading, a copied shot's picture); Return with no mark
/// and the area still the whole picture, which is no change, so the file stays the same file, the Trash is not asked and
/// the clipboard takes no write; and ⌘C of a marked edit, which puts the marked picture on the clipboard and leaves the
/// saved shot's file, and the thumbnail that comes back is that shot's, with its file and its reading. The edges
/// beside them are what does not give the shot back: Return with one mark and Return with no mark and the area reshaped
/// inside the picture, which replace the file, and ⌘C of a shot that was only copied, which stays a new copied shot.
/// Around them: the place the shot comes back to in a group of three and in a full group, the window or the module going
/// while the editor is open, the editor's hold and the group's life afterwards, ⌘C of a saved shot with no mark,
/// «Edit» pressed again on the shot that came back, a file renamed while the editor was open, and a picture shown
/// reduced, the flash that ⌘C of a saved shot and Return with one mark play and that Esc and a Return that changed
/// nothing do not (the overlay closes at once on that Return), and ⌘C of a saved shot with the module switched off
/// before the copy runs, which writes nothing to the clipboard and leaves no window.
///
/// The controller is the running app's, over real files in a scratch folder written by the module's own writer, a
/// Trash that is a folder, a toast with no window and an overlay that is built and never ordered in (`PileScene`).
/// **Each case first asks whether its subject happened:** the shot was taken (its file, reading and bytes are held, or
/// the held picture and an empty folder), the editor opened on it and the shot left the window for it. A case whose
/// precondition fails stops there, with a line that begins "precondition" or with a failed unwrap, and none of the
/// lines below is then about the subject.
///
/// Total failure of the subject prints: "never reached: the editor opened on the shot", "precondition: the editor did
/// not open on the shot", and nothing from the expectations. A defect in the exits prints the expectations instead: a
/// window that holds no shot after Esc, a Trash that was asked for the file, a reading whose inode is another one's, a
/// clipboard that took a second write, a thumbnail with a held picture where a file was, an area lit by a Return that
/// changed nothing.
@MainActor
final class AnEditThatLeavesTheShotAsItWasGivesItBackTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "edit-keeps")
        scenes.append(scene)
        return scene
    }

    /// What a saved shot was the moment before the editor opened on it.
    private struct Saved {
        let shot: ShotToastModel.Shot
        let url: URL
        let reading: ShotReading
        let bytes: Data
        let names: [String]
        let copies: Int
        var written: WrittenShot { WrittenShot(url: url, reading: reading) }
    }

    private struct PreconditionFailed: Error {}

    /// The case stops here when its subject did not happen.
    private func require(_ ok: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard ok else {
            XCTFail("precondition: \(message)", file: file, line: line)
            throw PreconditionFailed()
        }
    }

    private func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    private func pixels(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: Taking a shot, opening the editor, leaving it

    /// A shot saved to the folder and copied, its file read back from the disk.
    private func saved(_ s: PileScene, width: Int = 400, height: Int = 300) async throws -> Saved {
        let shot = try await s.take(width: width, height: height)
        let url = try XCTUnwrap(shot.file)
        let reading = try XCTUnwrap(shot.reading)
        let bytes = try Data(contentsOf: url)
        try require(!bytes.isEmpty, "the shot's file is empty")
        try require(FileShotWriter().reading(of: url) == reading, "the shot's reading is not its file's")
        try require(names(s.desktop) == [url.lastPathComponent], "the folder holds more than the shot: \(names(s.desktop))")
        try require(s.board.singles == 1, "the shot was not copied once: \(s.board.singles)")
        try require(s.toast.model.editSource?.shot == WrittenShot(url: url, reading: reading), "the thumbnail offers no Edit of the file")
        return Saved(shot: shot, url: url, reading: reading, bytes: bytes, names: names(s.desktop), copies: s.board.singles)
    }

    /// A shot that was only copied: the save target is the clipboard, so it has a held picture and no file.
    private func copiedOnly(_ s: PileScene) async throws -> ShotToastModel.Shot {
        s.store.set(SaveTarget.clipboard.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400, height: 300), kind: .area))
        let shot = try XCTUnwrap(s.toast.model.shots.last, "no shot after a hand-off")
        try require(shot.file == nil && shot.reading == nil, "the shot has a file: \(String(describing: shot.file))")
        try require(shot.full != nil, "the shot holds no picture")
        try require(s.toast.model.editSource?.held != nil && s.toast.model.editSource?.shot == nil, "the thumbnail offers no Edit of the held picture")
        try require(names(s.desktop).isEmpty, "the clipboard target made a file: \(names(s.desktop))")
        try require(s.board.singles == 1, "the shot was not copied once: \(s.board.singles)")
        return shot
    }

    /// Edit pressed on `shot`; the editor that opened on it (the `count`th of the scene). The shot has left the window for
    /// it, and `staying` are the shots that are in the window still, oldest first.
    private func openEditor(_ s: PileScene, on shot: ShotToastModel.Shot, opened count: Int = 1,
                            staying others: [ShotToastModel.Shot.ID] = [],
                            file: StaticString = #filePath, line: UInt = #line) async throws -> CaptureOverlay {
        s.press(shot)
        await waitUntil("the editor opened on the shot", file: file, line: line) { s.editors == count }
        try require(s.editors == count, "the editor did not open on the shot", file: file, line: line)
        let overlay = try XCTUnwrap(s.overlay)
        try require(s.controller.isBusy, "the controller is free with the editor open", file: file, line: line)
        try require(s.toast.model.shots.map(\.id) == others,
                    "the window holds \(s.toast.model.shots.map(\.id)) under the editor, not \(others)", file: file, line: line)
        try require(others.isEmpty || s.toast.holds.contains(.editor), "the group under the editor has no hold on its life", file: file, line: line)
        try require(overlay.editedLayers.isEmpty, "the editor opened with marks on it", file: file, line: line)
        return overlay
    }

    /// Three saved shots, 400, 420 and 440 points wide, oldest first, and the row open: the Edit of a folded pile is the
    /// newest shot's, and a shot of the row is the one the pointer is on (`press`).
    private func three(_ s: PileScene) async throws -> [ShotToastModel.Shot] {
        let shots = [try await s.take(width: 400), try await s.take(width: 420), try await s.take(width: 440)]
        try require(Set(shots.map(\.id)).count == 3, "three shots are three identities: \(shots.map(\.id))")
        try require(shots.allSatisfy { $0.file != nil && $0.reading != nil }, "a shot of the three has no file or no reading")
        try require(s.toast.model.shots.map(\.id) == shots.map(\.id), "the window does not hold the three shots, oldest first")
        try require(s.board.singles == 3, "the three shots were not copied once each: \(s.board.singles)")
        s.toast.unfold()
        try require(s.toast.model.unfolded, "the row is not open")
        return shots
    }

    private func finish(_ s: PileScene, _ overlay: CaptureOverlay, _ exit: EditorExit) async {
        overlay.perform(.exit(exit))
        await waitUntil("the edit was delivered") { !s.controller.isBusy }
    }

    /// The Esc key as the person presses it, until the editor is gone.
    private func escape(_ s: PileScene, _ overlay: CaptureOverlay) async {
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                   characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        for _ in 0..<4 where s.controller.isBusy { overlay.keyDown(key); await grace(0.02) }
        await waitUntil("the editor ended") { !s.controller.isBusy }
    }

    // MARK: What is read afterwards

    /// The shot's file is the file it was: its bytes, its reading (the identity a rewrite would change), the folder's
    /// names; nothing was asked of the Trash and nothing is in it.
    private func assertTheFileIsTheSameFile(_ s: PileScene, _ before: Saved, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(FileShotWriter().reading(of: before.url), before.reading,
                       "the file is not the file the shot wrote: its inode, size or time moved", file: file, line: line)
        XCTAssertEqual(try? Data(contentsOf: before.url), before.bytes, "the file's bytes changed", file: file, line: line)
        XCTAssertEqual(names(s.desktop), before.names, "a file was added or lost", file: file, line: line)
        XCTAssertEqual(s.trash.asked, [], "the Trash was asked for a file", file: file, line: line)
        XCTAssertEqual(names(s.trash.folder), [], "something is in the Trash", file: file, line: line)
    }

    /// The window holds that one shot again, with its file and its reading, and Edit is offered on the file.
    private func assertTheSavedShotIsBack(_ s: PileScene, _ before: Saved, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the shot after the editor", file: file, line: line)
        XCTAssertTrue(s.toast.model.shown, "the thumbnail is not up", file: file, line: line)
        XCTAssertEqual(s.toast.model.shots.last?.file, before.url, "the thumbnail that came back has not the shot's file", file: file, line: line)
        XCTAssertEqual(s.toast.model.shots.last?.reading, before.reading, "the thumbnail that came back has not the shot's reading", file: file, line: line)
        XCTAssertEqual(s.toast.model.editSource?.shot, before.written, "Edit is not offered on the shot's file", file: file, line: line)
    }

    /// The window holds the copied shot again with its held picture and no file, and Edit is offered on the picture.
    private func assertTheCopiedShotIsBack(_ s: PileScene, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the shot after the editor: a shot with no file is gone for good", file: file, line: line)
        XCTAssertTrue(s.toast.model.shown, "the thumbnail is not up", file: file, line: line)
        XCTAssertNotNil(s.toast.model.shots.last?.full, "the thumbnail that came back holds no picture", file: file, line: line)
        XCTAssertNil(s.toast.model.shots.last?.file, "the copied shot has a file now", file: file, line: line)
        XCTAssertNotNil(s.toast.model.editSource?.held, "Edit is not offered on the held picture", file: file, line: line)
    }

    /// The window holds exactly these shots, in this order, each one the shot it was: its identity, file, reading and caption.
    private func assertTheWindowHolds(_ s: PileScene, _ shots: [ShotToastModel.Shot], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let now = s.toast.model.shots
        XCTAssertEqual(now.map(\.id), shots.map(\.id), "\(what): the shots in the window, or their order", file: file, line: line)
        XCTAssertEqual(now.map(\.file), shots.map(\.file), "\(what): a file", file: file, line: line)
        XCTAssertEqual(now.map(\.reading), shots.map(\.reading), "\(what): a reading", file: file, line: line)
        XCTAssertEqual(now.map(\.caption), shots.map(\.caption), "\(what): a caption", file: file, line: line)
        XCTAssertTrue(s.toast.model.shown, "\(what): the window is not up", file: file, line: line)
    }

    /// Every file of the group is the file it was, the Trash was not asked and the folder holds the group and nothing else.
    private func assertTheFilesAreAsTheyWere(_ s: PileScene, _ shots: [ShotToastModel.Shot], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for shot in shots {
            guard let url = shot.file else { XCTFail("\(what): a shot of the group has no file", file: file, line: line); continue }
            XCTAssertEqual(FileShotWriter().reading(of: url), shot.reading, "\(what): the file of shot \(shot.id) moved", file: file, line: line)
        }
        XCTAssertEqual(names(s.desktop).count, shots.count, "\(what): a file was added or lost", file: file, line: line)
        XCTAssertEqual(s.trash.asked, [], "\(what): the Trash was asked for a file", file: file, line: line)
    }

    /// Nothing holds the window's life and it ends five seconds after the last shot arrived or came back, to the step.
    private func assertTheLifeRuns(_ s: PileScene, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(s.toast.holds.isEmpty, "\(what): something still holds the window's life: \(s.toast.holds)", file: file, line: line)
        XCTAssertFalse(s.toast.advance(by: 4.5), "\(what): the life ended before its five seconds", file: file, line: line)
        XCTAssertTrue(s.toast.advance(by: 0.5), "\(what): the life did not run to its end", file: file, line: line)
    }

    private func pixels(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: Esc

    /// A shot that was only copied has nothing but the thumbnail's picture: an Esc that does not bring the thumbnail
    /// back loses it, and Edit opens on nothing.
    func testEscOnACopiedOnlyShotBringsTheThumbnailBackWithItsHeldPictureAndEditOpensOnItAgain() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let overlay = try await openEditor(s, on: held)

        await escape(s, overlay)

        XCTAssertEqual(s.board.singles, 1, "Esc wrote to the clipboard")
        XCTAssertEqual(s.trash.asked, [], "Esc asked the Trash")
        XCTAssertEqual(names(s.desktop), [], "Esc made a file")
        assertTheCopiedShotIsBack(s)

        guard s.toast.model.editSource != nil else { return }
        s.toast.model.edit()
        await waitUntil("the editor opened again on the shot that came back") { s.editors == 2 }
    }

    func testEscOnASavedShotBringsTheThumbnailBackWithItsFileAndItsReading() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)

        await escape(s, overlay)

        XCTAssertEqual(s.board.singles, before.copies, "Esc wrote to the clipboard")
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
    }

    // MARK: Return with nothing changed

    /// No mark and the area still the whole picture: the file is the same file, nothing is asked of the Trash, the
    /// clipboard takes no write, and the thumbnail comes back with the shot's file and its reading.
    func testReturnWithNoMarkAndTheWholePictureWritesNothingAndGivesTheSavedShotBack() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        let area = try XCTUnwrap(overlay.editedArea)
        try require(area.size == CGSize(width: 400, height: 300), "the area is not the whole 400 x 300 picture: \(area)")

        await finish(s, overlay, .confirm)

        assertTheFileIsTheSameFile(s, before)
        XCTAssertEqual(s.board.singles, before.copies, "the clipboard took a write for an edit that changed nothing")
        assertTheSavedShotIsBack(s, before)
    }

    /// The sibling on a shot that was only copied: nothing to replace and nothing to write, so the clipboard takes no
    /// second write either, and the thumbnail comes back with its held picture.
    func testReturnWithNoMarkAndTheWholePictureOnACopiedOnlyShotWritesNothingAndGivesItBack() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let overlay = try await openEditor(s, on: held)

        await finish(s, overlay, .confirm)

        XCTAssertEqual(names(s.desktop), [], "an edit that changed nothing made a file")
        XCTAssertEqual(s.trash.asked, [], "the Trash was asked for a file")
        XCTAssertEqual(s.board.singles, 1, "the clipboard took a write for an edit that changed nothing")
        assertTheCopiedShotIsBack(s)
    }

    // MARK: ⌘C of a saved shot's edit

    func testCopyOfAMarkedEditPutsItOnTheClipboardAndLeavesTheFileAndTheThumbnailIsTheSavedShots() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, before.copies + 1, "the edit did not go to the clipboard once")
        XCTAssertNotEqual(s.board.pngs.last, before.bytes, "the clipboard took the file's own bytes, not a picture the editor made")
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
    }

    // MARK: What does replace, to stay as it is

    func testReturnWithOneMarkReplacesTheFileAndTheThumbnailCarriesTheNewReading() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")

        await finish(s, overlay, .confirm)

        XCTAssertEqual(s.trash.moved, [before.url], "the original was not the one that went to the Trash")
        XCTAssertEqual(names(s.desktop), before.names, "the edit did not take the original's name")
        let now = FileShotWriter().reading(of: before.url)
        XCTAssertNotNil(now)
        XCTAssertNotEqual(now?.identity, before.reading.identity, "the file under the name is the original")
        XCTAssertNotEqual(try? Data(contentsOf: before.url), before.bytes, "the file under the name has the original's bytes")
        XCTAssertEqual(s.board.singles, before.copies + 1, "Return did not copy the edit")
        XCTAssertEqual(s.toast.model.shots.count, 1)
        XCTAssertEqual(s.toast.model.shots.last?.file, before.url)
        XCTAssertEqual(s.toast.model.shots.last?.reading, now, "the thumbnail does not hold the file as it is now")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced)
        XCTAssertEqual(s.toast.model.editSource?.shot, now.map { WrittenShot(url: before.url, reading: $0) })
    }

    /// No mark, but the area is a part of the picture: that is a change, and the part replaces the file.
    func testReturnWithNoMarkAndTheAreaReshapedInsideThePictureReplacesTheFileWithThatPart() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        let whole = try XCTUnwrap(overlay.editedArea)
        let display = s.display(of: overlay)
        let view = try XCTUnwrap(overlay.view(for: display))
        let corner = view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .topLeft)!]
        overlay.mouseDown(on: display, at: corner, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: corner.x + 40, y: corner.y + 30), flags: [])
        overlay.mouseUp(on: display)
        let part = try XCTUnwrap(overlay.editedArea)
        try require(overlay.editedLayers.isEmpty, "a mark came with the drag")
        try require(part != whole && whole.contains(part) && part.width == whole.width - 40 && part.height == whole.height - 30,
                    "the area was not reshaped inside the picture: \(whole) -> \(part)")

        await finish(s, overlay, .confirm)

        XCTAssertEqual(s.trash.moved, [before.url], "the original was not the one that went to the Trash")
        XCTAssertEqual(names(s.desktop), before.names)
        let size = try XCTUnwrap(pixels(before.url))
        XCTAssertEqual(size.width, part.width, accuracy: 1, "the file is not the part the area took")
        XCTAssertEqual(size.height, part.height, accuracy: 1)
        XCTAssertNotEqual(FileShotWriter().reading(of: before.url)?.identity, before.reading.identity)
        XCTAssertEqual(s.board.singles, before.copies + 1, "Return did not copy the part")
        XCTAssertEqual(s.toast.model.shots.last?.file, before.url)
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced)
    }

    /// A clipboard-only shot has no file to give back, and ⌘C of its edit is a copy of the marked picture as a shot of its
    /// own: the old shot is let go, as it is for every exit that is not one of the three above.
    func testCommandCOfACopiedOnlyShotStaysANewCopiedShotOfTheMarkedPicture() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let overlay = try await openEditor(s, on: held)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, 2, "the edit did not go to the clipboard once")
        XCTAssertNotEqual(s.board.pngs.last, s.board.pngs.first, "the clipboard took the first copy's bytes again, not a picture the editor made")
        XCTAssertEqual(names(s.desktop), [], "⌘C made a file")
        XCTAssertEqual(s.trash.asked, [], "⌘C asked the Trash")
        XCTAssertEqual(s.toast.model.shots.count, 1)
        XCTAssertNotEqual(s.toast.model.shots.last?.id, held.id, "the shot that went into the editor came back instead of the copy of the marked edit")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.copied)
        XCTAssertNil(s.toast.model.shots.last?.file)
        XCTAssertNotNil(s.toast.model.shots.last?.full, "the copy holds no picture")
    }

    // MARK: Where a shot comes back to

    /// The first, the middle and the last of three: the shot that went into the editor is back at the place it stood at,
    /// as the same shot (its identity, file, reading and caption), and Edit is offered on its file.
    func testAShotComesBackToTheFirstMiddleAndLastPlaceOfItsGroupAsTheSameShotOnEsc() async throws {
        for index in 0..<3 {
            let s = try scene()
            let shots = try await three(s)
            let taken = shots[index]
            let overlay = try await openEditor(s, on: taken, staying: shots.filter { $0.id != taken.id }.map(\.id))

            await escape(s, overlay)

            assertTheWindowHolds(s, shots, "place \(index) of 3")
            assertTheFilesAreAsTheyWere(s, shots, "place \(index) of 3")
            XCTAssertEqual(s.board.singles, 3, "place \(index) of 3: Esc wrote to the clipboard")
            let back = try XCTUnwrap(s.toast.model.shot(index), "place \(index) of 3: no shot there")
            XCTAssertEqual(s.toast.model.editSource(of: back)?.shot,
                           WrittenShot(url: try XCTUnwrap(taken.file), reading: try XCTUnwrap(taken.reading)),
                           "place \(index) of 3: Edit is not offered on the shot's file")
        }
    }

    /// Return with no mark and ⌘C of a saved shot with no mark leave the same place for the middle shot as Esc does.
    func testReturnWithNothingChangedAndCommandCWithNoMarkBringTheMiddleShotBackToItsPlaceToo() async throws {
        for (exit, writes) in [(EditorExit.confirm, 0), (EditorExit.copy, 1)] {
            let s = try scene()
            let shots = try await three(s)
            let overlay = try await openEditor(s, on: shots[1], staying: [shots[0].id, shots[2].id])

            await finish(s, overlay, exit)

            assertTheWindowHolds(s, shots, "\(exit)")
            assertTheFilesAreAsTheyWere(s, shots, "\(exit)")
            XCTAssertEqual(s.board.singles, 3 + writes, "\(exit): the clipboard took \(s.board.singles - 3) writes, not \(writes)")
        }
    }

    // MARK: A full group

    /// A group of `ShotShelf.limit` shots when the shot comes back goes through the bound as any new shot does: the list
    /// stays at the limit and its oldest shot leaves. Here the middle of three is in the editor and the limit minus one
    /// shots arrive; the last of them pushes out the first of the three, so when the middle one comes back it is the last of the
    /// three that is the oldest, and that one leaves. The shot stands at index 1, where it stood, in the list that is left.
    func testAGroupThatIsFullWhenTheShotComesBackStaysWithinTheBoundAndLosesItsOldestShot() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (shots[0], shots[1], shots[2])
        let overlay = try await openEditor(s, on: middle, staying: [first.id, last.id])
        var arrived: [ShotToastModel.Shot.ID] = []
        for number in 1..<ShotShelf.limit {
            s.toast.showDone(try ShotToastRig.picture(width: 40, height: 30), caption: "n\(number)", file: nil)
            arrived.append(try XCTUnwrap(s.toast.model.shots.last?.id))
        }
        try require(s.toast.model.shots.count == ShotShelf.limit, "the group is not full: \(s.toast.model.shots.count)")
        try require(s.toast.model.shots.map(\.id) == [last.id] + arrived,
                    "the group is not the last of the three and the arrivals: \(s.toast.model.shots.map(\.id))")
        try require(s.controller.isBusy && s.toast.holds.contains(.editor), "the editor ended while the group filled")

        await escape(s, overlay)

        let now = s.toast.model.shots.map(\.id)
        XCTAssertEqual(now.count, ShotShelf.limit, "the group is past its bound or short of it")
        XCTAssertTrue(now.contains(middle.id), "the shot that went into the editor did not come back")
        XCTAssertFalse(now.contains(last.id), "the oldest shot of the group stayed and another left")
        XCTAssertTrue(arrived.allSatisfy { now.contains($0) }, "a shot that arrived while the editor was open left")
        XCTAssertEqual(now, [arrived[0], middle.id] + arrived.dropFirst(), "the shot is not at index 1 of the list that is left")
        XCTAssertEqual(s.toast.model.shot(1)?.file, middle.file)
        XCTAssertEqual(s.toast.model.shot(1)?.reading, middle.reading)
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: The window's end, and the hold

    func testTheModuleSwitchedOffWhileTheEditorIsOpenLetsTheHeldShotGoAndALaterEndBringsNothingBack() async throws {
        let s = try scene()
        let shots = try await three(s)
        let overlay = try await openEditor(s, on: shots[1], staying: [shots[0].id, shots[2].id])

        s.controller.teardown()

        XCTAssertFalse(s.controller.isBusy)
        XCTAssertTrue(s.toast.model.shots.isEmpty, "the window outlived the module")
        XCTAssertFalse(s.toast.model.shown)
        XCTAssertTrue(s.toast.holds.isEmpty, "the module is off and the window's life is held: \(s.toast.holds)")
        // The editor's late end: from the overlay that was closed, and straight at the toast.
        overlay.perform(.close)
        overlay.perform(.exit(.confirm))
        await grace(0.1)
        s.toast.editorClosed(givingBack: true)
        XCTAssertTrue(s.toast.model.shots.isEmpty, "a late end of the editor brought the shot back to a window that was gone")
        XCTAssertFalse(s.toast.model.shown)
        XCTAssertTrue(s.toast.holds.isEmpty)
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(s.board.singles, 3)
        // The next shot is alone in the window, and its life runs: nothing was left holding it.
        let later = try await s.take(width: 460)
        XCTAssertEqual(s.toast.model.shots.map(\.id), [later.id], "the held shot is still about")
        assertTheLifeRuns(s, "after the module was switched off with the editor open")
    }

    func testTheWindowDismissedWhileTheEditorIsOpenLetsTheHeldShotGoAndEscBringsNothingBack() async throws {
        let s = try scene()
        let shots = try await three(s)
        let overlay = try await openEditor(s, on: shots[1], staying: [shots[0].id, shots[2].id])

        s.toast.dismiss()

        XCTAssertTrue(s.toast.model.shots.isEmpty)
        XCTAssertFalse(s.toast.model.shown)
        XCTAssertTrue(s.toast.holds.isEmpty)
        XCTAssertTrue(s.controller.isBusy, "the control: the editor is still open")
        await escape(s, overlay)
        XCTAssertFalse(s.controller.isBusy)
        XCTAssertTrue(s.toast.model.shots.isEmpty, "the editor's end brought a shot back to a window that was dismissed")
        XCTAssertFalse(s.toast.model.shown)
        XCTAssertTrue(s.toast.holds.isEmpty)
        XCTAssertEqual(s.trash.asked, [])
        let later = try await s.take(width: 460)
        XCTAssertEqual(s.toast.model.shots.map(\.id), [later.id], "the held shot is still about")
        assertTheLifeRuns(s, "after the window was dismissed with the editor open")
    }

    /// While the editor is open the group's life does not run; once the shot is back the editor's hold is gone and the
    /// life runs for its five seconds from there. A second end of the editor brings nothing more.
    func testAfterTheShotIsGivenBackTheEditorsHoldIsGoneAndTheGroupsLifeRunsFromThere() async throws {
        let s = try scene()
        let shots = try await three(s)
        let overlay = try await openEditor(s, on: shots[1], staying: [shots[0].id, shots[2].id])
        XCTAssertFalse(s.toast.advance(by: 1000), "the control: the group's life ran while the editor was open")

        await escape(s, overlay)

        assertTheWindowHolds(s, shots, "after Esc")
        s.toast.editorClosed(givingBack: true)
        assertTheWindowHolds(s, shots, "after a second end of the editor")
        assertTheLifeRuns(s, "after Esc")
    }

    /// The only shot of a window: the editor took it and the window with it, and the shot's coming back makes the window
    /// again, for a life of its own.
    func testAfterTheOnlyShotIsGivenBackTheWindowIsUpAgainAndItsLifeRuns() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        XCTAssertFalse(s.toast.model.shown, "the control: the window stayed up over an editor with nothing in it")

        await escape(s, overlay)

        assertTheSavedShotIsBack(s, before)
        assertTheLifeRuns(s, "after the only shot came back")
    }

    // MARK: ⌘C of a saved shot with no mark

    func testCommandCOfASavedShotWithNoMarkWritesTheClipboardOnceLeavesTheFileAndGivesTheShotBack() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, before.copies + 1, "⌘C did not write the clipboard exactly once")
        XCTAssertEqual(s.board.pngs.last.flatMap { pixels($0) }, CGSize(width: 400, height: 300), "what the clipboard took is not the 400 x 300 picture")
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
        XCTAssertEqual(s.toast.model.shots.last?.caption, before.shot.caption, "the shot came back under another caption")
        XCTAssertNil(s.toast.model.refusal, "⌘C was told as a refusal")
    }

    /// The clipboard refuses the copy: the person is told over the shot that came back, and when the plaque goes the shot
    /// is the window again.
    func testCommandCOfASavedShotRefusedByTheClipboardShowsThePlaqueOverTheShotThatCameBack() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.board.accepts = false

        await finish(s, overlay, .copy)

        guard case .refusal(let title, let body, _)? = s.toast.model.refusal else {
            return XCTFail("no plaque after a refused copy: \(String(describing: s.toast.model.content))")
        }
        XCTAssertEqual(title, ScStr.failedTitle)
        XCTAssertEqual(body, ScStr.refusal(.pasteboard))
        XCTAssertEqual(s.board.singles, before.copies, "the clipboard took a write it was to refuse")
        assertTheFileIsTheSameFile(s, before)
        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id], "the shot is not under the plaque")
        XCTAssertFalse(s.toast.advance(by: 9))
        XCTAssertNil(s.toast.model.refusal, "the plaque stayed")
        assertTheSavedShotIsBack(s, before)
        XCTAssertFalse(s.controller.isBusy)
    }

    // MARK: Edit again on the shot that came back, a file renamed under the open editor, a picture shown reduced

    /// «Edit» on the saved shot that came back opens the editor on that shot's file: a mark and Return replace it.
    func testEditOpensAgainOnTheSavedShotThatCameBackAndItsMarkedEditReplacesTheOriginalsFile() async throws {
        let s = try scene()
        let before = try await saved(s)
        let first = try await openEditor(s, on: before.shot)
        await escape(s, first)
        assertTheSavedShotIsBack(s, before)

        let again = try await openEditor(s, on: try XCTUnwrap(s.toast.model.shots.last), opened: 2)
        s.draw(again)
        try require(again.editedLayers.count == 1, "the mark was not drawn: \(again.editedLayers.count) layers")
        await finish(s, again, .confirm)

        XCTAssertEqual(s.trash.moved, [before.url], "the second edit did not replace the file of the shot that came back")
        XCTAssertEqual(names(s.desktop), before.names)
        XCTAssertNotEqual(FileShotWriter().reading(of: before.url)?.identity, before.reading.identity, "the file under the name is the original")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced)
    }

    /// «Edit» on the copied shot that came back opens the editor on its held picture: a mark and Return copy it as a new
    /// shot, and make no file.
    func testEditOpensAgainOnTheCopiedShotThatCameBackAndItsMarkedEditIsCopiedAsANewShot() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let first = try await openEditor(s, on: held)
        await escape(s, first)
        assertTheCopiedShotIsBack(s)
        let back = try XCTUnwrap(s.toast.model.shots.last)
        XCTAssertEqual(back.id, held.id, "the shot that came back is not the same shot")

        let again = try await openEditor(s, on: back, opened: 2)
        s.draw(again)
        try require(again.editedLayers.count == 1, "the mark was not drawn: \(again.editedLayers.count) layers")
        await finish(s, again, .confirm)

        XCTAssertEqual(s.board.singles, 2, "the second edit did not go to the clipboard once")
        XCTAssertEqual(names(s.desktop), [], "the second edit made a file")
        XCTAssertEqual(s.trash.asked, [])
        assertTheCopiedShotIsBack(s)
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.copied)
    }

    /// The file is moved while the editor is open: Esc still brings the shot back, and its Edit, which asks the file again,
    /// is refused as it is for any shot whose file is not the shot's any more.
    func testAFileRenamedWhileTheEditorWasOpenStillComesBackWithTheShotAndEditThenRefusesIt() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        try FileManager.default.moveItem(at: before.url, to: s.desktop.appendingPathComponent("mine.png"))

        await escape(s, overlay)

        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id], "the shot did not come back")
        XCTAssertEqual(s.trash.asked, [])
        s.press(try XCTUnwrap(s.toast.model.shots.last))
        await waitUntil("the refusal was shown") { s.toast.model.refusal != nil }
        guard case .refusal(_, let body, _)? = s.toast.model.refusal else { return XCTFail("no plaque: \(String(describing: s.toast.model.content))") }
        XCTAssertEqual(body, ScStr.refusal(.notEditable))
        XCTAssertEqual(s.editors, 1, "an editor opened on a file that is not the shot's")
        XCTAssertFalse(s.controller.isBusy)
    }

    /// A picture larger than the screen is shown reduced, so the area is a rectangle with fractions in it: Return with no
    /// mark is still no change, whatever the reduction made of the numbers.
    func testReturnWithNoMarkOnAPictureThatWasReducedToFitTheScreenIsStillNoChange() async throws {
        for (width, height) in [(1200, 700), (1013, 677)] {
            let s = try scene()
            let before = try await saved(s, width: width, height: height)
            let overlay = try await openEditor(s, on: before.shot)
            let area = try XCTUnwrap(overlay.editedArea)
            try require(area.width < CGFloat(width) && area.height < CGFloat(height), "the \(width) x \(height) picture was not reduced: \(area)")

            await finish(s, overlay, .confirm)

            assertTheFileIsTheSameFile(s, before)
            XCTAssertEqual(s.board.singles, before.copies, "\(width) x \(height): the clipboard took a write for an edit that changed nothing")
            assertTheSavedShotIsBack(s, before)
        }
    }

    // MARK: The flash

    /// What the overlay stood at in the turn an exit was pressed, before any timer could run (`open`, `leaving`), and
    /// what it had lit by the time the edit was delivered. `close()` leaves what was lit as it was, so `flashed` holds a
    /// flash that has come and gone too.
    private struct Seen {
        let open: Bool
        let leaving: Bool
        let flashed: [DisplayID: CGRect]
    }

    /// The editor on `shot`, handed the motion setting itself: the default reads this Mac's own Reduce Motion, and with it
    /// on a case that expects nothing to be lit would pass without its subject.
    private func openEditorWithMotion(_ s: PileScene, on shot: ShotToastModel.Shot,
                                      file: StaticString = #filePath, line: UInt = #line) async throws -> CaptureOverlay {
        let overlay = try await openEditor(s, on: shot, file: file, line: line)
        overlay.reducesMotion = { false }
        return overlay
    }

    /// The exit pressed and the overlay read in that same turn, then the edit awaited and the flash read again.
    private func leave(_ s: PileScene, _ overlay: CaptureOverlay, by exit: EditorExit) async -> Seen {
        overlay.perform(.exit(exit))
        let (open, leaving) = (overlay.isOpen, overlay.leaving)
        await waitUntil("the edit was delivered") { !s.controller.isBusy }
        return Seen(open: open, leaving: leaving, flashed: overlay.flashed)
    }

    /// The white that says a shot was taken is not played for an edit that took none: Return with no mark and the area
    /// still the whole picture ends as Esc does, so the overlay closes in the turn of the key and nothing is lit.
    /// Reduce Motion is handed over as off, so that a flash which is not there is not missing for a reason of this
    /// Mac's.
    func testReturnWithNothingMarkedAndTheWholePictureLightsNothingAndTheOverlayClosesAtOnce() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot)
        let area = try XCTUnwrap(overlay.editedArea)
        try require(area.size == CGSize(width: 400, height: 300), "the area is not the whole 400 x 300 picture: \(area)")

        let seen = await leave(s, overlay, by: .confirm)

        XCTAssertTrue(seen.flashed.isEmpty, "a Return that changed nothing lit the area, the white of a shot that was taken: \(seen.flashed)")
        XCTAssertFalse(seen.leaving, "a Return that changed nothing left the overlay waiting for a flash")
        XCTAssertFalse(seen.open, "the overlay was still open in the turn of a Return that changed nothing")
        // The exit really was the one that changes nothing, so that "nothing is lit" is not the line of an edit that went
        // another way.
        assertTheFileIsTheSameFile(s, before)
        XCTAssertEqual(s.board.singles, before.copies, "the clipboard took a write for an edit that changed nothing")
        assertTheSavedShotIsBack(s, before)
    }

    /// ⌘C of a saved shot copies the picture and gives the shot back, and it is a shot that was taken: the area is lit.
    func testCommandCOfASavedShotStillLightsTheArea() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot)
        let area = try XCTUnwrap(overlay.editedArea)
        let display = s.display(of: overlay)

        let seen = await leave(s, overlay, by: .copy)

        XCTAssertEqual(seen.flashed, [display: area], "⌘C of a saved shot did not light the area it copied")
        XCTAssertTrue(seen.leaving, "⌘C of a saved shot did not leave the overlay waiting for the flash")
        XCTAssertTrue(seen.open, "the overlay closed in the turn of ⌘C, before the flash")
        XCTAssertEqual(s.board.singles, before.copies + 1, "the control: ⌘C did not write the clipboard once")
        assertTheSavedShotIsBack(s, before)
    }

    /// Return with one mark replaces the file, and it is a shot that was taken: the area is lit.
    func testReturnWithOneMarkStillLightsTheArea() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        let area = try XCTUnwrap(overlay.editedArea)
        let display = s.display(of: overlay)

        let seen = await leave(s, overlay, by: .confirm)

        XCTAssertEqual(seen.flashed, [display: area], "Return with one mark did not light the area it replaced the file with")
        XCTAssertTrue(seen.leaving, "Return with one mark did not leave the overlay waiting for the flash")
        XCTAssertTrue(seen.open, "the overlay closed in the turn of Return with a mark, before the flash")
        XCTAssertEqual(s.trash.moved, [before.url], "the control: Return with a mark did not replace the file")
    }

    /// The control the case of a Return that changed nothing is measured against: Esc ends the same edit on the same
    /// shot, in the same rig with the same motion setting, and lights nothing.
    func testEscLightsNothing() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot)

        await escape(s, overlay)

        try require(!s.controller.isBusy && s.toast.model.shots.count == 1, "Esc did not end the editor with the shot back in the window")
        XCTAssertTrue(overlay.flashed.isEmpty, "Esc lit the area: \(overlay.flashed)")
        XCTAssertFalse(overlay.leaving, "Esc left the overlay waiting for a flash")
        XCTAssertFalse(overlay.isOpen, "the overlay is open after Esc")
        assertTheSavedShotIsBack(s, before)
    }

    // MARK: The module switched off in the turn of ⌘C

    /// ⌘C of a saved shot gives the shot back at once and copies the picture in a task of its own, a turn later. The module
    /// switched off in the turn of the key cancels that task before it runs: the clipboard takes no write and the window is
    /// empty. The control is the same ⌘C with the module left on, which does write the clipboard once.
    func testCommandCOfASavedShotWithTheModuleSwitchedOffBeforeTheCopyRunsWritesNothingAndLeavesNoWindow() async throws {
        for switchedOff in [false, true] {
            let s = try scene()
            let before = try await saved(s)
            let overlay = try await openEditor(s, on: before.shot)

            overlay.perform(.exit(.copy))
            try require(s.controller.isBusy, "switched off \(switchedOff): the copy is not pending, the controller is free")
            try require(s.board.singles == before.copies, "switched off \(switchedOff): the copy ran in the turn of the key")
            try require(s.toast.model.shots.map(\.id) == [before.shot.id], "switched off \(switchedOff): the shot did not come back in the turn of the key")
            if switchedOff { s.controller.teardown() }
            await waitUntil("the controller was free") { !s.controller.isBusy }
            await grace(0.2)

            if switchedOff {
                XCTAssertEqual(s.board.singles, before.copies, "the copy ran after the module was switched off")
                XCTAssertTrue(s.toast.model.shots.isEmpty, "the window outlived the module")
                XCTAssertFalse(s.toast.model.shown, "the thumbnail is up after the module was switched off")
                XCTAssertTrue(s.toast.holds.isEmpty, "the module is off and the window's life is held: \(s.toast.holds)")
                assertTheFileIsTheSameFile(s, before)
            } else {
                XCTAssertEqual(s.board.singles, before.copies + 1, "the control: ⌘C with the module on did not write the clipboard once")
                assertTheSavedShotIsBack(s, before)
            }
        }
    }
}
