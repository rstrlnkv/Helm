import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **An exit of an editor opened from the thumbnail that changed nothing gives the shot back as it was and writes nothing;
/// ⌘C of a saved shot gives it back too, and says a changed picture on a note.** Each case is on a shot that was really
/// taken. Esc brings the thumbnail back with what it held (a saved shot's file and reading, a copied shot's picture);
/// Return with no mark and the area still the whole picture is no change, so the file stays the same file, the Trash is not
/// asked and the clipboard takes no write; ⌘S and Share the same way of a saved shot leave the file's bytes, inode and
/// modification date as they were, and Share stands the shot as the newest and opens the sheet on the file that is there;
/// ⌘C of a saved shot puts the edit on the clipboard and leaves the file, and the thumbnail that comes back is that shot's,
/// with its file and its reading. The edges beside them are what does not give the shot back: Return, ⌘S and Share with one
/// mark or with the area reshaped inside the picture, which replace the file; ⌘S and Share of a shot that was only copied,
/// which are delivered as a new shot; and ⌘C of a shot that was only copied, which stays a new copied shot. Around them: the
/// place the shot comes back to in a group of three and in a full group, a Share sheet already open, the window or the module
/// going while the editor is open, the editor's hold and the group's life afterwards, «Edit» pressed again on the shot that
/// came back, a file renamed while the editor was open, a picture shown reduced, the flash that ⌘C of a saved shot and Return
/// and ⌘S with one mark play and that an exit that changed nothing does not (the overlay closes at once), ⌘C of a saved shot
/// with the module switched off before the copy runs, which writes nothing to the clipboard and leaves no window, and the
/// note: said for a marked or reshaped picture and not for one that changed nothing nor for the capsule's Copy, never beside
/// a refusal that is up or comes, nor for a copy the clipboard refused, nor after the window went while the editor was open,
/// and gone with the window, a new shot, a removal and «Edit» pressed again, and gone with the pointer's coming over the
/// shot, onto a shot of the row or onto the pile, and not back when it leaves nor said while it is there.
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
/// clipboard that took a second write, a thumbnail with a held picture where a file was, an area lit by an exit that
/// changed nothing, a file whose modification date moved, a sheet handed another file, a note where nothing is to be said
/// or none where it is.
@MainActor
final class AnEditThatLeavesTheShotAsItWasGivesItBackTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        stands = []
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
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "⌘C of the marked edit did not say it was copied")
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
        XCTAssertNil(s.toast.model.note, "the new copied shot says its copy twice: its caption and a note")
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
        XCTAssertNil(s.toast.model.note, "⌘C with no mark said the copy")
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

    // MARK: ⌘S and Share of an edit that changed nothing

    /// The sheets the share asked for: how many, what each was handed, and what the handed file was at the moment the sheet
    /// opened (the file the sheet is shown on is read there, not afterwards).
    private final class Sheets {
        var opened = 0
        var handed: [[URL]] = []
        var readings: [ShotReading?] = []
    }

    private var stands: [StandInThumbnail] = []

    /// The thumbnail's view is on a window, so that a share has somewhere to open, and the system's sheet is replaced by a record.
    private func listen(_ s: PileScene) -> Sheets {
        let sheets = Sheets()
        let stand = StandInThumbnail()
        stands.append(stand)
        s.toast.model.anchor = stand.view
        s.toast.presentPicker = { [unowned s] _, _ in
            MainActor.assumeIsolated {
                sheets.opened += 1
                let urls = (s.toast.shareItems() ?? []).compactMap { $0 as? URL }
                sheets.handed.append(urls)
                sheets.readings.append(urls.first.flatMap { FileShotWriter().reading(of: $0) })
            }
        }
        return sheets
    }

    private func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// An edit of a saved shot opened and left by `exit` with no mark and the area still the whole picture: the file, its
    /// bytes, its inode and its modification date as they were, the Trash not asked, the clipboard not written, the shot
    /// back in the window under its own caption, and the overlay closed in the turn of the key with nothing lit, as it
    /// closes for a Return that changed nothing. Returns the scene, the shot as it was and the sheets the share opened.
    @discardableResult
    private func anUnchangedEdit(leftBy exit: EditorExit, width: Int = 400, height: Int = 300,
                                 file: StaticString = #filePath, line: UInt = #line) async throws -> (PileScene, Saved, Sheets) {
        let s = try scene()
        let before = try await saved(s, width: width, height: height)
        let sheets = listen(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot, file: file, line: line)
        let date = modified(before.url)
        try require(date != nil, "the saved shot's file has no modification date", file: file, line: line)

        let seen = await leave(s, overlay, by: exit)

        assertTheFileIsTheSameFile(s, before, file: file, line: line)
        XCTAssertEqual(modified(before.url), date, "\(exit): the file's modification date moved", file: file, line: line)
        XCTAssertEqual(s.board.singles, before.copies, "\(exit): the clipboard took a write for an edit that changed nothing", file: file, line: line)
        XCTAssertTrue(seen.flashed.isEmpty, "\(exit): an edit that changed nothing lit the area: \(seen.flashed)", file: file, line: line)
        XCTAssertFalse(seen.leaving, "\(exit): the overlay was left waiting for a flash", file: file, line: line)
        XCTAssertFalse(seen.open, "\(exit): the overlay was still open in the turn of the key", file: file, line: line)
        assertTheSavedShotIsBack(s, before, file: file, line: line)
        XCTAssertEqual(s.toast.model.shots.last?.caption, before.shot.caption, "\(exit): the shot came back under another caption", file: file, line: line)
        XCTAssertEqual(s.toast.model.shots.last?.id, before.shot.id, "\(exit): the shot that came back is not the same shot", file: file, line: line)
        XCTAssertFalse(s.controller.isBusy, file: file, line: line)
        return (s, before, sheets)
    }

    func testSaveWithNothingChangedLeavesTheFileAsItWasAndGivesTheShotBack() async throws {
        let (_, _, sheets) = try await anUnchangedEdit(leftBy: .save)
        XCTAssertEqual(sheets.opened, 0, "⌘S opened the share sheet")
    }

    /// The picture shown reduced has an area with fractions in it, which is no change all the same.
    func testSaveWithNothingChangedOnAPictureReducedToFitTheScreenLeavesTheFileAsItWas() async throws {
        try await anUnchangedEdit(leftBy: .save, width: 1200, height: 700)
    }

    /// Share hands the sheet the file that exists, as it was when the sheet opened.
    func testShareWithNothingChangedWritesNothingAndOpensTheSheetOnTheExistingFile() async throws {
        let (s, before, sheets) = try await anUnchangedEdit(leftBy: .share)
        XCTAssertEqual(sheets.opened, 1, "the share did not open the sheet once")
        XCTAssertEqual(sheets.handed, [[before.url]], "the sheet was not handed the shot's file")
        XCTAssertEqual(sheets.readings.compactMap { $0 }, [before.reading], "the file the sheet was opened on was not the file the shot wrote")
        XCTAssertEqual(s.toast.model.shots.last?.file, before.url)
    }

    func testShareWithNothingChangedOnAPictureReducedToFitTheScreenOpensTheSheetOnTheExistingFile() async throws {
        let (_, before, sheets) = try await anUnchangedEdit(leftBy: .share, width: 1200, height: 700)
        XCTAssertEqual(sheets.handed, [[before.url]], "the sheet was not handed the shot's file")
        XCTAssertEqual(sheets.readings.compactMap { $0 }, [before.reading], "the file the sheet was opened on was not the file the shot wrote")
    }

    // MARK: ⌘S and Share with one mark still write

    func testSaveWithOneMarkReplacesTheFileCopiesNothingAndLightsTheArea() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditorWithMotion(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        let area = try XCTUnwrap(overlay.editedArea)

        let seen = await leave(s, overlay, by: .save)

        XCTAssertEqual(s.trash.moved, [before.url], "the control: ⌘S with a mark did not replace the file")
        XCTAssertNotEqual(FileShotWriter().reading(of: before.url)?.identity, before.reading.identity, "the control: the file under the name is the original")
        XCTAssertNotEqual(try? Data(contentsOf: before.url), before.bytes, "the control: the file under the name has the original's bytes")
        XCTAssertEqual(names(s.desktop), before.names)
        XCTAssertEqual(s.board.singles, before.copies, "⌘S copied")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced)
        XCTAssertEqual(seen.flashed, [s.display(of: overlay): area], "⌘S with a mark did not light the area it replaced the file with")
    }

    func testShareWithOneMarkReplacesTheFileAndOpensTheSheetOnTheNewOne() async throws {
        let s = try scene()
        let before = try await saved(s)
        let sheets = listen(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")

        await finish(s, overlay, .share)

        XCTAssertEqual(s.trash.moved, [before.url], "the control: Share with a mark did not replace the file")
        XCTAssertEqual(sheets.opened, 1, "the control: the share did not open the sheet once")
        XCTAssertEqual(sheets.handed, [[before.url]])
        XCTAssertNotEqual(sheets.readings.compactMap { $0 }.first?.identity, before.reading.identity, "the sheet was opened on the original")
        XCTAssertEqual(s.board.singles, before.copies + 1, "Share copies the edit as Return does")
    }

    // MARK: A shot with no file, ⌘S with nothing changed

    /// A shot that was only copied has no file to leave as it was, and ⌘S asks for one: it is saved as a new shot, the picture
    /// is not copied again, and the shot that went into the editor is let go. This is what ⌘S does with such a shot, pinned as
    /// it is.
    func testSaveWithNothingChangedOnAShotWithNoFileSavesItAsANewShot() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let overlay = try await openEditor(s, on: held)

        await finish(s, overlay, .save)

        XCTAssertEqual(names(s.desktop).count, 1, "⌘S made \(names(s.desktop).count) files, not one: \(names(s.desktop))")
        XCTAssertEqual(s.board.singles, 1, "⌘S copied")
        XCTAssertEqual(s.trash.asked, [], "the Trash was asked for a file")
        XCTAssertEqual(s.toast.model.shots.count, 1)
        XCTAssertNotEqual(s.toast.model.shots.last?.id, held.id, "the shot that went into the editor came back")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.saved)
        XCTAssertNotNil(s.toast.model.shots.last?.file, "the new shot has no file")
        XCTAssertNil(s.toast.model.shots.last?.full)
        XCTAssertNil(s.toast.model.refusal)
    }

    /// The share of such a shot, under the clipboard target, writes no file: it copies the picture again as a new shot that has
    /// no file, and opens the sheet on that picture. Pinned as it is.
    func testShareWithNothingChangedOnAShotWithNoFileCopiesItAgainAsANewShotAndOpensTheSheetOnThePicture() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        let sheets = listen(s)
        let overlay = try await openEditor(s, on: held)

        await finish(s, overlay, .share)

        XCTAssertEqual(names(s.desktop), [], "the share made a file under the clipboard target")
        XCTAssertEqual(sheets.opened, 1, "the share did not open the sheet once")
        XCTAssertEqual(sheets.handed, [[]], "the sheet was handed a file, not the picture")
        XCTAssertEqual(s.board.singles, 2, "Share copies the picture as Return does")
        XCTAssertEqual(s.toast.model.shots.count, 1)
        XCTAssertNotEqual(s.toast.model.shots.last?.id, held.id, "the shot that went into the editor came back")
        XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.copied)
        XCTAssertNil(s.toast.model.shots.last?.file)
        XCTAssertNotNil(s.toast.model.shots.last?.full)
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: ⌘C of a marked picture is said

    /// What the after-shot window draws, read off a render of its own view: the pixels of the shot's picture (the flat colour
    /// the rig paints it in) and every other opaque pixel that is not the white frame the shot stands in, which is type and
    /// the glyphs of a control. A plaque that says something adds the second and leaves the first; one laid over the shot
    /// takes from the first.
    private struct Drawn {
        let picture: Int
        let ink: Int
    }

    private func drawn(_ s: PileScene, file: StaticString = #filePath, line: UInt = #line) throws -> Drawn {
        let mount = MountedRender(ShotToastView(model: s.toast.model), width: 640, height: 640, appearance: .aqua)
        mount.settle(20)
        let view = mount.host
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds), file: file, line: line)
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.bitmapData, file: file, line: line)
        try require(rep.samplesPerPixel == 4 && rep.bitsPerSample == 8, "the render is not 8-bit RGBA", file: file, line: line)
        var (picture, ink) = (0, 0)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let i = y * rep.bytesPerRow + x * 4
                guard data[i + 3] >= 128 else { continue }
                // The rig paints a picture (0.2, 0.5, 0.9).
                if abs(Int(data[i]) - 51) <= 40, abs(Int(data[i + 1]) - 128) <= 40, abs(Int(data[i + 2]) - 230) <= 40 {
                    picture += 1
                } else if min(data[i], data[i + 1], data[i + 2]) < 235 {
                    // Not the white frame the shot stands in: type, a glyph, a control.
                    ink += 1
                }
            }
        }
        return Drawn(picture: picture, ink: ink)
    }

    /// The window as it stands with the saved shot alone in it: the baseline every row below is read against.
    private func shotAlone(_ s: PileScene, file: StaticString = #filePath, line: UInt = #line) throws -> Drawn {
        let alone = try drawn(s, file: file, line: line)
        try require(alone.picture > 1000, "the window does not draw the shot's picture: \(alone)", file: file, line: line)
        return alone
    }

    /// The reading sees a plaque when one is up: a refusal drawn over the shot adds opaque pixels that are not the picture's.
    func testTheDrawnReadingSeesAPlaqueThatSaysSomething() async throws {
        let s = try scene()
        _ = try await saved(s)
        let alone = try shotAlone(s)

        s.toast.showRefusal(.pasteboard)

        let plaque = try drawn(s)
        XCTAssertGreaterThan(plaque.ink, alone.ink + 60, "the control: a refusal plaque added nothing the reading can see: \(alone) -> \(plaque)")
    }

    /// ⌘C of a picture with a mark leaves the clipboard the only place the marked picture lives: the person is told on a
    /// note, and the shot that came back is still in sight, undisturbed, beside or under it. The words are read off the
    /// model (`note`); on the render, which is not text, the note is read as ink that was not there and a picture that still is.
    func testCommandCOfAMarkedEditOfASavedShotIsSaidOnAPlaqueAndTheShotStaysInSight() async throws {
        let s = try scene()
        let before = try await saved(s)
        let alone = try shotAlone(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")

        await finish(s, overlay, .copy)

        try require(s.board.singles == before.copies + 1, "the marked picture did not reach the clipboard once: \(s.board.singles)")
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "⌘C of a marked picture did not say it was copied")
        XCTAssertNil(s.toast.model.refusal)
        let now = try drawn(s)
        XCTAssertGreaterThan(now.ink, alone.ink + 60, "nothing was drawn for the copy: the window is as it was, \(alone) -> \(now)")
        XCTAssertGreaterThanOrEqual(now.picture * 100, alone.picture * 95, "the shot is hidden by what said the copy: \(alone) -> \(now)")
    }

    /// The control that must stay as it is: ⌘C with nothing changed copies the picture and says nothing, and the window is
    /// the shot alone.
    func testCommandCWithNothingChangedCopiesAndDrawsNothingBeyondTheShot() async throws {
        let s = try scene()
        let before = try await saved(s)
        let alone = try shotAlone(s)
        let overlay = try await openEditor(s, on: before.shot)

        await finish(s, overlay, .copy)

        try require(s.board.singles == before.copies + 1, "⌘C did not write the clipboard once: \(s.board.singles)")
        assertTheSavedShotIsBack(s, before)
        XCTAssertNil(s.toast.model.refusal)
        XCTAssertNil(s.toast.model.note, "⌘C with nothing changed said the copy: the file holds that picture")
        let now = try drawn(s)
        XCTAssertLessThanOrEqual(abs(now.ink - alone.ink), 60, "⌘C with nothing changed drew something: \(alone) -> \(now)")
        XCTAssertGreaterThanOrEqual(now.picture * 100, alone.picture * 95, "the shot is not drawn as it was: \(alone) -> \(now)")
    }

    // MARK: The copied plaque and a plaque that is up

    private func plaque(_ s: PileScene) -> (title: String, body: String)? {
        guard case .refusal(let title, let body, _)? = s.toast.model.refusal else { return nil }
        return (title, body)
    }

    /// A refusal is up when the marked picture is copied: it is the plaque still, with the shot under it, and the copy is on the
    /// clipboard. What this guards is a note that comes up beside the refusal, or once it has gone, for a copy made while it was up.
    func testARefusalThatIsUpIsNotReplacedByTheCopiedPlaque() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        s.toast.showRefusal(.captureFailed)
        let up = try XCTUnwrap(plaque(s), "the refusal did not go up")

        await finish(s, overlay, .copy)

        try require(s.board.singles == before.copies + 1, "the marked picture did not reach the clipboard once: \(s.board.singles)")
        let now = plaque(s)
        XCTAssertEqual(now?.title, up.title, "the refusal's title was replaced")
        XCTAssertEqual(now?.body, up.body, "the refusal's sentence was replaced")
        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id], "the shot is not under the plaque")
        XCTAssertNil(s.toast.model.note, "a note came up beside a refusal that was already up")
        assertTheFileIsTheSameFile(s, before)

        XCTAssertFalse(s.toast.advance(by: 9))
        XCTAssertNil(s.toast.model.refusal, "the plaque stayed")
        XCTAssertNil(s.toast.model.note, "the note that was held back while the refusal was up came when it went")
        assertTheSavedShotIsBack(s, before)
    }

    /// The clipboard refuses the marked picture: the refusal is the plaque, nothing else is said, and when it has gone the
    /// window is the shot alone, with no copied plaque for a copy that did not happen.
    func testACopyOfAMarkedPictureThatTheClipboardRefusesIsTheRefusalAndNeverTheCopiedPlaque() async throws {
        let s = try scene()
        let before = try await saved(s)
        let alone = try shotAlone(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        s.board.accepts = false

        await finish(s, overlay, .copy)

        let up = try XCTUnwrap(plaque(s), "no plaque after a refused copy: \(String(describing: s.toast.model.content))")
        XCTAssertEqual(up.title, ScStr.failedTitle)
        XCTAssertEqual(up.body, ScStr.refusal(.pasteboard))
        XCTAssertEqual(s.board.singles, before.copies, "the clipboard took a write it was to refuse")
        XCTAssertNil(s.toast.model.note, "a copy that did not happen was said on a note beside its refusal")
        assertTheFileIsTheSameFile(s, before)

        XCTAssertFalse(s.toast.advance(by: 9))
        XCTAssertNil(s.toast.model.refusal, "the plaque stayed")
        XCTAssertNil(s.toast.model.note, "a copy that did not happen was said once the refusal had gone")
        assertTheSavedShotIsBack(s, before)
        let now = try drawn(s)
        XCTAssertLessThanOrEqual(abs(now.ink - alone.ink), 60, "a copy that did not happen was said once the refusal had gone: \(alone) -> \(now)")
        XCTAssertGreaterThanOrEqual(now.picture * 100, alone.picture * 95)
    }

    // MARK: The note: when it comes, and when it goes

    /// A mark drawn on the shot's editor and ⌘C pressed: the copy of a picture that no file holds.
    private func markedCopy(_ s: PileScene, of shot: ShotToastModel.Shot, opened count: Int = 1,
                            staying others: [ShotToastModel.Shot.ID] = [],
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let overlay = try await openEditor(s, on: shot, opened: count, staying: others, file: file, line: line)
        // The editor remembers the tool of the one before it (`EditorMemory`), and the rig's `draw` presses the rectangle's
        // key, which puts a tool that is already chosen down: from the second editor on, one press first.
        if count > 1 { overlay.perform(.tool(.rectangle)) }
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers", file: file, line: line)
        await finish(s, overlay, .copy)
    }

    /// The area's top-left corner dragged in by 40 x 30, no mark: the part of the picture the area now takes.
    private func reshape(_ s: PileScene, _ overlay: CaptureOverlay, file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        let whole = try XCTUnwrap(overlay.editedArea, file: file, line: line)
        let display = s.display(of: overlay)
        let view = try XCTUnwrap(overlay.view(for: display), file: file, line: line)
        let corner = view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .topLeft)!]
        overlay.mouseDown(on: display, at: corner, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: corner.x + 40, y: corner.y + 30), flags: [])
        overlay.mouseUp(on: display)
        let part = try XCTUnwrap(overlay.editedArea, file: file, line: line)
        try require(overlay.editedLayers.isEmpty && part != whole && whole.contains(part),
                    "the area was not reshaped inside the picture, or a mark came with the drag: \(whole) -> \(part)", file: file, line: line)
        return part
    }

    /// A refusal that arrives while the note is up takes it, and the note is not back when the plaque goes: the sentence was
    /// about a moment that has passed. The next marked copy says it again.
    func testARefusalThatArrivesWhileTheNoteIsUpTakesItAndItIsNotBackWhenThePlaqueGoes() async throws {
        let s = try scene()
        let before = try await saved(s)
        let alone = try shotAlone(s)
        try await markedCopy(s, of: before.shot)
        try require(s.toast.model.note == ScStr.copied, "the note was not up: \(String(describing: s.toast.model.note))")

        s.toast.showRefusal(.pasteboard)

        let up = try XCTUnwrap(plaque(s), "the refusal did not go up")
        XCTAssertEqual(up.body, ScStr.refusal(.pasteboard))
        XCTAssertNil(s.toast.model.note, "the note stayed up beside the refusal that came")
        XCTAssertFalse(s.toast.advance(by: 9))
        XCTAssertNil(s.toast.model.refusal, "the plaque stayed")
        XCTAssertNil(s.toast.model.note, "the note came back when the refusal went")
        assertTheSavedShotIsBack(s, before)
        let now = try drawn(s)
        XCTAssertLessThanOrEqual(abs(now.ink - alone.ink), 60, "something is drawn beside the shot after the refusal went: \(alone) -> \(now)")

        // And not for good: the next copy of a marked picture is said again, twice in a row as well.
        try await markedCopy(s, of: try XCTUnwrap(s.toast.model.shots.last), opened: 2)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the second marked copy was not said")
        XCTAssertEqual(s.board.singles, before.copies + 2)
        try await markedCopy(s, of: try XCTUnwrap(s.toast.model.shots.last), opened: 3)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the third marked copy, with the note up before it, was not said")
        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id])
        assertTheFileIsTheSameFile(s, before)
    }

    /// The note has the window's life (`ShotToast.life`), counted again from the copy, and goes with the window when it is
    /// dismissed; a shot that comes after it is not under it.
    func testTheNoteLivesAsLongAsTheWindowAndGoesWithIt() async throws {
        let s = try scene()
        let before = try await saved(s)
        try await markedCopy(s, of: before.shot)
        try require(s.toast.model.note == ScStr.copied, "the note was not up")

        assertTheLifeRuns(s, "after the marked copy")
        s.toast.dismiss()

        XCTAssertNil(s.toast.model.note, "the note outlived the window")
        XCTAssertTrue(s.toast.model.shots.isEmpty)
        let later = try await s.take(width: 460)
        XCTAssertEqual(s.toast.model.shots.map(\.id), [later.id])
        XCTAssertNil(s.toast.model.note, "the note was said again over a shot it is not about")
    }

    func testANewShotTakesTheNote() async throws {
        let s = try scene()
        let before = try await saved(s)
        try await markedCopy(s, of: before.shot)
        try require(s.toast.model.note == ScStr.copied, "the note was not up")

        let next = try await s.take(width: 500)

        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id, next.id])
        XCTAssertNil(s.toast.model.note, "the note stayed over a pile with a shot it is not about")
    }

    /// Edit pressed on the shot the note is about takes the note, and Esc does not bring it back.
    func testEditPressedAgainTakesTheNoteAndEscDoesNotBringItBack() async throws {
        let s = try scene()
        let before = try await saved(s)
        try await markedCopy(s, of: before.shot)
        try require(s.toast.model.note == ScStr.copied, "the note was not up")

        let again = try await openEditor(s, on: try XCTUnwrap(s.toast.model.shots.last), opened: 2)
        XCTAssertNil(s.toast.model.note, "the note stayed while the shot it is about was in the editor")
        await escape(s, again)

        XCTAssertNil(s.toast.model.note, "Esc brought the note back")
        assertTheSavedShotIsBack(s, before)
    }

    /// In a group the copy is said and the shot is back at its place; a shot of the group removed takes the note.
    func testTheNoteInAGroupIsSaidWithTheShotBackAtItsPlaceAndARemovalTakesIt() async throws {
        let s = try scene()
        let shots = try await three(s)

        try await markedCopy(s, of: shots[1], staying: [shots[0].id, shots[2].id])

        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the marked copy in a group was not said")
        assertTheWindowHolds(s, shots, "marked ⌘C in a group")
        assertTheFilesAreAsTheyWere(s, shots, "marked ⌘C in a group")
        s.toast.remove(shots[0].id)
        XCTAssertEqual(s.toast.model.shots.map(\.id), [shots[1].id, shots[2].id])
        XCTAssertNil(s.toast.model.note, "a shot was removed and the note stayed")
    }

    /// The pointer's coming over the shot takes the note, and its leaving does not bring it back: the capsule wins, and
    /// is what is left. The next marked copy is said again.
    func testThePointerComingOverTheShotTakesTheNoteAndItsLeavingDoesNotBringItBack() async throws {
        let s = try scene()
        let before = try await saved(s)
        try await markedCopy(s, of: before.shot)
        try require(s.toast.model.note == ScStr.copied, "the note was not up: \(String(describing: s.toast.model.note))")

        s.toast.model.pointer(over: true)

        XCTAssertNil(s.toast.model.note, "the note stayed up while the pointer came over the shot")
        XCTAssertEqual(s.toast.model.shots.map(\.id), [before.shot.id], "the pointer took the shot with the note")
        s.toast.model.pointer(over: false)
        XCTAssertNil(s.toast.model.note, "the note came back when the pointer left")

        try await markedCopy(s, of: try XCTUnwrap(s.toast.model.shots.last), opened: 2)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the marked copy after the pointer had left was not said")
        assertTheFileIsTheSameFile(s, before)
    }

    /// A note asked for while the pointer is over the shot is not said, and is not kept for the pointer's leaving; asked for
    /// again with the pointer away, it is said.
    func testANoteAskedForWhileThePointerIsOverTheShotIsNotSaidNorKept() async throws {
        let s = try scene()
        _ = try await saved(s)
        s.toast.model.pointer(over: true)

        s.toast.showNote(ScStr.copied)

        XCTAssertNil(s.toast.model.note, "a note was said under the capsule")
        s.toast.model.pointer(over: false)
        XCTAssertNil(s.toast.model.note, "the note that was asked for under the capsule came when the pointer left")
        s.toast.showNote(ScStr.copied)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the control: a note asked for with the pointer away was not said")
    }

    /// In the row the capsule is the focused shot's: the pointer's coming onto a shot of the row takes the note, nothing is
    /// said while a shot has the pointer, and the leaving brings nothing back.
    func testTheRowsFocusTakesTheNoteAndNoNoteIsSaidWhileAShotHasThePointer() async throws {
        let s = try scene()
        let shots = try await three(s)
        s.toast.showNote(ScStr.copied)
        try require(s.toast.model.note == ScStr.copied, "the note was not up over the row: \(String(describing: s.toast.model.note))")

        s.toast.model.pointer(over: true, shot: shots[1].id, view: nil)

        try require(s.toast.model.focus == shots[1].id, "the row did not take the pointer: \(String(describing: s.toast.model.focus))")
        XCTAssertNil(s.toast.model.note, "the note stayed up while the pointer was on a shot of the row")
        s.toast.model.pointer(over: false, shot: shots[1].id, view: nil)
        try require(s.toast.model.focus == nil, "the row kept the focus after the pointer left")
        XCTAssertNil(s.toast.model.note, "the note came back when the pointer left the shot of the row")

        s.toast.model.pointer(over: true, shot: shots[2].id, view: nil)
        s.toast.showNote(ScStr.copied)
        XCTAssertNil(s.toast.model.note, "a note was said while a shot of the row had the pointer")
        s.toast.model.pointer(over: false, shot: shots[2].id, view: nil)
        XCTAssertNil(s.toast.model.note, "the note that was asked for under the row's capsule came when the pointer left")
    }

    /// On a folded pile the capsule is the newest shot's and the pointer is the pile's: it takes the note as well.
    func testThePointerOnAFoldedPileTakesTheNote() async throws {
        let s = try scene()
        _ = try await s.take(width: 400)
        let newest = try await s.take(width: 420)
        try require(s.toast.model.isPile, "two shots are not a folded pile")
        s.toast.showNote(ScStr.copied)
        try require(s.toast.model.note == ScStr.copied, "the note was not up over the pile: \(String(describing: s.toast.model.note))")

        s.toast.model.pointer(over: true, shot: newest.id, view: nil)

        XCTAssertNil(s.toast.model.note, "the note stayed up while the pointer was on the pile")
        s.toast.model.pointer(over: false, shot: newest.id, view: nil)
        XCTAssertNil(s.toast.model.note, "the note came back when the pointer left the pile")
    }

    /// A note that is asked for under the pointer and is not said leaves the window's life as it was: the seconds that
    /// are left are the same seconds, and what holds them is what held them. The control is the same call with the pointer
    /// away, which says the note and starts the life over; without it the seconds read before and after could be equal
    /// because nothing ever moved them.
    func testANoteRefusedUnderThePointerLeavesTheWindowsLifeAsItWas() async throws {
        let s = try scene()
        _ = try await saved(s)
        try require(s.toast.holds.isEmpty, "something held the life before the clock was run: \(s.toast.holds)")
        XCTAssertFalse(s.toast.advance(by: 3), "the life ended before its five seconds")
        let left = s.toast.remaining
        try require(left > 0 && left < 4, "the clock did not run: \(left) seconds left")
        s.toast.model.pointer(over: true)
        try require(s.toast.holds == [.pointer] && s.toast.model.hovering, "the pointer did not hold the window: \(s.toast.holds)")

        s.toast.showNote(ScStr.copied)

        XCTAssertNil(s.toast.model.note, "a note was said under the capsule")
        XCTAssertEqual(s.toast.remaining, left, "the refused note started the window's life over")
        XCTAssertEqual(s.toast.holds, [.pointer], "the refused note changed what holds the window")
        XCTAssertTrue(s.toast.model.hovering, "the refused note let go of the pointer")
        s.toast.model.pointer(over: false)
        XCTAssertEqual(s.toast.remaining, left, "the pointer's leaving moved the seconds that were left")

        s.toast.showNote(ScStr.copied)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the control: a note asked for with the pointer away was not said")
        XCTAssertGreaterThan(s.toast.remaining, left, "the control: a note that was said did not start the life over")
    }

    /// The same in the row, opened after some of the life was spent: a note asked for while a shot of the row has the pointer
    /// says nothing and leaves the seconds that were left, what holds the window and the shot that has the focus as they were;
    /// asked for with the pointer away, the note is said and the life starts over.
    func testANoteRefusedUnderTheRowsFocusLeavesTheWindowsLifeAsItWas() async throws {
        let s = try scene()
        let shots = [try await s.take(width: 400), try await s.take(width: 420)]
        try require(s.toast.model.isPile, "two shots are not a folded pile")
        try require(s.toast.holds.isEmpty, "something held the life before the clock was run: \(s.toast.holds)")
        XCTAssertFalse(s.toast.advance(by: 3), "the life ended before its five seconds")
        let left = s.toast.remaining
        try require(left > 0 && left < 4, "the clock did not run: \(left) seconds left")
        s.toast.unfold()
        try require(s.toast.model.unfolded, "the row is not open")
        s.toast.model.pointer(over: true, shot: shots[0].id, view: nil)
        try require(s.toast.model.focus == shots[0].id, "the row did not take the pointer: \(String(describing: s.toast.model.focus))")
        let held = s.toast.holds

        s.toast.showNote(ScStr.copied)

        XCTAssertNil(s.toast.model.note, "a note was said while a shot of the row had the pointer")
        XCTAssertEqual(s.toast.remaining, left, "the refused note started the window's life over")
        XCTAssertEqual(s.toast.holds, held, "the refused note changed what holds the window")
        XCTAssertEqual(s.toast.model.focus, shots[0].id, "the refused note took the focus from the shot")
        s.toast.model.pointer(over: false, shot: shots[0].id, view: nil)

        s.toast.showNote(ScStr.copied)
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "the control: a note asked for with the pointer away was not said")
        XCTAssertGreaterThan(s.toast.remaining, left, "the control: a note that was said did not start the life over")
    }

    /// The window was dismissed while the editor was open: the copy happens, and there is no window to say it in. The note
    /// does not make one (the area's flash is all that shows).
    func testAMarkedCopyAfterTheWindowWasDismissedWritesTheClipboardAndMakesNoWindow() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn")
        s.toast.dismiss()

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, before.copies + 1, "the marked picture did not reach the clipboard")
        XCTAssertNil(s.toast.model.note)
        XCTAssertTrue(s.toast.model.shots.isEmpty, "the copy brought a window back")
        XCTAssertFalse(s.toast.model.shown)
        XCTAssertTrue(s.toast.holds.isEmpty)
        assertTheFileIsTheSameFile(s, before)
    }

    /// The capsule's Copy is the file's picture, which is on the disk: it says nothing.
    func testTheCapsulesCopySaysNothing() async throws {
        let s = try scene()
        let before = try await saved(s)

        s.toast.model.copy()
        await waitUntil("the capsule's Copy reached the board") { s.board.singles == before.copies + 1 }
        await grace(0.2)

        XCTAssertEqual(s.board.singles, before.copies + 1)
        XCTAssertNil(s.toast.model.note, "the capsule's Copy said it was copied")
        XCTAssertNil(s.toast.model.refusal)
        assertTheSavedShotIsBack(s, before)
    }

    /// Copy of a picture whose area was reshaped, with no mark, is another picture than the file's: it is said.
    func testCommandCOfAnAreaReshapedInsideThePictureIsSaid() async throws {
        let s = try scene()
        let before = try await saved(s)
        let overlay = try await openEditor(s, on: before.shot)
        let part = try reshape(s, overlay)

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, before.copies + 1)
        let size = try XCTUnwrap(s.board.pngs.last.flatMap { pixels($0) })
        XCTAssertEqual(size.width, part.width, accuracy: 1, "the clipboard took another picture than the part")
        XCTAssertEqual(s.toast.model.note, ScStr.copied, "a copy of a reshaped area was not said")
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
    }

    /// The picture shown reduced has an area with fractions in it; ⌘C of it with nothing changed is the file's picture.
    func testCommandCOfAPictureReducedToFitTheScreenWithNothingChangedSaysNothing() async throws {
        let s = try scene()
        let before = try await saved(s, width: 1200, height: 700)
        let overlay = try await openEditor(s, on: before.shot)

        await finish(s, overlay, .copy)

        XCTAssertEqual(s.board.singles, before.copies + 1)
        XCTAssertNil(s.toast.model.note, "⌘C of a reduced picture with nothing changed was taken for a change")
        assertTheSavedShotIsBack(s, before)
    }

    // MARK: ⌘S and Share with the area reshaped, no mark

    /// The one predicate has the area in it, not only the layers: ⌘S and Share of a reshaped area replace the file with the part.
    func testSaveAndShareWithTheAreaReshapedAndNoMarkStillReplaceTheFile() async throws {
        for exit in [EditorExit.save, EditorExit.share] {
            let s = try scene()
            let before = try await saved(s)
            let sheets = listen(s)
            let overlay = try await openEditor(s, on: before.shot)
            let part = try reshape(s, overlay)

            await finish(s, overlay, exit)

            XCTAssertEqual(s.trash.moved, [before.url], "\(exit): the original did not go to the Trash")
            XCTAssertNotEqual(FileShotWriter().reading(of: before.url)?.identity, before.reading.identity, "\(exit): the file was not replaced")
            XCTAssertEqual(try XCTUnwrap(pixels(before.url)).width, part.width, accuracy: 1, "\(exit): the file is not the part the area took")
            XCTAssertEqual(sheets.opened, exit == .share ? 1 : 0, "\(exit): sheets opened")
            XCTAssertEqual(s.toast.model.shots.last?.caption, ScStr.replaced, "\(exit)")
        }
    }

    // MARK: Share with nothing changed, in a group and with a sheet already open

    /// In a group, Share of an edit that changed nothing stands the shot as the newest of the group (a Share of a changed edit
    /// does the same, as a new shot), and the sheet opens on the file that is there. Pinned as it is.
    func testShareWithNothingChangedInAGroupStandsTheShotAsTheNewestAndOpensTheSheetOnItsFile() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (shots[0], shots[1], shots[2])
        let sheets = listen(s)
        let overlay = try await openEditor(s, on: middle, staying: [first.id, last.id])

        await finish(s, overlay, .share)

        XCTAssertEqual(sheets.opened, 1, "the share did not open the sheet once")
        XCTAssertEqual(sheets.handed, [[try XCTUnwrap(middle.file)]], "the sheet was not handed the middle shot's file")
        XCTAssertEqual(sheets.readings.compactMap { $0 }, [try XCTUnwrap(middle.reading)], "the sheet was opened on a file that is not the one the shot wrote")
        XCTAssertEqual(s.toast.model.shots.map(\.id), [first.id, last.id, middle.id], "the shot is not the newest of the group")
        XCTAssertEqual(s.toast.model.shots.last?.file, middle.file)
        XCTAssertEqual(s.toast.model.shots.last?.reading, middle.reading)
        XCTAssertEqual(s.toast.model.shots.last?.caption, middle.caption)
        assertTheFilesAreAsTheyWere(s, shots, "Share in a group")
        XCTAssertEqual(s.board.singles, 3, "Share of an edit that changed nothing wrote the clipboard")
        XCTAssertNil(s.toast.model.note)
        XCTAssertTrue(s.toast.holds.contains(.sheet) && !s.toast.holds.contains(.editor), "the holds after the share: \(s.toast.holds)")
    }

    /// A full group: the shot that comes back as the newest pushes the oldest out, as any new shot does.
    func testShareWithNothingChangedInAFullGroupPushesTheOldestOutAndOpensTheSheetOnTheShot() async throws {
        let s = try scene()
        let shots = try await three(s)
        let (first, middle, last) = (shots[0], shots[1], shots[2])
        let sheets = listen(s)
        let overlay = try await openEditor(s, on: middle, staying: [first.id, last.id])
        var arrived: [ShotToastModel.Shot.ID] = []
        for number in 1..<ShotShelf.limit {
            s.toast.showDone(try ShotToastRig.picture(width: 40, height: 30), caption: "n\(number)", file: nil)
            arrived.append(try XCTUnwrap(s.toast.model.shots.last?.id))
        }
        try require(s.toast.model.shots.map(\.id) == [last.id] + arrived, "the group is not full as the editor left it")

        await finish(s, overlay, .share)

        XCTAssertEqual(s.toast.model.shots.map(\.id), arrived + [middle.id], "the group is past its bound, or the shot is not the newest")
        XCTAssertEqual(sheets.opened, 1)
        XCTAssertEqual(sheets.handed, [[try XCTUnwrap(middle.file)]], "the sheet was not handed the shot's file")
        XCTAssertEqual(sheets.readings.compactMap { $0 }, [try XCTUnwrap(middle.reading)])
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(s.board.singles, 3)
    }

    /// Two shots, the sheet open on the newest, Edit on the older one: the sheet stays open under the editor.
    private func aSheetOpenOnTheNewestAndTheEditorOnTheOlder(_ s: PileScene) async throws
        -> (older: ShotToastModel.Shot, newest: ShotToastModel.Shot, sheets: Sheets, overlay: CaptureOverlay) {
        let older = try await s.take(width: 400), newest = try await s.take(width: 420)
        let sheets = listen(s)
        s.toast.requestShare()
        try require(sheets.opened == 1 && sheets.handed == [[try XCTUnwrap(newest.file)]], "the sheet did not open on the newest shot: \(sheets.handed)")
        try require(s.toast.holds.contains(.sheet), "the sheet is open and the window's life is not held by it")
        s.toast.unfold()
        let overlay = try await openEditor(s, on: older, staying: [newest.id])
        try require(s.toast.holds.contains(.sheet) && s.toast.holds.contains(.editor), "the holds under the editor: \(s.toast.holds)")
        return (older, newest, sheets, overlay)
    }

    func testSaveWithNothingChangedWhileAShareSheetIsOpenGivesTheShotBackAndLeavesTheSheetBe() async throws {
        let s = try scene()
        let (older, newest, sheets, overlay) = try await aSheetOpenOnTheNewestAndTheEditorOnTheOlder(s)

        await finish(s, overlay, .save)

        XCTAssertEqual(s.toast.model.shots.map(\.id), [older.id, newest.id], "the shot is not back at its place")
        XCTAssertEqual(sheets.opened, 1, "⌘S opened a sheet")
        XCTAssertTrue(s.toast.holds.contains(.sheet) && !s.toast.holds.contains(.editor), "the holds after ⌘S: \(s.toast.holds)")
        assertTheFilesAreAsTheyWere(s, [older, newest], "⌘S with a sheet open")
        XCTAssertEqual(s.board.singles, 2)
    }

    /// Share of the older shot while a sheet is open on the newest: one sheet at a time, so no second sheet opens, and the
    /// shot that came back as the newest is not the one the open sheet shows. Pinned as it is (a Share of a changed edit
    /// meets the same).
    func testShareWithNothingChangedWhileAShareSheetIsOpenOpensNoSecondSheet() async throws {
        let s = try scene()
        let (older, newest, sheets, overlay) = try await aSheetOpenOnTheNewestAndTheEditorOnTheOlder(s)

        await finish(s, overlay, .share)

        XCTAssertEqual(sheets.opened, 1, "a second sheet opened over the first")
        XCTAssertEqual(sheets.handed, [[try XCTUnwrap(newest.file)]])
        XCTAssertEqual(s.toast.model.shots.map(\.id), [newest.id, older.id])
        XCTAssertTrue(s.toast.holds.contains(.sheet) && !s.toast.holds.contains(.editor), "the holds after Share: \(s.toast.holds)")
        assertTheFilesAreAsTheyWere(s, [older, newest], "Share with a sheet open")
        XCTAssertEqual(s.board.singles, 2)
    }

    /// One shot alone: Edit takes the window with the sheet in it (the sheet is closed), and ⌘S that changed nothing brings the
    /// shot back without one.
    func testEditOnTheOnlyShotClosesTheSheetAndSaveWithNothingChangedDoesNotOpenIt() async throws {
        let s = try scene()
        let before = try await saved(s)
        let sheets = listen(s)
        var closed = 0
        s.toast.closePicker = { _ in closed += 1 }
        s.toast.requestShare()
        try require(sheets.opened == 1 && s.toast.holds.contains(.sheet), "the sheet did not open")

        let overlay = try await openEditor(s, on: before.shot)
        XCTAssertEqual(closed, 1, "the sheet was left open over the editor")
        XCTAssertFalse(s.toast.holds.contains(.sheet))
        await finish(s, overlay, .save)

        XCTAssertEqual(sheets.opened, 1, "⌘S opened a sheet")
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(s.toast.holds.contains(.sheet))
        assertTheFileIsTheSameFile(s, before)
        assertTheSavedShotIsBack(s, before)
    }
}
