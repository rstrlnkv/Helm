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

/// **A delivery that was refused keeps the person's marks, and a picture that could not be composed is said.** An area is
/// drawn on, one mark put on it, and the editor left by ⌘S, by the check mark or from the thumbnail's Edit; the folder takes no
/// write (a directory of mode 0555, as the engine's tests make one). The marked picture then exists nowhere but in memory,
/// and the after-shot window is where it must stay: a finished shot (a caption, which is what the model asks before the capsule,
/// Edit and Copy serve a shot) that holds the full marked picture and has no file, under the plaque that says why the write was
/// refused, and the shot is what the window shows when the plaque is taken away by its ✕ or by its nine seconds. The capsule's
/// Copy then puts the marked pixels on the board. ⌘S copies nothing, so the board stays as it was; the check mark copies before it
/// writes, so the board has the picture whatever the write did. With the thumbnail setting off the picture is kept as well, since
/// it is the only copy there is. A plaque over a shot that was kept does not say the screenshot was not taken. The caption of a
/// shot kept with nothing saved and nothing copied is the sentence of the refusal that kept it, the plaque's own body, and never
/// the thumbnail's name: the window reads that name as the label of a single shot, and a caption beside it is the same word said
/// twice and nothing of what happened. After the check mark with the clipboard taking the picture it stays the word for copied.
///
/// What a kept shot makes reachable is read at the end: Edit on it and a save that lands in a file, a group at its bound, both
/// the clipboard and the folder refusing, and a delivery the module's switch cancelled while the disk was refusing. A picture that
/// could not be composed is read on every exit, Pin among them, and on ⌘C of a saved shot.
///
/// The second half is a picture that could not be composed: an exit of the editor that asks for a picture and gets none. The
/// reachable input is a blur box of one pixel, which the file refuses on purpose (a mean of one pixel hides nothing, `Pixelate.tile`),
/// drawn by a gesture the real overlay takes (out three points and back, so it is no click) on a display of scale 1, where a point
/// is a pixel. An area the frozen picture does not hold is reached only by a freeze that is not the system's (its image smaller
/// than its frame in points times its scale), and an edit that ends on another display is not reachable at all: the overlay
/// opened on a picture starts no area on another display (`CaptureOverlay.mouseDown`). Each of those is a plaque and a log line
/// of the module's category that names no path, whichever the exit. The plaque's title is what the editor was opened on: an area
/// that was never taken is a screenshot that was not taken (`ScStr.failedTitle`), and an edit of a shot that was taken, saved or
/// only copied, is titled as that shot is (`ScStr.thumbnailLabel`), since «not taken» is untrue of a shot that was taken; the body
/// is the same sentence for both.
///
/// The controller is the running app's, over real files in a scratch folder, a toast with no window and an overlay that is built
/// and never ordered in (`PileScene`), driven through the overlay's own mouse and action entries, as the views drive them.
/// **Each case first asks whether its subject happened:** the area was drawn, the mark is on it, the folder took no write and said
/// so on the plaque. A case whose precondition fails stops there, with a line that begins "precondition". The pixel reading is
/// proved by a control that does write: the same mark in a folder that takes it is read out of the file by the same helper.
///
/// Total failure of the subject prints: a window with no shot after a refused write, a plaque that says the screenshot was not
/// taken over a kept one, a picture without the mark or with the mark in the wrong place, a board that took a write nobody asked
/// for, a delivery that ended with no plaque and no line.
@MainActor
final class ARefusedDeliveryKeepsTheMarksAndAnUncomposedPictureIsSaidTests: XCTestCase {

    private var scenes: [PileScene] = []
    private var constructed: [(controller: CaptureController, toast: ShotToast)] = []

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        for one in constructed { one.controller.teardown(); one.toast.dismiss() }
        constructed = []
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "refused-keeps")
        scenes.append(scene)
        return scene
    }

    private struct PreconditionFailed: Error {}

    private func require(_ ok: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard ok else {
            XCTFail("precondition: \(message)", file: file, line: line)
            throw PreconditionFailed()
        }
    }

    private func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    /// The module's lines of the log, oldest first.
    private var lines: [String] { HelmLog.shared.recentEntries().filter { $0.category == ScreenshotsEngine.moduleID }.map(\.message) }

    // MARK: What is read

    /// A picture read as sRGB, and the question every case asks of it: is the mark on it, at its place, and nowhere else.
    @MainActor
    private struct Pixels {
        let width: Int, height: Int
        private let bytes: [UInt8]
        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            bytes = try ScreenAndFile.rgb(image)
        }
        private func at(_ x: Int, _ y: Int) -> [Int] {
            let (x, y) = (min(max(x, 0), width - 1), min(max(y, 0), height - 1))
            let i = (y * width + x) * 4
            return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
        }
        /// How many pixels within `radius` of the point differ from the picture's own ground, its last pixel, by more than 60 in a
        /// channel. The ground is the colour the frozen screen was filled with; ink is whatever is not it.
        func ink(near point: CGPoint, radius: Int = 4) -> Int {
            let ground = at(width - 1, height - 1)
            var count = 0
            for y in Int(point.y) - radius...Int(point.y) + radius {
                for x in Int(point.x) - radius...Int(point.x) + radius where x >= 0 && y >= 0 && x < width && y < height {
                    if zip(at(x, y), ground).contains(where: { abs($0 - $1) > 60 }) { count += 1 }
                }
            }
            return count
        }
    }

    /// Where the mark stands in the picture it was drawn on, in the picture's pixels (a display of scale 1: a point is a pixel).
    private struct Mark {
        let size: CGSize
        let onTheStroke: CGPoint
        let insideTheOutline: CGPoint
        let farFromIt: CGPoint

        /// A fresh area from (100, 100) to (700, 500), a rectangle from (300, 300) to (500, 450) of the display on it: its left edge.
        static let fresh = Mark(size: CGSize(width: 600, height: 400), onTheStroke: CGPoint(x: 200, y: 275),
                                insideTheOutline: CGPoint(x: 300, y: 275), farFromIt: CGPoint(x: 560, y: 360))

        /// The picture of a shot of `size` standing at `origin` of the display, the same rectangle drawn on it: its right edge.
        static func edit(size: CGSize, origin: CGPoint) -> Mark {
            Mark(size: size, onTheStroke: CGPoint(x: 500 - origin.x, y: 375 - origin.y),
                 insideTheOutline: CGPoint(x: 400 - origin.x, y: 375 - origin.y),
                 farFromIt: CGPoint(x: size.width - 30, y: size.height - 30))
        }
    }

    private func assertMarked(_ image: CGImage?, _ mark: Mark, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let image else { return XCTFail("\(what): there is no picture", file: file, line: line) }
        XCTAssertEqual(CGSize(width: image.width, height: image.height), mark.size, "\(what): the picture's pixel size", file: file, line: line)
        guard image.width == Int(mark.size.width), image.height == Int(mark.size.height), let pixels = try? Pixels(image) else { return }
        XCTAssertGreaterThan(pixels.ink(near: mark.onTheStroke), 0, "\(what): no ink at the mark's pixel \(mark.onTheStroke)", file: file, line: line)
        XCTAssertEqual(pixels.ink(near: mark.insideTheOutline), 0, "\(what): ink inside the outline, where the mark is empty", file: file, line: line)
        XCTAssertEqual(pixels.ink(near: mark.farFromIt), 0, "\(what): ink far from the mark", file: file, line: line)
    }

    private func decoded(_ data: Data?) -> CGImage? {
        data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    private func decoded(file url: URL) -> CGImage? { CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }

    // MARK: Driving the editor

    /// A folder that takes no write: a directory of mode 0555, put back before the scratch sweep.
    private func lock(_ folder: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        try require(!FileManager.default.createFile(atPath: folder.appendingPathComponent("probe").path, contents: Data()),
                    "the folder took a file though it is locked", file: file, line: line)
    }

    /// The area press, and the area (100, 100) to (700, 500) of the first display released: the editor is up on it.
    private func freshArea(_ s: PileScene) async throws -> CaptureOverlay {
        s.controller.begin(.area)
        await waitUntil("the area press reached the overlay") { s.editors == 1 }
        try require(s.editors == 1, "the area press did not reach the overlay")
        let overlay = try XCTUnwrap(s.overlay)
        let id = try XCTUnwrap(s.frames.first).id
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 700, y: 500), flags: [])
        overlay.mouseUp(on: id)
        try require(overlay.editedArea == CGRect(x: 100, y: 100, width: 600, height: 400),
                    "the area is not 600 x 400 at (100, 100): \(String(describing: overlay.editedArea))")
        try require(s.controller.isBusy, "the controller is free with the editor open")
        return overlay
    }

    /// One blue rectangle, (300, 300) to (500, 450): blue, since the frozen screen of the rig is red and a red mark on it is no ink.
    private func markInBlue(_ s: PileScene, _ overlay: CaptureOverlay) throws {
        let id = s.display(of: overlay)
        overlay.perform(.tool(.rectangle))
        overlay.perform(.color(.blue))
        overlay.mouseDown(on: id, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 500, y: 450), flags: [])
        overlay.mouseUp(on: id)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
    }

    /// A blur box of one point, which the real gesture makes: pressed, taken out three points or more so that it is no click,
    /// and brought back to one point from where it began.
    private func onePixelBlur(_ s: PileScene, _ overlay: CaptureOverlay, at base: CGPoint) throws {
        let id = s.display(of: overlay)
        overlay.perform(.tool(.blur))
        overlay.mouseDown(on: id, at: base, flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: base.x + 10, y: base.y), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: base.x + 1, y: base.y + 1), flags: [])
        overlay.mouseUp(on: id)
        let layers = overlay.editedLayers
        try require(layers.count == 1 && layers.first?.tool == .blur, "the blur box was not drawn: \(layers)")
        try require(layers[0].frame.size == CGSize(width: 1, height: 1), "the box is not one point square: \(layers[0].frame)")
    }

    /// The exit, and the delivery awaited.
    private func leave(_ s: PileScene, _ overlay: CaptureOverlay, by exit: EditorExit) async {
        overlay.perform(.exit(exit))
        await waitUntil("the delivery was done") { !s.controller.isBusy }
    }

    /// A fresh area with one blue mark, left by `exit` into the Desktop of the scene, which takes no write. The plaque that says
    /// so is a precondition of every case below it, and its body is the write's own sentence.
    private func markedAndRefused(_ s: PileScene, by exit: EditorExit, file: StaticString = #filePath, line: UInt = #line) async throws {
        try lock(s.desktop, file: file, line: line)
        let overlay = try await freshArea(s)
        try markInBlue(s, overlay)
        try require(s.board.singles == 0 && names(s.desktop).isEmpty, "the board or the folder was touched before the exit", file: file, line: line)
        await leave(s, overlay, by: exit)
        try require(names(s.desktop).isEmpty, "a file was written into the locked folder: \(names(s.desktop))", file: file, line: line)
        guard case .refusal(_, let body, _)? = s.toast.model.refusal else {
            XCTFail("precondition: no plaque after a refused write: \(String(describing: s.toast.model.content))", file: file, line: line)
            throw PreconditionFailed()
        }
        XCTAssertEqual(body, ScStr.refusal(.write(.noPermission)), "the plaque does not say the write's own sentence", file: file, line: line)
    }

    private enum Away: CustomStringConvertible {
        case closeControl, nineSeconds
        var description: String { self == .closeControl ? "its ✕" : "its nine seconds" }
    }

    /// The plaque goes, as the ✕ takes it (the model's `dismiss`, which the view calls) or as its nine seconds end it.
    private func takeThePlaqueAway(_ s: PileScene, by way: Away, file: StaticString = #filePath, line: UInt = #line) {
        switch way {
        case .closeControl:
            s.toast.model.dismiss()
        case .nineSeconds:
            XCTAssertFalse(s.toast.advance(by: 8.5), "the window ended inside the plaque's nine seconds", file: file, line: line)
            XCTAssertNotNil(s.toast.model.refusal, "the plaque went before its nine seconds", file: file, line: line)
            XCTAssertFalse(s.toast.advance(by: 0.5), "the window ended with the plaque instead of showing the shot", file: file, line: line)
        }
        XCTAssertNil(s.toast.model.refusal, "the plaque stayed after \(way)", file: file, line: line)
    }

    /// The captions a shot whose write was refused cannot have: it was not saved, and what replaced a file is not true of it.
    private func sentencesOfADeliveryThatWorked(copiedIsOne: Bool) -> [(name: String, text: String)] {
        var all = [("ScStr.saved", ScStr.saved), ("ScStr.savedAndCopied", ScStr.savedAndCopied), ("ScStr.replaced", ScStr.replaced)]
        if copiedIsOne { all.append(("ScStr.copied", ScStr.copied)) }
        return all
    }

    /// The shot is finished, holds the full marked picture in memory and has no file, and its caption is `expected` and none of
    /// `banned` nor the thumbnail's own name: after a refusal that kept it with nothing saved and nothing copied `expected` is the
    /// refusal's sentence, which is the body of the plaque over it.
    private func assertIsTheMarkedPictureKept(_ shot: ShotToastModel.Shot, _ mark: Mark, banned: [(name: String, text: String)],
                                              caption expected: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(shot.caption, "\(what): the shot is not finished (no caption): the capsule, Edit and Copy serve a shot that has one", file: file, line: line)
        XCTAssertNil(shot.file, "\(what): the shot has a file", file: file, line: line)
        if let caption = shot.caption {
            for sentence in banned {
                XCTAssertNotEqual(caption, sentence.text, "\(what): the caption is \(sentence.name), which says what did not happen", file: file, line: line)
            }
            XCTAssertNotEqual(caption, ScStr.thumbnailLabel,
                              "\(what): the caption is the thumbnail's own name «\(caption)», which the window already reads as the shot's label: the word is said twice and nothing of what happened",
                              file: file, line: line)
            XCTAssertEqual(caption, expected, "\(what): the caption is not «\(expected)»", file: file, line: line)
        }
        assertMarked(shot.full, mark, "\(what): the shot's full picture", file: file, line: line)
    }

    /// The capsule's Copy of the shot the window shows: the board takes one write more, and it is the marked picture.
    private func copyFromTheCapsule(_ s: PileScene, _ mark: Mark, _ what: String, file: StaticString = #filePath, line: UInt = #line) async {
        let before = s.board.singles
        s.toast.model.copy()
        await waitUntil("\(what): the capsule's Copy reached the board", file: file, line: line) { s.board.singles == before + 1 }
        XCTAssertEqual(s.board.singles, before + 1, "\(what): the Copy did not write the board once", file: file, line: line)
        assertMarked(decoded(s.board.pngs.last), mark, "\(what): the picture the Copy put on the board", file: file, line: line)
        XCTAssertNil(s.toast.model.refusal, "\(what): the Copy was told as a refusal", file: file, line: line)
    }

    /// The plaque of a picture that could not be composed: titled `title`, the body the encoding's sentence, no Open Settings.
    private func assertTheUncomposedPlaque(_ toast: ShotToast, title expected: String, _ what: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        guard case .refusal(let title, let body, let offersSettings)? = toast.model.refusal else {
            return XCTFail("\(what): no plaque: \(String(describing: toast.model.content))", file: file, line: line)
        }
        XCTAssertEqual(title, expected, "\(what): the plaque is titled «\(title)», not «\(expected)»", file: file, line: line)
        XCTAssertEqual(body, ScStr.refusal(.encoding), "\(what): the plaque does not say the encoding's sentence", file: file, line: line)
        XCTAssertFalse(offersSettings, "\(what): the plaque offers Open Settings", file: file, line: line)
    }

    // MARK: The control: the same mark where the write works

    /// The pixel reading is proved on a delivery that works: the same area, the same mark and ⌘S into a folder that takes it make
    /// a file in which the mark is read at its place, and a shot that has the file and holds no picture of its own.
    func testTheSameMarkInAFolderThatTakesTheWriteIsInTheFileAndTheReadingSeesIt() async throws {
        let s = try scene()
        let overlay = try await freshArea(s)
        try markInBlue(s, overlay)

        await leave(s, overlay, by: .save)

        let files = names(s.desktop)
        try require(files.count == 1, "the folder does not hold one file: \(files)")
        assertMarked(decoded(file: s.desktop.appendingPathComponent(files[0])), .fresh, "the control: the file")
        let plain = try Pixels(try ShotToastRig.picture(width: 600, height: 400))
        XCTAssertEqual(plain.ink(near: Mark.fresh.onTheStroke), 0, "the control: a picture with no mark reads as marked")
        XCTAssertEqual(s.toast.model.shots.count, 1)
        XCTAssertNotNil(s.toast.model.shots.first?.file)
        XCTAssertNil(s.toast.model.shots.first?.full, "a shot with a file holds a picture of its own")
        XCTAssertEqual(s.toast.model.shots.first?.caption, ScStr.saved)
        XCTAssertNil(s.toast.model.refusal)
        XCTAssertEqual(s.board.singles, 0, "the control: ⌘S wrote the board")
    }

    /// The control of the reading helpers the cases below end with (the kept shot, the plaque taken away, the capsule's Copy): the
    /// window is put by hand into the state they ask for, a finished shot with the marked picture and no file, and a plaque over
    /// it, by `showDone` and `showRefusal` without `keeping`, which is not the controller's refusal path. A helper that fails here
    /// is told from a controller that keeps nothing.
    func testTheStateTheContractAsksForReadsGreenWhenItIsBuiltByHand() async throws {
        for way in [Away.closeControl, .nineSeconds] {
            let s = try scene()
            let what = "by hand, the plaque taken away by \(way)"
            let overlay = try await freshArea(s)
            try markInBlue(s, overlay)
            await leave(s, overlay, by: .save)
            let files = names(s.desktop)
            try require(files.count == 1, "the folder does not hold one file: \(files)")
            let image = try XCTUnwrap(decoded(file: s.desktop.appendingPathComponent(files[0])))
            s.toast.dismiss()
            s.toast.showDone(image, caption: ScStr.refusal(.write(.noPermission)), file: nil)
            s.toast.showRefusal(.write(.noPermission))
            guard case .refusal(_, let body, _)? = s.toast.model.refusal else { return XCTFail("\(what): no plaque") }
            XCTAssertEqual(body, ScStr.refusal(.write(.noPermission)))

            XCTAssertEqual(s.toast.model.shots.count, 1, "\(what): the shot is not under the plaque")
            let shot = try XCTUnwrap(s.toast.model.shots.first)
            assertIsTheMarkedPictureKept(shot, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                         caption: ScStr.refusal(.write(.noPermission)), what)
            takeThePlaqueAway(s, by: way)
            XCTAssertEqual(s.toast.model.current?.id, shot.id, "\(what): the shot is not what the window shows")
            XCTAssertNotNil(s.toast.model.editSource?.held, "\(what): Edit is not offered on the shot's held picture")
            XCTAssertEqual(s.board.singles, 0, "\(what): the board took a write while the plaque went")
            await copyFromTheCapsule(s, .fresh, what)
        }
    }

    // MARK: ⌘S refused

    /// ⌘S refused: the marked picture is a finished shot of the window under the plaque, the board is as it was, and when the
    /// plaque goes, by its ✕ or its nine seconds, the shot is what the window shows and its Copy puts the marked pixels on the board.
    func testASaveTheFolderRefusedLeavesTheMarkedPictureAsAFinishedShotAndItsCopyPutsItOnTheBoard() async throws {
        for way in [Away.closeControl, .nineSeconds] {
            let s = try scene()
            let what = "⌘S refused, the plaque taken away by \(way)"
            try await markedAndRefused(s, by: .save)

            XCTAssertEqual(s.board.singles, 0, "\(what): ⌘S copies nothing, and the board took a write")
            XCTAssertEqual(s.toast.model.shots.count, 1, "\(what): the window does not hold the marked picture as a shot")
            guard let shot = s.toast.model.shots.first else { continue }
            assertIsTheMarkedPictureKept(shot, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                         caption: ScStr.refusal(.write(.noPermission)), what)

            takeThePlaqueAway(s, by: way)

            XCTAssertEqual(s.toast.model.current?.id, shot.id, "\(what): the shot is not what the window shows")
            XCTAssertTrue(s.toast.model.showsShots, "\(what): the window shows no shot")
            XCTAssertNotNil(s.toast.model.editSource?.held, "\(what): Edit is not offered on the shot's held picture")
            XCTAssertEqual(s.board.singles, 0, "\(what): the board took a write while the plaque went")
            await copyFromTheCapsule(s, .fresh, what)
        }
    }

    // MARK: The check mark refused

    /// The check mark: the engine copies before it writes, so the board has the marked picture although the write was refused,
    /// and the shot is kept as after ⌘S; its caption is the one that says it was copied, which is true of it.
    func testACheckMarkWhoseWriteWasRefusedLeavesTheMarkedPictureOnTheBoardAndAsAFinishedShot() async throws {
        let s = try scene()
        try await markedAndRefused(s, by: .confirm)

        XCTAssertEqual(s.board.singles, 1, "the check mark did not copy the picture before the write was refused")
        assertMarked(decoded(s.board.pngs.last), .fresh, "the picture on the board")
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the marked picture as a shot")
        guard let shot = s.toast.model.shots.first else { return }
        assertIsTheMarkedPictureKept(shot, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: false), caption: ScStr.copied, "✓ refused")

        takeThePlaqueAway(s, by: .closeControl)

        XCTAssertEqual(s.toast.model.current?.id, shot.id, "the shot is not what the window shows")
        await copyFromTheCapsule(s, .fresh, "✓ refused")
    }

    // MARK: An edit of a shot that was only copied

    /// A shot that was only copied: the clipboard is the save target, so it has a held picture and no file.
    private func copiedOnly(_ s: PileScene) async throws -> ShotToastModel.Shot {
        s.store.set(SaveTarget.clipboard.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400, height: 300), kind: .area))
        let shot = try XCTUnwrap(s.toast.model.shots.last, "no shot after a hand-off")
        try require(shot.file == nil && shot.full != nil, "the shot is not a copied-only one")
        try require(names(s.desktop).isEmpty && s.board.singles == 1, "the clipboard target made a file or did not copy once")
        return shot
    }

    /// The editor opened on the thumbnail of a shot that was only copied, one mark drawn: the editor, and the picture's area.
    private func editorWithAMarkOnACopiedOnlyShot(_ s: PileScene) async throws -> (overlay: CaptureOverlay, area: CGRect) {
        let held = try await copiedOnly(s)
        s.press(held)
        await waitUntil("the editor opened on the shot") { s.editors == 1 }
        try require(s.editors == 1, "the editor did not open on the shot")
        let overlay = try XCTUnwrap(s.overlay)
        let area = try XCTUnwrap(overlay.editedArea)
        try require(area.size == CGSize(width: 400, height: 300), "the area is not the whole 400 x 300 picture: \(area)")
        s.draw(overlay)
        try require(overlay.editedLayers.count == 1, "the mark was not drawn: \(overlay.editedLayers.count) layers")
        return (overlay, area)
    }

    /// The control of the case below: the same edit and ⌘S into a folder that takes the write make a file in which the mark is
    /// read at the place `Mark.edit` gives it, so that the reading of the kept picture is known to look where the mark is.
    func testTheSameEditInAFolderThatTakesTheWriteIsInTheFileAtTheMarksPlace() async throws {
        let s = try scene()
        let (overlay, area) = try await editorWithAMarkOnACopiedOnlyShot(s)

        await leave(s, overlay, by: .save)

        let files = names(s.desktop)
        try require(files.count == 1, "the folder does not hold one file: \(files)")
        assertMarked(decoded(file: s.desktop.appendingPathComponent(files[0])), .edit(size: area.size, origin: area.origin), "the control: the file of the edit")
        XCTAssertEqual(s.board.singles, 1, "the control: ⌘S wrote the board")
    }

    /// The editor opened from the thumbnail of a shot that was only copied, one mark, ⌘S refused: the marked picture is a
    /// shot of the list, as after ⌘S on a fresh area, and the board is as it was (the one copy of the unmarked shot).
    func testAnEditOfACopiedOnlyShotWhoseSaveWasRefusedKeepsTheMarkedPicture() async throws {
        let s = try scene()
        let (overlay, area) = try await editorWithAMarkOnACopiedOnlyShot(s)
        try lock(s.desktop)

        await leave(s, overlay, by: .save)

        try require(names(s.desktop).isEmpty, "a file was written into the locked folder: \(names(s.desktop))")
        guard case .refusal(_, let body, _)? = s.toast.model.refusal else {
            return XCTFail("precondition: no plaque after a refused write: \(String(describing: s.toast.model.content))")
        }
        XCTAssertEqual(body, ScStr.refusal(.write(.noPermission)), "the plaque does not say the write's own sentence")
        XCTAssertEqual(s.board.singles, 1, "⌘S copies nothing, and the board took a write")
        let mark = Mark.edit(size: area.size, origin: area.origin)
        let marked = s.toast.model.shots.filter { shot in
            guard let full = shot.full, let pixels = try? Pixels(full), pixels.width == Int(area.width), pixels.height == Int(area.height) else { return false }
            return pixels.ink(near: mark.onTheStroke) > 0
        }
        XCTAssertEqual(marked.count, 1, "the window does not hold the marked picture as a shot: \(s.toast.model.shots.map { ($0.id, $0.caption as Any) })")
        guard let shot = marked.first else { return }
        assertIsTheMarkedPictureKept(shot, mark, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                     caption: ScStr.refusal(.write(.noPermission)), "⌘S refused on an edit of a copied-only shot")

        takeThePlaqueAway(s, by: .closeControl)

        XCTAssertEqual(s.toast.model.current?.id, shot.id, "the marked shot is not what the window shows")
        await copyFromTheCapsule(s, mark, "⌘S refused on an edit of a copied-only shot")
    }

    // MARK: The thumbnail off

    /// The thumbnail off: nobody asked to see a shot, and the picture is the only copy there is, so it is kept and shown under
    /// the plaque all the same.
    func testWithTheThumbnailOffARefusedSaveStillKeepsTheMarkedPictureUnderThePlaque() async throws {
        let s = try scene()
        s.store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        try await markedAndRefused(s, by: .save)

        XCTAssertEqual(s.board.singles, 0, "⌘S copies nothing, and the board took a write")
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the marked picture as a shot")
        guard let shot = s.toast.model.shots.first else { return }
        assertIsTheMarkedPictureKept(shot, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                     caption: ScStr.refusal(.write(.noPermission)), "⌘S refused, thumbnail off")

        takeThePlaqueAway(s, by: .nineSeconds)

        XCTAssertEqual(s.toast.model.current?.id, shot.id, "the shot is not what the window shows")
        await copyFromTheCapsule(s, .fresh, "⌘S refused, thumbnail off")
    }

    // MARK: The plaque's title

    /// A plaque over a shot that was kept from its own refused delivery does not say the screenshot was not taken: it was, and it
    /// is there. No new sentence is asked for (`ShotToast.refusalContent` names a taken shot's plaque by the module's own word).
    func testThePlaqueOverAKeptShotDoesNotSayTheScreenshotWasNotTaken() async throws {
        for (exit, thumbnail) in [(EditorExit.save, true), (.confirm, true), (.save, false)] {
            let s = try scene()
            let what = "\(exit), thumbnail \(thumbnail ? "on" : "off")"
            s.store.set(thumbnail, for: ScreenshotsSettings.Key.thumbnail)
            try await markedAndRefused(s, by: exit)

            XCTAssertEqual(s.toast.model.shots.count, 1, "\(what): the shot is not kept, so the plaque stands over nothing")
            guard case .refusal(let title, _, let offersSettings)? = s.toast.model.refusal else { return XCTFail("\(what): no plaque") }
            XCTAssertFalse(title.isEmpty, "\(what): the plaque has no title")
            XCTAssertNotEqual(title, ScStr.failedTitle, "\(what): the plaque over the kept shot says «\(title)»")
            XCTAssertFalse(offersSettings, "\(what): a refused write offers Open Settings")
        }
    }

    // MARK: A picture that could not be composed

    /// An exit that asks for a picture and gets none is a plaque and a line, never silence, and does nothing else: no file, no
    /// board write, no shot, no pin. The blur box of one pixel is the input the real overlay can deliver.
    func testAPictureThatCouldNotBeComposedIsSaidOnAPlaqueAndInTheLogByEveryExitThatAsksForOne() async throws {
        HelmLog.shared.info(ScreenshotsEngine.moduleID, "probe")
        try require(lines.contains("probe"), "the log is not recording, so an absence proves nothing")
        for exit in [EditorExit.confirm, .copy, .save, .share, .pin] {
            let s = try scene()
            let overlay = try await freshArea(s)
            try onePixelBlur(s, overlay, at: CGPoint(x: 300, y: 300))
            HelmLog.shared.clearTail()
            let before = lines

            await leave(s, overlay, by: exit)

            // The subject: nothing was delivered, so the silence is the picture's not being made and not a delivery that went on.
            XCTAssertEqual(names(s.desktop), [], "\(exit): a file was made")
            XCTAssertEqual(s.board.singles, 0, "\(exit): the board took a write")
            XCTAssertTrue(s.toast.model.shots.isEmpty, "\(exit): a shot is in the window")
            XCTAssertFalse(s.controller.isBusy, "\(exit): the controller is busy")
            XCTAssertTrue(s.controller.pins.pins.isEmpty, "\(exit): a pin was opened")
            // The thing said.
            XCTAssertNotNil(s.toast.model.refusal, "\(exit): no plaque: the picture that could not be composed is not said")
            // The control of the title below: an area that was never taken is a screenshot that was not taken.
            assertTheUncomposedPlaque(s.toast, title: ScStr.failedTitle, "\(exit), a fresh area")
            let new = lines
            XCTAssertGreaterThan(new.count, before.count, "\(exit): no line of the module's category in the log")
            for line in new { XCTAssertFalse(line.contains("/"), "\(exit): the line names a path: \(line)") }
        }
    }

    /// The control of the case above: the same gesture with a box of twenty points is composed and delivered, so the nothing
    /// above is the box of one pixel and not the rig.
    func testTheSameBlurOfTwentyPointsIsComposedAndDelivered() async throws {
        let s = try scene()
        let overlay = try await freshArea(s)
        let id = s.display(of: overlay)
        overlay.perform(.tool(.blur))
        overlay.mouseDown(on: id, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 320, y: 320), flags: [])
        overlay.mouseUp(on: id)
        try require(overlay.editedLayers.count == 1 && overlay.editedLayers[0].frame.size == CGSize(width: 20, height: 20),
                    "the blur box is not 20 points square: \(overlay.editedLayers.map(\.frame))")

        await leave(s, overlay, by: .save)

        XCTAssertEqual(names(s.desktop).count, 1, "the control: the picture was not written")
        XCTAssertNil(s.toast.model.refusal, "the control: a plaque is up")
        XCTAssertEqual(s.toast.model.shots.first?.caption, ScStr.saved)
    }

    /// The same box on an edit of a shot the window held: the editor opened from the thumbnail, the exit asks for a picture and
    /// gets none, by the check mark, ⌘S and Share (⌘C is its own case below). What becomes of the shot that went into the editor
    /// is not pinned here; the plaque, its title and the line are, and the shot's file on the disk. The shot was taken, which is
    /// why the plaque is titled as a shot is and not as a capture that failed.
    func testAPictureThatCouldNotBeComposedOnAnEditOfASavedShotIsSaidToo() async throws {
        for exit in [EditorExit.confirm, .save, .share] {
            let s = try scene()
            let what = "\(exit), an edit of a saved shot"
            let saved = try await s.take(width: 400, height: 300)
            s.press(saved)
            await waitUntil("the editor opened on the shot") { s.editors == 1 }
            try require(s.editors == 1, "\(what): the editor did not open on the shot")
            let overlay = try XCTUnwrap(s.overlay)
            let area = try XCTUnwrap(overlay.editedArea)
            try onePixelBlur(s, overlay, at: CGPoint(x: area.minX + 100, y: area.minY + 100))
            HelmLog.shared.clearTail()
            let before = lines
            let (trashed, files) = (s.trash.asked, names(s.desktop))
            try require(files.count == 1, "\(what): the folder does not hold the saved shot's file: \(files)")

            await leave(s, overlay, by: exit)

            XCTAssertEqual(s.trash.asked, trashed, "\(what): the original was sent to the Trash for a picture that was never made")
            XCTAssertEqual(names(s.desktop), files, "\(what): the folder changed")
            XCTAssertNotNil(s.toast.model.refusal, "\(what): no plaque: the picture that could not be composed is not said")
            assertTheUncomposedPlaque(s.toast, title: ScStr.thumbnailLabel, what)
            XCTAssertGreaterThan(lines.count, before.count, "\(what): no line of the module's category in the log")
            for line in lines where !before.contains(line) { XCTAssertFalse(line.contains("/"), "\(what): the line names a path: \(line)") }
        }
    }

    /// The same box on an edit of a shot that was only copied: it has no file, and it was taken as much as a saved one was, so the
    /// plaque is titled as a shot is.
    func testAPictureThatCouldNotBeComposedOnAnEditOfACopiedOnlyShotIsTitledAsAShotIs() async throws {
        let s = try scene()
        let held = try await copiedOnly(s)
        s.press(held)
        await waitUntil("the editor opened on the shot") { s.editors == 1 }
        try require(s.editors == 1, "the editor did not open on the shot")
        let overlay = try XCTUnwrap(s.overlay)
        let area = try XCTUnwrap(overlay.editedArea)
        try onePixelBlur(s, overlay, at: CGPoint(x: area.minX + 100, y: area.minY + 100))
        let (boarded, files) = (s.board.singles, names(s.desktop))

        await leave(s, overlay, by: .confirm)

        XCTAssertEqual(s.board.singles, boarded, "the board took a write for a picture that was never made")
        XCTAssertEqual(names(s.desktop), files, "the folder changed")
        assertTheUncomposedPlaque(s.toast, title: ScStr.thumbnailLabel, "the check mark, an edit of a copied-only shot")
    }

    // MARK: The inputs only a constructed freeze reaches

    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private final class Shutter: ShutterPlaying, @unchecked Sendable { func play() {} }
    private final class OverlayBox { var overlay: CaptureOverlay?; var count = 0 }

    /// A write that waits at a gate and is then refused by the disk: the delivery is in flight for as long as the test holds it.
    private final class GatedRefuser: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var _arrived = 0
        private let gate = DispatchSemaphore(value: 0)
        var arrived: Int { lock.withLock { _arrived } }
        func release() { gate.signal() }
        // A disk that keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { _arrived += 1 }
            gate.wait()
            return .refused(.noPermission)
        }
    }

    /// A controller as the running app builds it, over a freeze whose pictures are `imagePixels` large for frames of 1000 x 800
    /// points at scale 1, a toast with no window, and `writer` for a disk. Torn down with the test.
    private func constructedController(imagePixels: (width: Int, height: Int), writer: ShotWriting) throws
        -> (controller: CaptureController, toast: ShotToast, board: PileBoard, desktop: URL, box: OverlayBox, frames: [FrozenDisplay]) {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: imagePixels.width, height: imagePixels.height, bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: 1, image: try XCTUnwrap(context.makeImage())))
        }
        let home = scratchDirectory("refused-keeps-constructed")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let aside = home.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        let board = PileBoard()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(true, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let session = CaptureSession(capture: PileFrames(Freeze(displays: frames.map { .image($0) }, windows: [])), writer: writer,
                                     trash: AsideTrash(aside), pasteboard: board, preferences: NoPreferences(), shutter: Shutter(),
                                     textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        let box = OverlayBox()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in box.count += 1; box.overlay = overlay; return overlay.build() },
                                           pins: PinBoard(present: { _ in }, screens: { [] }), toast: toast)
        constructed.append((controller, toast))
        return (controller, toast, board, desktop, box, frames)
    }

    /// An area the frozen picture does not hold: the freeze's image is 100 x 80 pixels for a frame of 1000 x 800 points at scale 1,
    /// which no system freeze is, so the area (100, 100) to (700, 500) is wholly outside it (`ScreenSpace.pixels`: nil). Only a
    /// freeze built so reaches this; the real overlay delivers areas on its displays, within them.
    func testAnAreaTheFrozenPictureDoesNotHoldIsSaidToo() async throws {
        let rig = try constructedController(imagePixels: (100, 80), writer: FileShotWriter())
        let (controller, toast, board, desktop, box) = (rig.controller, rig.toast, rig.board, rig.desktop, rig.box)

        controller.begin(.area)
        await waitUntil("the area press reached the overlay") { box.count == 1 }
        try require(box.count == 1, "the area press did not reach the overlay")
        let overlay = try XCTUnwrap(box.overlay)
        let id = try XCTUnwrap(rig.frames.first).id
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 700, y: 500), flags: [])
        overlay.mouseUp(on: id)
        try require(overlay.editedArea == CGRect(x: 100, y: 100, width: 600, height: 400), "the area is not drawn: \(String(describing: overlay.editedArea))")
        HelmLog.shared.clearTail()
        let before = lines

        overlay.perform(.exit(.confirm))
        await waitUntil("the delivery was done") { !controller.isBusy }

        XCTAssertEqual(names(desktop), [], "a file was made")
        XCTAssertEqual(board.singles, 0, "the board took a write")
        XCTAssertNotNil(toast.model.refusal, "no plaque: the picture that could not be composed is not said")
        assertTheUncomposedPlaque(toast, title: ScStr.failedTitle, "an area the frozen picture does not hold")
        XCTAssertGreaterThan(lines.count, before.count, "no line of the module's category in the log")
        for line in lines where !before.contains(line) { XCTAssertFalse(line.contains("/"), "the line names a path: \(line)") }
    }

    // MARK: Inputs the kept shot made reachable

    /// Edit offered on the kept shot, once the plaque is gone: the editor opens on the marked picture the shot holds, not on the
    /// screen, and a save into a folder that now takes the write lands in a file that has the marks, with the kept shot let go and
    /// the file's shot in its place. The folder is unlocked between the two saves, as a person who read the plaque would.
    func testEditOnTheKeptShotOpensOnTheMarkedPictureAndASaveTheFolderNowTakesLandsInAFile() async throws {
        let s = try scene()
        try await markedAndRefused(s, by: .save)
        try require(s.toast.model.shots.count == 1, "the shot is not kept: \(s.toast.model.shots.count) shots")
        let kept = try XCTUnwrap(s.toast.model.shots.first)
        takeThePlaqueAway(s, by: .closeControl)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.desktop.path)

        s.press(kept)
        await waitUntil("the editor opened on the kept shot") { s.editors == 2 }
        try require(s.editors == 2, "Edit on the kept shot did not open the editor")
        let overlay = try XCTUnwrap(s.overlay)
        XCTAssertEqual(overlay.editedArea?.size, Mark.fresh.size, "the editor opened on something other than the kept picture: \(String(describing: overlay.editedArea))")
        XCTAssertTrue(overlay.editedLayers.isEmpty, "the editor opened with layers of its own")

        await leave(s, overlay, by: .save)

        let files = names(s.desktop)
        try require(files.count == 1, "the folder that takes the write does not hold one file: \(files)")
        assertMarked(decoded(file: s.desktop.appendingPathComponent(files[0])), .fresh, "the file the kept picture was saved as")
        XCTAssertNil(s.toast.model.refusal, "a plaque is up over a save that worked")
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the one shot of the file: \(s.toast.model.shots.map { ($0.id, $0.caption as Any) })")
        let saved = s.toast.model.shots.first
        XCTAssertEqual(saved?.caption, ScStr.saved)
        XCTAssertNotNil(saved?.file, "the shot of the file has no file")
        XCTAssertNil(saved?.full, "the shot of the file holds a picture of its own")
        XCTAssertNotEqual(saved?.id, kept.id, "the kept shot was not let go when its picture was saved")
        XCTAssertEqual(s.board.singles, 0, "⌘S copies nothing, and the board took a write")
        XCTAssertEqual(s.trash.asked, [], "something was sent to the Trash for a shot that had no file")
    }

    /// ⌘C in the editor opened on a saved shot, the picture not composed: the shot is back in the window as it was, the board and
    /// the Trash are as they were, and the plaque and the line say it.
    func testCommandCOfASavedShotWhosePictureCouldNotBeComposedGivesTheShotBackAndSaysIt() async throws {
        HelmLog.shared.info(ScreenshotsEngine.moduleID, "probe")
        try require(lines.contains("probe"), "the log is not recording, so an absence proves nothing")
        let s = try scene()
        let saved = try await s.take(width: 400, height: 300)
        s.press(saved)
        await waitUntil("the editor opened on the shot") { s.editors == 1 }
        try require(s.editors == 1, "the editor did not open on the shot")
        let overlay = try XCTUnwrap(s.overlay)
        let area = try XCTUnwrap(overlay.editedArea)
        try onePixelBlur(s, overlay, at: CGPoint(x: area.minX + 100, y: area.minY + 100))
        let (boarded, trashed, files) = (s.board.singles, s.trash.asked, names(s.desktop))
        HelmLog.shared.clearTail()
        let before = lines

        await leave(s, overlay, by: .copy)

        XCTAssertEqual(s.board.singles, boarded, "the board took a write for a picture that was never made")
        XCTAssertEqual(s.trash.asked, trashed, "the original was sent to the Trash")
        XCTAssertEqual(names(s.desktop), files, "the folder changed")
        XCTAssertEqual(s.toast.model.shots.map(\.id), [saved.id], "the saved shot is not back in the window as it was")
        XCTAssertEqual(s.toast.model.shots.first?.file, saved.file)
        XCTAssertNotNil(s.toast.model.refusal, "no plaque: the picture that could not be composed is not said")
        assertTheUncomposedPlaque(s.toast, title: ScStr.thumbnailLabel, "⌘C, an edit of a saved shot")
        XCTAssertGreaterThan(lines.count, before.count, "no line of the module's category in the log")
        for line in lines where !before.contains(line) { XCTAssertFalse(line.contains("/"), "the line names a path: \(line)") }
        takeThePlaqueAway(s, by: .closeControl)
        XCTAssertEqual(s.toast.model.current?.id, saved.id, "the saved shot is not what the window shows once the plaque is gone")
    }

    /// The group is full when a refused delivery arrives: the kept picture is the newest shot, the oldest is pushed out by it as by any
    /// shot, the list stays at its bound; with the thumbnail shown (the working shot is the one that is filled) and not shown (the
    /// kept picture is added).
    func testAKeptPictureArrivingAtTheGroupsBoundIsTheNewestAndPushesOutTheOldest() async throws {
        for thumbnail in [true, false] {
            let s = try scene()
            let what = "thumbnail \(thumbnail ? "on" : "off")"
            s.store.set(thumbnail, for: ScreenshotsSettings.Key.thumbnail)
            for i in 1...ShotShelf.limit { s.toast.showDone(try ShotToastRig.picture(width: 200 + i, height: 100), caption: "filler\(i)", file: nil) }
            try require(s.toast.model.shots.count == ShotShelf.limit, "the group is not full: \(s.toast.model.shots.count)")
            let oldest = try XCTUnwrap(s.toast.model.shots.first).id

            try await markedAndRefused(s, by: .save)

            XCTAssertEqual(s.toast.model.shots.count, ShotShelf.limit, "\(what): the list is not at its bound")
            XCTAssertFalse(s.toast.model.shots.contains { $0.id == oldest }, "\(what): the oldest shot was not pushed out")
            guard let newest = s.toast.model.shots.last else { continue }
            assertIsTheMarkedPictureKept(newest, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                         caption: ScStr.refusal(.write(.noPermission)), "\(what): the newest shot")
            XCTAssertEqual(s.toast.model.shots.dropLast().compactMap(\.caption).filter { $0.hasPrefix("filler") }.count, ShotShelf.limit - 1,
                           "\(what): a filler was replaced by the kept picture")
            takeThePlaqueAway(s, by: .nineSeconds)
            XCTAssertEqual(s.toast.model.current?.id, newest.id, "\(what): the kept picture is not what the window shows")
        }
    }

    /// The check mark when the clipboard and the folder both refuse: the picture is kept all the same, as a shot that is neither
    /// saved nor copied, and the plaque has room for one sentence, which is the first refusal's, the clipboard's (it is asked
    /// before the folder). The folder's refusal is in the log and is not on the plaque.
    func testACheckMarkWhoseClipboardAndFolderBothRefusedKeepsThePictureAndSaysTheFirstRefusal() async throws {
        HelmLog.shared.info(ScreenshotsEngine.moduleID, "probe")
        try require(lines.contains("probe"), "the log is not recording, so an absence proves nothing")
        let s = try scene()
        try lock(s.desktop)
        s.board.accepts = false
        let overlay = try await freshArea(s)
        try markInBlue(s, overlay)
        HelmLog.shared.clearTail()

        await leave(s, overlay, by: .confirm)

        try require(names(s.desktop).isEmpty, "a file was written into the locked folder: \(names(s.desktop))")
        XCTAssertEqual(s.board.singles, 0, "the board took a write it refused")
        guard case .refusal(let title, let body, let offersSettings)? = s.toast.model.refusal else {
            return XCTFail("no plaque after two refusals: \(String(describing: s.toast.model.content))")
        }
        XCTAssertEqual(body, ScStr.refusal(.pasteboard), "the plaque does not say the first refusal")
        XCTAssertNotEqual(title, ScStr.failedTitle, "the plaque over the kept shot says «\(title)»")
        XCTAssertFalse(offersSettings)
        XCTAssertTrue(lines.contains { $0.hasPrefix("save refused") }, "the folder's refusal is not in the log: \(lines)")
        XCTAssertEqual(s.toast.model.shots.count, 1, "the window does not hold the marked picture as a shot")
        guard let shot = s.toast.model.shots.first else { return }
        assertIsTheMarkedPictureKept(shot, .fresh, banned: sentencesOfADeliveryThatWorked(copiedIsOne: true),
                                     caption: body, "both refused")
        takeThePlaqueAway(s, by: .closeControl)
        XCTAssertEqual(s.toast.model.current?.id, shot.id, "the shot is not what the window shows")
    }

    /// The module is switched off while the write waits, and the disk then refuses it: nothing reaches the window, which the switch
    /// emptied. The control is the same delivery left alone, which keeps the picture under a plaque.
    func testARefusedWriteWhoseDeliveryWasCancelledByTheModulesSwitchReachesNoWindow() async throws {
        let picture = try ShotToastRig.picture(width: 600, height: 400)
        for cancelling in [false, true] {
            let disk = GatedRefuser()
            let rig = try constructedController(imagePixels: (1000, 800), writer: disk)
            let what = cancelling ? "cancelled" : "left alone"
            let delivery = Task { await rig.controller.handOff(CapturedShot(image: picture, kind: .area)) }
            await waitUntil("\(what): the write reached the gate") { disk.arrived == 1 }
            try require(disk.arrived == 1, "\(what): the write never reached the gate")
            try require(rig.toast.model.shots.count == 1 && rig.toast.model.shots[0].caption == nil, "\(what): the working shot is not up")
            if cancelling {
                delivery.cancel()
                rig.controller.cancel()
                try require(rig.toast.model.shots.isEmpty, "the switch did not empty the window")
            }

            disk.release()
            await delivery.value

            if cancelling {
                XCTAssertTrue(rig.toast.model.shots.isEmpty, "\(what): a shot reached the window the switch emptied")
                XCTAssertNil(rig.toast.model.refusal, "\(what): a plaque reached the window the switch emptied")
            } else {
                XCTAssertEqual(rig.toast.model.shots.count, 1, "\(what): the control: the refused picture is not kept")
                XCTAssertNotNil(rig.toast.model.refusal, "\(what): the control: no plaque")
            }
        }
    }
}
