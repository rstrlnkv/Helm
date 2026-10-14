import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A display that comes or goes closes the editor opened on a shot, says so, and keeps what the person drew.** The editor
/// is opened from the thumbnail of a shot that was really taken (its file is in a scratch folder), as the capsule's Edit opens
/// it; the notification is `NSApplication.didChangeScreenParametersNotification`, posted in the test process on the default
/// centre as AppKit posts it, with no display changed and no window moved.
///
/// **With marks.** One rectangle is drawn on the picture. The case asserts that the editor is closed and the controller is
/// free; that the after-shot window holds one shot, the **marked** picture, held in memory with no file and with the sentence
/// as its caption, read by the ink at the mark's place and nowhere else (the same reading is proved on the file a ⌘S of the
/// same edit writes, the first case); that one plaque titled for a shot is up; and that the shot's own file is as it was, byte
/// for byte, with nothing moved to the Trash. The picture is composed off the main thread, so the case waits on the toast's
/// own publication of the plaque and not on the clock.
///
/// **Without marks.** The case asserts that the shot the editor was opened on is back in the window as after Esc, the same
/// shot with its file and its caption, that its file is as it was, and that one plaque titled for a shot is up.
///
/// **Inputs around them, as the cases assert them.** Edit pressed while the screen is still frozen for it: the shot is still
/// in the window and the plaque is titled for a shot. The module's end between the change and the marked picture: neither a
/// shot nor a plaque arrives afterwards. Two changes in one turn over an editor with marks: one marked shot, one plaque. A
/// change while the edited shot's replacement is held at the Trash: the delivery goes on, and no plaque is given. A pop-over
/// open: it closes with the editor. An Edit that ended, by Esc on the editor or by the change itself, and then a pick on the
/// panel ended by a change, are asserted to give a plaque titled for a capture that was not taken. **Every language:** a pick,
/// an editor with nothing drawn and an editor with marks, each in the eight languages, with the sentence of the language word
/// for word (`DisplayChange.sentences`) and the title for a capture that was not taken or for a shot.
///
/// The controller is the running app's over real files, a toast with no window and an overlay that is built and never ordered
/// in (`PileScene`, with a bar seam that puts nothing on a screen). **Each case that opens the editor first asks whether its
/// subject happened:** the shot was taken, the editor opened on it and the shot left the window for it, the mark is on the
/// editor's layers. A case whose precondition fails stops there, with a line that begins "precondition".
///
/// **Which row was shown red by taking a piece of the fix back.** The marks not kept (`heldForExit` read as nothing):
/// `testAnEditorWithMarksClosesAndTheWindowHoldsTheMarkedPictureAsAShotAndSaysSo`, `testTwoChangesInOneTurnWithMarksKeepOneShotAndSayOnce`,
/// the precondition of `testTheModuleEndingWhileTheMarkedPictureIsBeingMadeLeavesNoShotAndNoPlaque` and the marks part of
/// `testTheSentenceAndBothTitlesAreSaidInEveryLanguage`. `teardown` not cancelling `keepTask`:
/// `testTheModuleEndingWhileTheMarkedPictureIsBeingMadeLeavesNoShotAndNoPlaque`, at its absences. The `delivering` guard gone:
/// `testAChangeWhileTheEditedShotIsBeingReplacedLeavesTheDeliveryAlone`. The title of the editor with no marks losing its shot:
/// `testAnEditorWithNoMarksClosesAndTheShotIsBackAsAfterEscAndTheWindowSaysSo`,
/// `testAChangeWithAPopOverOpenClosesTheEditorAndThePopOver` and the no-marks part of the language row. The sentence of
/// `.displayChanged` answering `.displayGone`'s: the language row. `editFromThumbnail` not setting `editPressed`:
/// `testAChangeBeforeTheEditorHasOpenedLeavesTheShotInTheWindowAndTitlesThePlaqueForAShot` and the precondition of half B of
/// `testAnEditThatEndedLeavesNothingBehindForTheNextPressesPlaque`. `busy`'s `didSet` not clearing `editPressed`: both halves
/// of `testAnEditThatEndedLeavesNothingBehindForTheNextPressesPlaque`. The other rows of this family assert what their text
/// says; none of the pieces taken back turned them red.
///
/// Total failure of the subject prints: "precondition: the editor did not open on the shot"; otherwise the expectations: an
/// editor still open, no shot with the marks in the window, no plaque, a shot that is not back, a file that changed.
@MainActor
final class TheEditorMeetsADisplayThatComesOrGoesTests: XCTestCase {

    private var scenes: [PileScene] = []
    private var boxes: [PanelRig.Rig] = []

    override func tearDown() {
        for scene in scenes { scene.capture.release(); scene.trash.release(); scene.teardown() }
        for box in boxes { box.controller.teardown() }
        scenes = []
        boxes = []
        super.tearDown()
    }

    private struct PreconditionFailed: Error {}

    private func require(_ ok: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard ok else {
            XCTFail("precondition: \(message)", file: file, line: line)
            throw PreconditionFailed()
        }
    }

    private func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    /// What the shot was before the editor opened on it.
    private struct Taken {
        let shot: ShotToastModel.Shot
        let url: URL
        let bytes: Data
        let names: [String]
    }

    /// A scene, a shot taken into it, the editor opened on that shot; with `marks` one rectangle is drawn.
    private func editing(marks: Bool) async throws -> (scene: PileScene, taken: Taken, overlay: CaptureOverlay, area: CGRect,
                                                       plaques: DisplayChange.Plaques) {
        let scene = try PileScene(self, name: "display-change", presentBar: { _ in })
        scenes.append(scene)
        let plaques = DisplayChange.Plaques(scene.toast)
        let shot = try await scene.take(width: 400)
        let url = try XCTUnwrap(shot.file)
        let taken = Taken(shot: shot, url: url, bytes: try Data(contentsOf: url), names: names(scene.desktop))
        try require(!taken.bytes.isEmpty && taken.names == [url.lastPathComponent], "the shot's file is not alone in its folder")
        scene.press(shot)
        await waitUntil("the editor opened on the shot") { scene.editors == 1 }
        try require(scene.editors == 1, "the editor did not open on the shot")
        let overlay = try XCTUnwrap(scene.overlay)
        let area = try XCTUnwrap(overlay.editedArea)
        try require(area.size == CGSize(width: 400, height: 300), "the area is not the whole 400 x 300 picture: \(area)")
        try require(scene.controller.isBusy && overlay.isOpen && scene.toast.model.shots.isEmpty, "the shot is still in the window, or the editor is not open")
        if marks {
            scene.draw(overlay)
            try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        } else {
            try require(overlay.editedLayers.isEmpty, "the editor holds a layer with no mark drawn")
        }
        return (scene, taken, overlay, area, plaques)
    }

    private func decoded(file url: URL) -> CGImage? { CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }

    private func assertTheFileIsAsItWas(_ scene: PileScene, _ taken: Taken, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try? Data(contentsOf: taken.url), taken.bytes, "\(what): the shot's file changed", file: file, line: line)
        XCTAssertEqual(names(scene.desktop), taken.names, "\(what): the folder holds other files than the shot's", file: file, line: line)
        XCTAssertTrue(scene.trash.moved.isEmpty, "\(what): something was moved to the Trash: \(scene.trash.moved)", file: file, line: line)
    }

    // MARK: The reading of the mark is proved where the mark is certain

    /// The control of the reading: the same edit left by ⌘S replaces the file, and the mark is read in it at its place and
    /// nowhere else, while the picture of a shot nobody drew on reads as unmarked.
    func testTheMarkIsReadAtItsPlaceInTheFileTheSameEditSaves() async throws {
        let (scene, _, overlay, area, _) = try await editing(marks: true)
        overlay.perform(.exit(.save))
        await waitUntil("the delivery was done") { !scene.controller.isBusy }
        let files = names(scene.desktop)
        try require(files.count == 1, "the folder does not hold one file: \(files)")
        let saved = try XCTUnwrap(decoded(file: scene.desktop.appendingPathComponent(files[0])))
        XCTAssertTrue(DisplayChange.isMarked(saved, origin: area.origin, size: area.size), "the control: the saved file does not read as marked at \(area)")
        XCTAssertFalse(DisplayChange.isMarked(try ShotToastRig.picture(width: 400, height: 300), origin: area.origin, size: area.size),
                       "the control: a picture nobody drew on reads as marked")
    }

    // MARK: With marks

    func testAnEditorWithMarksClosesAndTheWindowHoldsTheMarkedPictureAsAShotAndSaysSo() async throws {
        let (scene, taken, overlay, area, plaques) = try await editing(marks: true)
        await DisplayChange.happens()
        let body = await DisplayChange.nextPlaque(of: scene.toast)
        XCTAssertNotNil(body, "the plaque never came")

        XCTAssertFalse(overlay.isOpen, "the editor is still open")
        XCTAssertFalse(scene.controller.isBusy, "the controller is still busy with the editor")
        DisplayChange.assertPlaque(of: scene.toast, plaques, "an editor with marks", titled: .ofAShot)
        let marked = scene.toast.model.shots.filter { DisplayChange.isMarked($0.full, origin: area.origin, size: area.size) }
        XCTAssertEqual(marked.count, 1,
                       "the window does not hold the marked picture as a shot: \(scene.toast.model.shots.map { ($0.id, $0.caption as Any, $0.file as Any) })")
        XCTAssertEqual(scene.toast.model.shots.count, 1, "the window holds other shots than the marked picture")
        if let shot = marked.first {
            XCTAssertNil(shot.file, "the marked shot has a file")
            XCTAssertEqual(shot.caption, ScStr.refusal(.displayChanged), "the marked shot has not the sentence as its caption")
        }
        assertTheFileIsAsItWas(scene, taken, "an editor with marks")
    }

    // MARK: Without marks

    func testAnEditorWithNoMarksClosesAndTheShotIsBackAsAfterEscAndTheWindowSaysSo() async throws {
        let (scene, taken, overlay, _, plaques) = try await editing(marks: false)
        await DisplayChange.happens()

        XCTAssertFalse(overlay.isOpen, "the editor is still open")
        XCTAssertFalse(scene.controller.isBusy, "the controller is still busy with the editor")
        XCTAssertEqual(scene.toast.model.shots.map(\.id), [taken.shot.id], "the shot the editor was opened on is not back in the window")
        XCTAssertEqual(scene.toast.model.shots.first?.file, taken.url, "the shot that came back has not its file")
        XCTAssertEqual(scene.toast.model.shots.first?.caption, taken.shot.caption, "the shot that came back has not its caption")
        DisplayChange.assertPlaque(of: scene.toast, plaques, "an editor with no marks", titled: .ofAShot)
        assertTheFileIsAsItWas(scene, taken, "an editor with no marks")
    }

    // MARK: The inputs nobody planned

    /// Edit pressed and the screen still frozen for it: the shot has not left the window, and it is a shot that was taken.
    func testAChangeBeforeTheEditorHasOpenedLeavesTheShotInTheWindowAndTitlesThePlaqueForAShot() async throws {
        let scene = try PileScene(self, name: "display-change", presentBar: { _ in })
        scenes.append(scene)
        let plaques = DisplayChange.Plaques(scene.toast)
        let shot = try await scene.take(width: 400)
        scene.capture.hold()
        scene.press(shot)
        await waitUntil("the freeze for the editor is out") { scene.capture.isHeld }
        try require(scene.controller.isBusy && scene.editors == 0 && scene.toast.model.shots.map(\.id) == [shot.id],
                    "the press is not waiting on the freeze with the shot in the window")

        await DisplayChange.happens()
        XCTAssertFalse(scene.controller.isBusy, "the change did not end the press")
        XCTAssertEqual(scene.toast.model.shots.map(\.id), [shot.id], "the shot that was taken is not in the window")
        DisplayChange.assertPlaque(of: scene.toast, plaques, "an Edit before the editor opened", titled: .ofAShot)

        scene.capture.release()
        await grace(0.25)
        XCTAssertEqual(scene.editors, 0, "an editor opened after the change")
        XCTAssertEqual(scene.toast.model.shots.map(\.id), [shot.id], "the shot left the window after the freeze came back")
    }

    /// Edit pressed and ended, then the panel's pick ended by a change: the plaque is titled for a capture that was not taken.
    /// What the Edit press left behind must not reach the next press, whether the Edit ended by Esc on the editor (A) or by
    /// the change itself (B).
    func testAnEditThatEndedLeavesNothingBehindForTheNextPressesPlaque() async throws {
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                 context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53))
        // A: the editor opened and closed by Esc.
        let (scene, _, overlay, _, plaques) = try await editing(marks: false)
        overlay.keyDown(esc)
        await waitUntil("the Esc ended the editor's press") { !scene.controller.isBusy }
        try require(!overlay.isOpen && plaques.count == 0, "Esc did not end the editor, or a plaque was given for it")
        try await assertAPickEndedByAChangeIsNotTaken(scene, plaques, after: "an Edit ended by Esc")

        // B: the Edit ended by the change itself, while the freeze for it was out.
        let other = try PileScene(self, name: "display-change", presentBar: { _ in })
        scenes.append(other)
        let heard = DisplayChange.Plaques(other.toast)
        let shot = try await other.take(width: 400)
        other.capture.hold()
        other.press(shot)
        await waitUntil("the freeze for the editor is out") { other.capture.isHeld }
        try require(other.controller.isBusy && other.editors == 0, "the Edit is not waiting on the freeze")
        await DisplayChange.happens()
        try require(!other.controller.isBusy && heard.count == 1 && heard.heard[0].title == DisplayChange.Title.ofAShot.text,
                    "the change did not end the Edit with the plaque for a shot: \(heard.heard)")
        other.capture.release()
        await grace(0.25)
        try await assertAPickEndedByAChangeIsNotTaken(other, heard, after: "an Edit ended by the change")
    }

    /// The panel opened and a window being picked, then a change: one more plaque, titled for a capture that was not taken.
    private func assertAPickEndedByAChangeIsNotTaken(_ scene: PileScene, _ plaques: DisplayChange.Plaques, after what: String,
                                                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let opened = scene.editors, given = plaques.count
        scene.controller.begin(.panel)
        scene.controller.bar.model.choose(.window)
        await waitUntil("the picking overlay opened") { scene.editors == opened + 1 }
        let picking = try XCTUnwrap(scene.overlay, file: file, line: line)
        try require(scene.controller.isBusy && picking.isOpen && scene.controller.bar.selecting,
                    "\(what): the pick is not open on the panel", file: file, line: line)
        await DisplayChange.happens()
        XCTAssertFalse(scene.controller.isBusy, "\(what): the change did not end the pick", file: file, line: line)
        XCTAssertEqual(plaques.count, given + 1, "\(what): the pick was given \(plaques.count - given) plaques: \(plaques.heard)", file: file, line: line)
        XCTAssertEqual(plaques.heard.last?.title, DisplayChange.Title.notTaken.text,
                       "\(what): the pick's plaque is titled «\(plaques.heard.last?.title ?? "none")», not «\(DisplayChange.Title.notTaken.text)»", file: file, line: line)
        XCTAssertNotEqual(DisplayChange.Title.notTaken.text, DisplayChange.Title.ofAShot.text, "the two titles read alike in \(AppLanguage.current)",
                          file: file, line: line)
    }

    /// The module ends right after the change, while the marked picture is being made: nothing arrives after it.
    func testTheModuleEndingWhileTheMarkedPictureIsBeingMadeLeavesNoShotAndNoPlaque() async throws {
        let (scene, taken, _, _, plaques) = try await editing(marks: true)
        final class Seen: @unchecked Sendable { var busy: Bool?; var shots: Int?; var plaque: Int? }
        let seen = Seen()
        let controller = scene.controller, toast = scene.toast
        // Registered after the controller's own listener, so its block runs after the controller's in the same turn.
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                seen.busy = controller.isBusy
                seen.shots = toast.model.shots.count
                seen.plaque = plaques.count
                controller.teardown()
            }
        }
        addTeardownBlock { NotificationCenter.default.removeObserver(observer) }
        await DisplayChange.happens()
        try require(seen.busy == false && seen.shots == 0 && seen.plaque == 0,
                    "the module did not end between the change and the marked picture: busy \(String(describing: seen.busy)), shots \(String(describing: seen.shots)), plaques \(String(describing: seen.plaque))")

        await grace(0.4)
        XCTAssertTrue(scene.toast.model.shots.isEmpty, "a shot arrived after the module ended: \(scene.toast.model.shots.map(\.id))")
        XCTAssertNil(DisplayChange.plaque(of: scene.toast), "a plaque arrived after the module ended")
        XCTAssertEqual(plaques.count, 0, "the window was given a plaque after the module ended")
        assertTheFileIsAsItWas(scene, taken, "the module ended")
    }

    /// Two changes in one turn with marks on the editor: one marked shot, one plaque.
    func testTwoChangesInOneTurnWithMarksKeepOneShotAndSayOnce() async throws {
        let (scene, taken, _, area, plaques) = try await editing(marks: true)
        await DisplayChange.happens(times: 2)
        _ = await DisplayChange.nextPlaque(of: scene.toast)
        await grace(0.3)

        XCTAssertFalse(scene.controller.isBusy)
        XCTAssertEqual(plaques.count, 1, "the window was given \(plaques.count) plaques for two changes in one turn")
        let marked = scene.toast.model.shots.filter { DisplayChange.isMarked($0.full, origin: area.origin, size: area.size) }
        XCTAssertEqual(marked.count, 1, "the window does not hold exactly one marked picture")
        XCTAssertEqual(scene.toast.model.shots.count, 1, "the window holds \(scene.toast.model.shots.count) shots")
        assertTheFileIsAsItWas(scene, taken, "two changes")
    }

    /// An exit that is already being delivered is not a capture the change ends: the replacement is written, the new shot is
    /// in the window, and no plaque is laid over a shot that was saved.
    func testAChangeWhileTheEditedShotIsBeingReplacedLeavesTheDeliveryAlone() async throws {
        let (scene, taken, overlay, _, plaques) = try await editing(marks: true)
        scene.trash.hold()
        overlay.perform(.exit(.confirm))
        await waitUntil("the move to the Trash was reached") { !scene.trash.asked.isEmpty }
        try require(scene.controller.isBusy, "the delivery is not under way")

        await DisplayChange.happens()
        XCTAssertTrue(scene.controller.isBusy, "the change ended a delivery that was under way")
        XCTAssertEqual(plaques.count, 0, "a plaque was given over a shot that is being saved")
        scene.trash.release()
        await waitUntil("the replacement ended") { !scene.controller.isBusy }
        XCTAssertEqual(scene.trash.moved, [taken.url], "the original was not replaced")
        XCTAssertEqual(scene.toast.model.shots.count, 1, "the replacement is not in the window")
        XCTAssertNotNil(scene.toast.model.shots.first?.file, "the replacement has no file")
        XCTAssertEqual(plaques.count, 0, "a plaque was given over a shot that was saved")
    }

    /// The pop-over of an editor tool is up when the change comes: the editor goes with it, and the controller is free.
    func testAChangeWithAPopOverOpenClosesTheEditorAndThePopOver() async throws {
        let (scene, _, overlay, _, plaques) = try await editing(marks: false)
        overlay.perform(.tool(.pen))
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        try require(overlay.popoverIsOpen, "the pop-over did not open")
        await DisplayChange.happens()
        XCTAssertFalse(overlay.isOpen, "the editor is still open")
        XCTAssertFalse(overlay.popoverIsOpen, "the pop-over is still open")
        XCTAssertFalse(scene.controller.isBusy)
        DisplayChange.assertPlaque(of: scene.toast, plaques, "an editor with a pop-over", titled: .ofAShot)
    }

    // MARK: Every language

    /// The plaques a change gives, in each of the eight languages: a press under way (titled for a capture that was
    /// not taken), an editor with nothing drawn and an editor with marks (titled for a shot), each with the sentence of the
    /// language word for word; the marked shot's caption is that sentence.
    func testTheSentenceAndBothTitlesAreSaidInEveryLanguage() async throws {
        var seen: [AppLanguage] = []
        for language in AppLanguage.allCases {
            await AppLanguage.only(language) {
                do {
                    let box = try PanelRig.rig(values: [ScreenshotsSettings.Key.thumbnail: false])
                    boxes.append(box)
                    let picking = DisplayChange.Plaques(box.controller.toast)
                    box.controller.begin(.panel)
                    box.controller.bar.model.choose(.window)
                    await waitUntil("the overlay opened") { box.held.overlay != nil }
                    await DisplayChange.happens()
                    DisplayChange.assertPlaque(of: box.controller.toast, picking, "a pick in \(language)", titled: .notTaken)

                    let (bare, _, _, _, bareCount) = try await editing(marks: false)
                    await DisplayChange.happens()
                    DisplayChange.assertPlaque(of: bare.toast, bareCount, "an editor with nothing drawn in \(language)", titled: .ofAShot)

                    let (drawn, _, _, _, drawnCount) = try await editing(marks: true)
                    await DisplayChange.happens()
                    _ = await DisplayChange.nextPlaque(of: drawn.toast)
                    DisplayChange.assertPlaque(of: drawn.toast, drawnCount, "an editor with marks in \(language)", titled: .ofAShot)
                    XCTAssertEqual(drawn.toast.model.shots.first?.caption, DisplayChange.sentences[language],
                                   "the marked shot's caption is not the sentence in \(language)")
                    seen.append(language)
                } catch {
                    XCTFail("\(language): \(error)")
                }
            }
        }
        XCTAssertEqual(Set(seen), Set(AppLanguage.allCases), "a language was not reached: \(seen)")
        XCTAssertEqual(Set(DisplayChange.sentences.values).count, AppLanguage.allCases.count, "two languages share a sentence")
    }
}
