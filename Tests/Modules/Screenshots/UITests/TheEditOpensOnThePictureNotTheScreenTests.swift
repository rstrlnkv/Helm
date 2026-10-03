import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import ImageIO
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Edit» opens the palette on the finished picture, never on the screen under it, and «Done» replaces the file that
/// shot wrote.** The controller is driven as the running app drives it, with the overlay built and never ordered in:
/// a shot is handed off through the real session and the real folder writer, the thumbnail's own Edit is pressed, the
/// overlay is worked by hand, and what is read afterwards is the folder, the Trash (a folder of the test's own), the
/// board and what the thumbnail says. The ground behind the picture is RED, so that a file that carries any of the
/// screen shows it.
///
/// Total failure of the subject prints: a file with the screen's ground in it, an area that leaves the picture, an editor
/// opened on a file that is not the shot's, a second Done that replaces twice, a thumbnail that offers an Edit it could not
/// keep, or a replacement that the person is not told of.
@MainActor
final class TheEditOpensOnThePictureNotTheScreenTests: XCTestCase {

    private final class Board: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var copies: Int { lock.withLock { count } }
        func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1 }; return .accepted }
    }

    /// The Trash as a folder of the test's, which can hold a move at its door.
    private final class AsideTrash: ShotTrashing, @unchecked Sendable {
        let folder: URL
        private let lock = NSLock()
        private var _moved: [URL] = [], _asked: [URL] = []
        private var _holding = false, _failure: NSError?, _after: ((URL) -> Void)?
        private let gate = DispatchSemaphore(value: 0)
        init(_ folder: URL) { self.folder = folder }
        /// Run in the moment between the Trash and the claim, with the path that was moved.
        var after: ((URL) -> Void)? {
            get { lock.withLock { _after } }
            set { lock.withLock { _after = newValue } }
        }
        var moved: [URL] { lock.withLock { _moved } }
        var asked: [URL] { lock.withLock { _asked } }
        var failure: NSError? {
            get { lock.withLock { _failure } }
            set { lock.withLock { _failure = newValue } }
        }
        func hold() { lock.withLock { _holding = true } }
        func release() { lock.withLock { _holding = false }; gate.signal() }
        func trash(_ url: URL) throws {
            lock.withLock { _asked.append(url) }
            if lock.withLock({ _holding }) { gate.wait() }
            if let failure { throw failure }
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(UUID().uuidString))
            lock.withLock { _moved.append(url) }
            after?(url)
        }
    }

    private final class Shutter: ShutterPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var plays: Int { lock.withLock { count } }
        func play() { lock.withLock { count += 1 } }
    }

    /// The freeze, which can be held open: the editor is then still being opened.
    private final class Frames: ScreenCapturing, @unchecked Sendable {
        let freeze: Freeze
        private let lock = NSLock()
        private var count = 0
        private var holding = false
        private var waiting: CheckedContinuation<Void, Never>?
        var freezes: Int { lock.withLock { count } }
        var isHeld: Bool { lock.withLock { waiting != nil } }
        init(_ freeze: Freeze) { self.freeze = freeze }
        func hold() { lock.withLock { holding = true } }
        func release() {
            let next: CheckedContinuation<Void, Never>? = lock.withLock { holding = false; defer { waiting = nil }; return waiting }
            next?.resume()
        }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            lock.withLock { count += 1 }
            if lock.withLock({ holding }) {
                await withCheckedContinuation { continuation in
                    lock.withLock { waiting = continuation }
                }
            }
            return .frozen(freeze)
        }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .gone }
    }

    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }

    private final class Box { var overlay: CaptureOverlay?; var count = 0 }
    private final class Opened { var pickers: [NSSharingServicePicker] = []; var closed: [NSSharingServicePicker] = [] }

    private struct Scene {
        let controller: CaptureController
        let toast: ShotToast
        let board: Board
        let trash: AsideTrash
        let shutter: Shutter
        let capture: Frames
        let box: Box
        let store: NamespacedStore
        let desktop: URL
        let frames: [FrozenDisplay]
        /// The display the editor's picture stands on: the one under the pointer (`CaptureController`), which on a Mac with
        /// two screens is wherever the person's pointer is, so it is asked of the overlay and never assumed to be the first.
        @MainActor func display(of overlay: CaptureOverlay) -> DisplayID { frames.map(\.id).first { overlay.chrome(on: $0) != nil } ?? frames[0].id }
        /// How many displays hold the editor's palette: one.
        @MainActor func palettes(of overlay: CaptureOverlay) -> Int { frames.filter { overlay.chrome(on: $0.id) != nil }.count }
    }

    private let clock = StepClock()
    private var controllers: [CaptureController] = []
    private var stands: [StandInThumbnail] = []

    override func tearDown() {
        AppLanguage.override = nil
        for controller in controllers { controller.teardown() }
        controllers = []
        stands = []
        clock.finish()
        super.tearDown()
    }

    /// One 1000×800-point frame at 1× per real screen, with a red ground.
    private func groundFrames() throws -> [FrozenDisplay] {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
            frames.append(FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: 1, image: try XCTUnwrap(context.makeImage())))
        }
        return frames
    }

    private func scene(target: SaveTarget = .desktop, thumbnail: Bool = true) throws -> Scene {
        let frames = try groundFrames()
        let home = scratchDirectory("edit-ui")
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let aside = home.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        let trash = AsideTrash(aside), board = Board(), shutter = Shutter()
        let capture = Frames(Freeze(displays: frames.map { .image($0) }, windows: []))
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(thumbnail, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let session = CaptureSession(capture: capture, writer: FileShotWriter(), trash: trash, pasteboard: board,
                                     preferences: NoPreferences(), shutter: shutter,
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        let toast = ShotToastRig.toast(clock)
        let box = Box()
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in box.count += 1; box.overlay = overlay; return overlay.build() },
                                           pins: PinBoard(present: { _ in }, screens: { [] }), toast: toast)
        controllers.append(controller)
        return Scene(controller: controller, toast: toast, board: board, trash: trash, shutter: shutter, capture: capture, box: box,
                     store: store, desktop: desktop, frames: frames)
    }

    // MARK: Helpers

    private func take(_ s: Scene, width: Int = 1200, height: Int = 700) async throws -> WrittenShot {
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: width, height: height), kind: .area))
        let shot = try XCTUnwrap(s.toast.model.editSource?.shot, "nothing to edit after a saved shot")
        let written = try XCTUnwrap(image(shot.url), "the shot's file is no picture")
        let read = rgb(written, 3, 3)
        picture = (read.0, read.1, read.2)
        XCTAssertGreaterThan(picture.blue, 150, "the control: the picture is bluish, which neither the red ground nor a blank frame is")
        XCTAssertLessThan(picture.red, 120)
        return shot
    }

    private func openEditor(_ s: Scene, count: Int = 1) async throws -> CaptureOverlay {
        s.toast.model.edit()
        await waitUntil("the editor opened") { s.box.count == count }
        let overlay = try XCTUnwrap(s.box.overlay)
        XCTAssertEqual(s.palettes(of: overlay), 1, "the palette is not up round the picture, on one display")
        return overlay
    }

    private func finish(_ s: Scene, _ overlay: CaptureOverlay, _ exit: EditorExit = .confirm) async {
        overlay.perform(.exit(exit))
        await waitUntil("the edit was delivered") { !s.controller.isBusy }
    }

    private func draw(_ overlay: CaptureOverlay, on display: DisplayID, from: CGPoint = CGPoint(x: 300, y: 300), to: CGPoint = CGPoint(x: 500, y: 450)) {
        overlay.perform(.tool(.rectangle))
        overlay.mouseDown(on: display, at: from, flags: [])
        overlay.mouseDragged(on: display, at: to, flags: [])
        overlay.mouseUp(on: display)
    }

    private func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    private func image(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// A pixel in the image's own colour space: reading it in another converts it.
    private func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    /// What the shot's own file holds as its picture, read before any edit: the colour a pixel of the picture has once the
    /// file has been through the encoder, which is what the edited file is compared with.
    private var picture = (red: 0, green: 0, blue: 0)

    private func isPicture(_ colour: (Int, Int, Int), tolerance: Int = 5) -> Bool {
        abs(colour.0 - picture.red) <= tolerance && abs(colour.1 - picture.green) <= tolerance && abs(colour.2 - picture.blue) <= tolerance
    }

    private func refusal(_ s: Scene) -> (title: String, body: String, offersSettings: Bool)? {
        if case .refusal(let title, let body, let offers)? = s.toast.model.content { (title, body, offers) } else { nil }
    }

    // MARK: Done replaces the file, at the picture's own size, with nothing of the screen in it

    func testDoneReplacesTheFileAtThePicturesOwnSizeWithMarksWhereTheyWereDrawnAndNothingOfTheScreen() async throws {
        let s = try scene()
        let original = try await take(s)
        let name = original.url.lastPathComponent
        XCTAssertEqual(s.shutter.plays, 1)
        let freezesBefore = s.capture.freezes

        let overlay = try await openEditor(s)
        XCTAssertNil(s.toast.model.content, "the thumbnail stayed up under the editor")
        XCTAssertEqual(s.capture.freezes, freezesBefore + 1, "the editor takes a fresh freeze of the screen, once")
        draw(overlay, on: s.display(of: overlay))
        await finish(s, overlay)

        XCTAssertEqual(s.trash.moved, [original.url])
        XCTAssertEqual(names(s.desktop), [name], "one file in the folder, and it is the original's name")
        let file = try XCTUnwrap(image(original.url))
        XCTAssertEqual(file.width, 1200, "a picture reduced to fit the screen was saved at the screen's size")
        XCTAssertEqual(file.height, 700)
        for (x, y) in [(0, 0), (1199, 0), (0, 699), (1199, 699), (600, 5), (5, 350), (1190, 350), (600, 690)] {
            let colour = rgb(file, x, y)
            XCTAssertTrue(isPicture(colour), "pixel (\(x), \(y)) is \(colour): the screen's ground or nothing is in the file, not the picture")
        }
        // The overlay put the picture 108 points down (800 − 583 over two), 1.2 pixels of it to a point: the top edge of
        // the rectangle drawn at y = 300 is at row (300 − 108) × 1.2 = 230.4 of the file, between x = 360 and 600.
        let ink = (150..<320).filter { !isPicture(rgb(file, 480, $0), tolerance: 40) }
        XCTAssertFalse(ink.isEmpty, "the rectangle is not in the file at column 480")
        let top = ink.filter { $0 < 280 }
        XCTAssertEqual(Double(top.reduce(0, +)) / Double(max(top.count, 1)), 230.4, accuracy: 4, "the top edge is not where it was drawn: \(top)")
        XCTAssertTrue(isPicture(rgb(file, 480, 300)), "the inside of the rectangle was drawn over")
        XCTAssertTrue(isPicture(rgb(file, 480, 100)))

        XCTAssertEqual(s.shutter.plays, 1, "an edit played the shutter")
        XCTAssertEqual(s.board.copies, 2, "Return copies the edit as it copies a shot")
        guard case .picture(_, let caption, let shown)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(caption, ScStr.replaced)
        XCTAssertEqual(shown, original.url)
        XCTAssertEqual(s.toast.model.reading, FileShotWriter().reading(of: original.url), "the thumbnail holds the file as it is now")
        XCTAssertNotEqual(s.toast.model.reading, original.reading)
        XCTAssertFalse(s.controller.isBusy)
    }

    /// Return with no mark at all is still a replacement, by the same picture.
    func testDoneWithNoMarkReplacesWithTheSamePictureAndNoGround() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        await finish(s, overlay)
        XCTAssertEqual(s.trash.moved, [original.url])
        let file = try XCTUnwrap(image(original.url))
        XCTAssertEqual(file.width, 400)
        XCTAssertEqual(file.height, 300)
        XCTAssertTrue(isPicture(rgb(file, 0, 0)))
        XCTAssertTrue(isPicture(rgb(file, 399, 299)))
    }

    /// ⌘C on an edit copies it and replaces nothing, and the thumbnail it leaves is a copy's: the picture held, no file.
    /// Editing THAT is the edit of a shot with no file, which saves a new one by the settings and moves nothing.
    func testCopyReplacesNothingAndTheThumbnailItLeavesIsACopysWithNoFileToReplace() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        XCTAssertEqual(s.board.copies, 1)
        var overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        await finish(s, overlay, .copy)
        XCTAssertEqual(s.board.copies, 2)
        XCTAssertEqual(s.trash.asked, [], "⌘C moved the original")
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
        XCTAssertEqual(FileShotWriter().reading(of: original.url), original.reading, "⌘C touched the file")
        let after = try XCTUnwrap(s.toast.model.editSource, "the thumbnail after a copy offers no Edit: \(String(describing: s.toast.model.content))")
        XCTAssertNil(after.shot, "a copy's thumbnail holds the file of the shot it was made from")
        XCTAssertNotNil(after.held)

        overlay = try await openEditor(s, count: 2)
        await finish(s, overlay)
        XCTAssertEqual(s.trash.asked, [], "the edit of a copy replaced a file")
        XCTAssertEqual(names(s.desktop).count, 2, "a new shot beside the original, which is as it was")
        XCTAssertEqual(FileShotWriter().reading(of: original.url), original.reading)
    }

    /// ⌘S replaces the file and copies nothing more.
    func testSaveReplacesAndCopiesNothing() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        await finish(s, overlay, .save)
        XCTAssertEqual(s.board.copies, 1, "⌘S copied")
        XCTAssertEqual(s.trash.moved, [original.url])
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
    }

    // MARK: The editor is on the picture's rectangle and on its display

    func testTheAreaStaysInsideThePictureWhereverTheDragStartsAndEnds() throws {
        let frames = try groundFrames()
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
        let shown = try XCTUnwrap(PictureOnScreen.place(try ShotToastRig.picture(width: 400, height: 300), over: freeze, on: frames[0].id))
        XCTAssertEqual(shown.rect, CGRect(x: 300, y: 250, width: 400, height: 300))
        var results: [OverlayResult] = []
        let overlay = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { results.append($0) }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }
        XCTAssertNotNil(overlay.chrome(on: shown.display), "the editor is not up at once on the picture")
        // A new area dragged from the ground, out past the picture's far corner.
        overlay.mouseDown(on: shown.display, at: CGPoint(x: 20, y: 20), flags: [])
        overlay.mouseDragged(on: shown.display, at: CGPoint(x: 990, y: 790), flags: [])
        overlay.mouseUp(on: shown.display)
        overlay.perform(.exit(.confirm))
        guard case .edited(let display, let local, _, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(display, shown.display)
        XCTAssertTrue(shown.rect.insetBy(dx: -0.001, dy: -0.001).contains(local), "the area \(local) leaves the picture \(shown.rect)")
    }

    func testTheEditorOpensOnTheWholePictureAndReturnTakesItWhole() throws {
        let frames = try groundFrames()
        let shown = try XCTUnwrap(PictureOnScreen.place(try ShotToastRig.picture(width: 400, height: 300),
                                                        over: Freeze(displays: frames.map { .image($0) }, windows: []), on: frames[0].id))
        var results: [OverlayResult] = []
        let overlay = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { results.append($0) }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }
        overlay.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, let exit)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(local, shown.rect)
        XCTAssertTrue(layers.isEmpty)
        XCTAssertEqual(exit, .confirm)
    }

    /// The press on another display is not the picture's: it starts nothing there and the area stays where it was.
    func testADragOnAnotherDisplayStartsNothing() throws {
        let frames = try groundFrames()
        guard frames.count > 1 else { throw XCTSkip("one display: there is no other to press on") }
        let shown = try XCTUnwrap(PictureOnScreen.place(try ShotToastRig.picture(width: 400, height: 300),
                                                        over: Freeze(displays: frames.map { .image($0) }, windows: []), on: frames[0].id))
        var results: [OverlayResult] = []
        let overlay = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { results.append($0) }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }
        overlay.mouseDown(on: frames[1].id, at: CGPoint(x: 50, y: 50), flags: [])
        overlay.mouseDragged(on: frames[1].id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay.mouseUp(on: frames[1].id)
        XCTAssertNotNil(overlay.chrome(on: shown.display), "a press on another display took the editor away from the picture")
        overlay.perform(.exit(.confirm))
        guard case .edited(let display, let local, _, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(display, shown.display)
        XCTAssertEqual(local, shown.rect)
    }

    func testEscapeLeavesTheFileTheThumbnailGoneAndTheControllerFree() async throws {
        let s = try scene()
        let original = try await take(s)
        let overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        // Esc drops the drawing, Esc again leaves.
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                   characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        for _ in 0..<4 where s.controller.isBusy { overlay.keyDown(esc); await grace(0.02) }
        await waitUntil("the editor ended") { !s.controller.isBusy }
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
        XCTAssertEqual(FileShotWriter().reading(of: original.url), original.reading, "leaving the editor touched the file")
        XCTAssertNil(refusal(s), "leaving was told as a refusal")
        XCTAssertEqual(s.board.copies, 1)
    }

    // MARK: Refused at the opening

    func testAFileThatIsNotTheShotAnymoreOpensNoEditorAndSaysSo() async throws {
        for what in ["renamed", "deleted", "appended", "another file under the name"] {
            let s = try scene()
            let original = try await take(s, width: 400, height: 300)
            let freezes = s.capture.freezes
            switch what {
            case "renamed": try FileManager.default.moveItem(at: original.url, to: s.desktop.appendingPathComponent("mine.png"))
            case "deleted": try FileManager.default.removeItem(at: original.url)
            case "appended":
                let handle = try FileHandle(forWritingTo: original.url)
                try handle.seekToEnd(); try handle.write(contentsOf: Data([1])); try handle.close()
            default:
                let other = s.desktop.appendingPathComponent("other.tmp")
                try Data(contentsOf: original.url).write(to: other)
                XCTAssertEqual(rename(other.path, original.url.path), 0)
            }
            s.toast.model.edit()
            await waitUntil("\(what): the refusal was shown") { self.refusal(s) != nil }
            let said = try XCTUnwrap(refusal(s))
            XCTAssertEqual(said.title, ScStr.thumbnailLabel, what)
            XCTAssertEqual(said.body, ScStr.refusal(.notEditable), what)
            XCTAssertFalse(said.offersSettings, what)
            XCTAssertEqual(s.box.count, 0, "\(what): an editor opened on a file that is not the shot's")
            XCTAssertEqual(s.capture.freezes, freezes, "\(what): the screen was frozen for it")
            XCTAssertFalse(s.controller.isBusy, what)
            XCTAssertEqual(s.trash.asked, [], what)
        }
    }

    func testTheSentenceOfTheRefusalIsTranslatedInEveryLanguage() throws {
        AppLanguage.each { language in
            for reason in [CaptureRefusal.notEditable, .notReplaced(.changed), .notReplaced(.missing), .notReplaced(.trash(.noPermission)),
                           .notReplaced(.trash(.outOfScope)), .notReplaced(.trash(.systemRefused))] {
                XCTAssertFalse(ScStr.refusal(reason).isEmpty, "\(language) \(reason)")
            }
            XCTAssertFalse(ScStr.replaced.isEmpty, "\(language)")
            XCTAssertFalse(ScStr.edit.isEmpty, "\(language)")
            if language != .en {
                XCTAssertNotEqual(ScStr.refusal(.notEditable), "The screenshot was moved or changed after it was taken, so it cannot be edited here.", "\(language)")
                XCTAssertNotEqual(ScStr.replaced, "Replaced. The original is in the Trash.", "\(language)")
            }
        }
    }

    // MARK: Refused at Done

    func testAFileRenamedWhileTheEditorWasOpenIsNotReplacedAndTheEditIsSaved() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        try FileManager.default.moveItem(at: original.url, to: s.desktop.appendingPathComponent("mine.png"))
        await finish(s, overlay)
        let said = try XCTUnwrap(refusal(s), "no plaque: \(String(describing: s.toast.model.content))")
        XCTAssertEqual(said.body, ScStr.refusal(.notReplaced(.changed)))
        XCTAssertEqual(said.title, ScStr.thumbnailLabel)
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(names(s.desktop), ["mine.png", original.url.lastPathComponent].sorted())
        XCTAssertEqual(image(s.desktop.appendingPathComponent("mine.png")).map { rgb($0, 0, 0) }.map { isPicture($0) }, true, "the renamed original is the shot")
        XCTAssertFalse(s.controller.isBusy)
    }

    func testTheTrashRefusingIsToldWithItsReasonAndBothFilesStay() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        s.trash.failure = NSError(domain: NSCocoaErrorDomain, code: 513)
        await finish(s, overlay)
        let said = try XCTUnwrap(refusal(s))
        XCTAssertEqual(said.body, ScStr.refusal(.notReplaced(.trash(.noPermission))))
        XCTAssertEqual(said.body, TrashReasonText.sentence("noPermission"))
        XCTAssertEqual(names(s.desktop).count, 2, "the original and the edit beside it")
        XCTAssertTrue(names(s.desktop).contains(original.url.lastPathComponent))
        XCTAssertFalse(s.controller.isBusy)
        XCTAssertNil(s.toast.model.editSource, "a refusal plaque offers an Edit")
    }

    // MARK: Twice

    /// After a replacement the thumbnail holds the NEW reading, so the second edit replaces again; and nothing remains of the first.
    func testASecondEditReplacesAgainFromTheNewReading() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        var overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        await finish(s, overlay)
        let first = try XCTUnwrap(s.toast.model.editSource?.shot, "no Edit on the thumbnail after a replacement")
        XCTAssertEqual(first.url, original.url)
        XCTAssertNotEqual(first.reading.identity, original.reading.identity)

        overlay = try await openEditor(s, count: 2)
        draw(overlay, on: s.display(of: overlay), from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 400))
        await finish(s, overlay)
        XCTAssertEqual(s.trash.moved, [original.url, original.url], "the second Done did not replace")
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
        XCTAssertNil(refusal(s))
        guard case .picture(_, let caption, _)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(caption, ScStr.replaced)
        XCTAssertEqual(s.toast.model.reading, FileShotWriter().reading(of: original.url))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.trash.folder.path).count, 2)
    }

    /// While the first replacement is in the move to the Trash: no Edit is on offer, a press on it is dropped, a new
    /// capture is dropped and the old overlay's Return does nothing: one replacement, once.
    func testASecondDoneWhileTheFirstRunsIsDropped() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        s.trash.hold()
        overlay.perform(.exit(.confirm))
        await waitUntil("the move to the Trash was reached") { !s.trash.asked.isEmpty }
        XCTAssertTrue(s.controller.isBusy)
        XCTAssertNil(s.toast.model.editSource, "an Edit is offered on a thumbnail that is being written")

        let freezes = s.capture.freezes
        s.toast.model.edit()
        s.controller.editFromThumbnail()
        s.controller.begin(.area)
        overlay.perform(.exit(.confirm))
        await grace(0.2)
        XCTAssertEqual(s.box.count, 1, "a second editor or a capture opened while the first edit was being written")
        XCTAssertEqual(s.capture.freezes, freezes, "a second press froze the screen")
        XCTAssertEqual(s.trash.asked, [original.url], "the original was asked for twice")
        XCTAssertTrue(s.controller.isBusy)

        s.trash.release()
        await waitUntil("the replacement ended") { !s.controller.isBusy }
        XCTAssertEqual(s.trash.moved, [original.url])
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
        XCTAssertEqual(s.board.copies, 2, "a second Done copied again")
    }

    /// While the editor is still being opened (the screen is being frozen): a second press of Edit, a capture and a Done
    /// that no one has are all dropped, and one editor opens.
    func testASecondPressWhileTheEditorIsBeingOpenedIsDropped() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        s.capture.hold()
        let freezes = s.capture.freezes
        s.toast.model.edit()
        await waitUntil("the freeze was reached") { s.capture.isHeld }
        XCTAssertTrue(s.controller.isBusy)
        s.toast.model.edit()
        s.controller.editFromThumbnail()
        s.controller.begin(.area)
        await grace(0.1)
        XCTAssertEqual(s.capture.freezes, freezes + 1, "a second press froze the screen again")
        XCTAssertEqual(s.box.count, 0)
        s.capture.release()
        await waitUntil("the editor opened") { s.box.count == 1 }
        await grace(0.1)
        XCTAssertEqual(s.box.count, 1, "two editors opened")
        let overlay = try XCTUnwrap(s.box.overlay)
        await finish(s, overlay)
        XCTAssertEqual(s.trash.moved, [original.url], "one replacement")
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
    }

    /// The module is switched off while the screen is being frozen for the editor: no editor opens afterwards.
    func testTheModuleSwitchedOffWhileTheEditorIsBeingOpenedOpensNothing() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        s.capture.hold()
        s.toast.model.edit()
        await waitUntil("the freeze was reached") { s.capture.isHeld }
        s.controller.cancel()
        s.capture.release()
        await grace(0.2)
        XCTAssertEqual(s.box.count, 0, "an editor opened for a module that was off")
        XCTAssertFalse(s.controller.isBusy)
        XCTAssertEqual(FileShotWriter().reading(of: original.url), original.reading)
        XCTAssertEqual(s.trash.asked, [])
    }

    func testTheModuleSwitchedOffWithTheEditorOpenClosesItAndLeavesTheFile() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        s.controller.cancel()
        XCTAssertFalse(s.controller.isBusy)
        overlay.perform(.exit(.confirm))
        await grace(0.1)
        XCTAssertEqual(s.trash.asked, [], "an editor that was closed replaced a file")
        XCTAssertEqual(FileShotWriter().reading(of: original.url), original.reading)
        XCTAssertEqual(names(s.desktop), [original.url.lastPathComponent])
        XCTAssertNil(s.toast.model.content)
    }

    // MARK: Edit while the Share sheet is open

    func testEditWhileTheShareSheetIsOpenClosesTheSheetAndOpensTheEditor() async throws {
        let s = try scene()
        let opened = Opened()
        s.toast.presentPicker = { picker, _ in opened.pickers.append(picker) }
        s.toast.closePicker = { opened.closed.append($0) }
        let stand = StandInThumbnail()
        stands.append(stand)
        s.toast.model.anchor = stand.view
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400, height: 300), kind: .area), thenShare: true)
        XCTAssertEqual(opened.pickers.count, 1, "the sheet did not open")
        XCTAssertEqual(s.toast.holds, [.sheet])
        let original = try XCTUnwrap(s.toast.model.editSource?.shot)

        let overlay = try await openEditor(s)
        XCTAssertEqual(opened.closed.count, 1, "the sheet stayed open under the editor")
        XCTAssertTrue(opened.closed.first === opened.pickers.first)
        XCTAssertTrue(s.toast.holds.isEmpty)
        await finish(s, overlay)
        XCTAssertEqual(s.trash.moved, [original.url])
    }

    // MARK: A shot with no file

    /// A clipboard-only shot: its Edit holds the picture, «Done» copies and saves nothing a new shot would not,
    /// and no original is moved.
    func testAClipboardOnlyShotEditsAndCopiesAndSavesNoFile() async throws {
        let s = try scene(target: .clipboard)
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400, height: 300), kind: .area))
        let source = try XCTUnwrap(s.toast.model.editSource)
        XCTAssertNil(source.shot, "a shot with no file has no original")
        XCTAssertNotNil(source.held)
        let overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        await finish(s, overlay)
        XCTAssertEqual(s.board.copies, 2)
        XCTAssertEqual(names(s.desktop), [], "the clipboard target made a file")
        XCTAssertEqual(s.trash.asked, [])
        guard case .picture(_, let caption, let file)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertNil(file)
        XCTAssertEqual(caption, ScStr.copied)
        XCTAssertNotNil(s.toast.model.editSource, "the held picture could be edited again")
    }

    /// The setting changed to a folder between the shot and Done: the edit is saved as a new shot by the setting, and
    /// nothing is replaced, since the shot had no file.
    func testAClipboardOnlyShotEditedAfterTheSettingChangedIsSavedAsANewShot() async throws {
        let s = try scene(target: .clipboard)
        await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400, height: 300), kind: .area))
        let overlay = try await openEditor(s)
        s.store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        await finish(s, overlay)
        XCTAssertEqual(names(s.desktop).count, 1, "a new shot")
        XCTAssertEqual(s.trash.asked, [])
        guard case .picture(_, let caption, let file?)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(caption, ScStr.savedAndCopied, "a new shot was told as a replacement")
        XCTAssertEqual(file.deletingLastPathComponent().path, s.desktop.path)
    }

    // MARK: A stranger takes the name between the Trash and the claim

    /// The original is in the Trash, the edit keeps its own "(1)" name, and the person is told what is true: a plain save
    /// (Return saves and copies, so «Saved and copied»; ⌘S alone says «Saved»), never «Replaced». The thumbnail's file is
    /// the "(1)" one with its own reading, so a second Edit replaces "(1)" and the stranger is never touched.
    func testANameTakenBetweenTheTwoStepsIsToldAsASaveAndTheSecondEditReplacesTheEditsFileNotTheStranger() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let stranger = Data("squatter".utf8)
        let overlay = try await openEditor(s)
        draw(overlay, on: s.display(of: overlay))
        s.trash.after = { url in try? stranger.write(to: url) }
        await finish(s, overlay)
        s.trash.after = nil

        XCTAssertNil(refusal(s), "a taken name was told as a refusal")
        guard case .picture(_, let caption, let file?)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(caption, ScStr.savedAndCopied, "a name that was not claimed is told as a plain save")
        XCTAssertNotEqual(caption, ScStr.replaced)
        let beside = s.desktop.appendingPathComponent(original.url.deletingPathExtension().lastPathComponent + " (1).png")
        XCTAssertEqual(file.path, beside.path, "the thumbnail's file is the edit, where it is")
        XCTAssertEqual(try Data(contentsOf: original.url), stranger, "the stranger was written over")
        XCTAssertEqual(s.toast.model.reading, FileShotWriter().reading(of: beside), "the thumbnail holds the edit's own reading")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.trash.folder.path).count, 1, "the original is in the Trash")

        // A second Edit, from this thumbnail.
        let second = try await openEditor(s, count: 2)
        draw(second, on: s.display(of: second), from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 400))
        await finish(s, second)
        XCTAssertEqual(s.trash.moved, [original.url, beside], "the second Edit trashed something that was not its own file")
        XCTAssertEqual(try Data(contentsOf: original.url), stranger, "the stranger was replaced or moved")
        XCTAssertEqual(names(s.desktop).count, 2, "the stranger and the edit under the name that freed: \(names(s.desktop))")
        guard case .picture(_, let again, let shown?)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(again, ScStr.replaced)
        XCTAssertEqual(shown.path, beside.path)
    }

    /// ⌘S alone is «Saved» for that branch.
    func testANameTakenBetweenTheTwoStepsUnderSaveAloneSaysSaved() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        s.trash.after = { url in try? Data("squatter".utf8).write(to: url) }
        await finish(s, overlay, .save)
        guard case .picture(_, let caption, _)? = s.toast.model.content else { return XCTFail("\(String(describing: s.toast.model.content))") }
        XCTAssertEqual(caption, ScStr.saved)
        XCTAssertEqual(s.trash.moved, [original.url])
    }

    // MARK: Show in Finder

    /// The capsule's «Show in Finder» is `HelmReveal.inFinder(file.path)`, which asks `HelmReveal.target(for:)` first (read at
    /// `ShotToastView.reveal`): a file that is there is selected; a file that is gone (moved, renamed or trashed after the
    /// thumbnail was drawn) opens the folder it was in, a folder that is gone shows nothing. Finder itself is not
    /// launched here; the decision is what is asserted, on real files, for the file the replacement leaves.
    func testShowInFinderOnAMovedFileOpensItsFolderAndOnAReplacedOneSelectsIt() async throws {
        let s = try scene()
        let original = try await take(s, width: 400, height: 300)
        let overlay = try await openEditor(s)
        await finish(s, overlay)
        let file = try XCTUnwrap(s.toast.model.editSource?.shot?.url)
        XCTAssertEqual(HelmReveal.target(for: file.path), HelmReveal.Target.select(file), "the replaced file is there and is selected")

        let moved = s.desktop.appendingPathComponent("moved.png")
        try FileManager.default.moveItem(at: file, to: moved)
        let folder = HelmReveal.target(for: file.path)
        XCTAssertEqual(folder, HelmReveal.Target.open(s.desktop), "a moved file opens the folder it was in, and selects nothing")
        XCTAssertEqual(HelmReveal.target(for: moved.path), HelmReveal.Target.select(moved))

        try FileManager.default.removeItem(at: s.desktop)
        XCTAssertNil(HelmReveal.target(for: file.path), "a folder that is gone has nothing to show")
        XCTAssertEqual(original.url, file)
    }

    // MARK: The click on the thumbnail

    func testAClickOnTheThumbnailIsEditAndADragOfItIsNot() throws {
        let image = try ShotToastRig.picture()
        let mounted = ShotToastRig.mount(.picture(image, caption: "x", file: nil))
        var edits = 0
        mounted.model.edit = { edits += 1 }
        let view = try XCTUnwrap(mounted.mount.host.everyView(ofType: ShotDragView.self).first, "no drag view over the thumbnail")
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 10, y: 10)))
        view.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 11, y: 10)))
        XCTAssertEqual(edits, 1, "a click on the thumbnail did not ask for the editor")
        view.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 11, y: 10)))
        XCTAssertEqual(edits, 1, "a release with no press asked for it")
    }
}
