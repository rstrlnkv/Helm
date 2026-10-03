import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A released area is not the end of the press: the overlay stays and edits it.**
/// The panels are built and never ordered in, driven by hand; every test asserts
/// that the overlay *finished* before it asserts what it finished with.
@MainActor
final class TheEditorTakesTheAreaAfterTheDragTests: XCTestCase {

    private final class Board: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var copies: Int { lock.withLock { count } }
        func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1 }; return .accepted }
    }
    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
    }
    private struct Frames: ScreenCapturing {
        let freeze: Freeze
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .frozen(freeze) }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .gone }
    }
    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    private struct NoShutter: ShutterPlaying { func play() {} }

    /// One 1000×800-point frame at 1× per real screen: the overlay is built over every screen or none.
    private func freeze(windows: [FrozenWindow] = []) throws -> (Freeze, DisplayID) {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number),
                                        frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: 1, image: try XCTUnwrap(context.makeImage())))
        }
        return (Freeze(displays: frames.map { .image($0) }, windows: windows), try XCTUnwrap(frames.first).id)
    }

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func build() throws -> DisplayID {
        let (freeze, first) = try freeze()
        let built = CaptureOverlay(freeze: freeze) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        return first
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private let kA: UInt16 = 0, kR: UInt16 = 15, kZ: UInt16 = 6, kC: UInt16 = 8, kS: UInt16 = 1
    private let kReturn: UInt16 = 36, kEsc: UInt16 = 53

    private func select(_ id: DisplayID, _ rect: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)) {
        overlay?.mouseDown(on: id, at: rect.origin, flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: rect.maxX, y: rect.maxY), flags: [])
        overlay?.mouseUp(on: id)
    }

    private func stroke(_ id: DisplayID, from: CGPoint = CGPoint(x: 150, y: 150), to: CGPoint = CGPoint(x: 300, y: 250)) {
        overlay?.mouseDown(on: id, at: from, flags: [])
        overlay?.mouseDragged(on: id, at: to, flags: [])
        overlay?.mouseUp(on: id)
    }

    private func edited(file: StaticString = #filePath, line: UInt = #line)
        -> (display: DisplayID, local: CGRect, layers: [Annotation], exit: EditorExit)? {
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)", file: file, line: line)
        guard case .edited(let display, let local, let layers, let exit)? = results.first else {
            XCTFail("\(results)", file: file, line: line)
            return nil
        }
        return (display, local, layers, exit)
    }

    // MARK: The phase

    func testAReleaseDoesNotFinishAndReturnTakesTheAreaWithNoLayers() throws {
        let id = try build()
        select(id)
        XCTAssertEqual(results.count, 0, "the release finished the press: there is no editor")
        overlay?.keyDown(key(kReturn, "\r"))
        let done = try XCTUnwrap(edited())
        XCTAssertEqual(done.display, id)
        XCTAssertEqual(done.local, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertTrue(done.layers.isEmpty)
        XCTAssertEqual(done.exit, .confirm)
    }

    func testTheCrosshairAndTheSizePlateAreGoneWhileEditing() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.mouseMoved(on: id, at: CGPoint(x: 300, y: 200))
        XCTAssertFalse(view.visiblePlates.isEmpty, "before the drag the pointer's plate was not there, so its absence below says nothing")
        select(id)
        overlay?.mouseMoved(on: id, at: CGPoint(x: 320, y: 220))
        XCTAssertTrue(view.visiblePlates.isEmpty, "a plate stayed up over the editor")
    }

    func testTheKeyIsTheKeyCodeAndNotTheCharacter() throws {
        let id = try build()
        select(id)
        // The A key on a Russian layout: character "ф", key code 0.
        overlay?.keyDown(key(kA, "ф"))
        stroke(id)
        overlay?.keyDown(key(kR, "к"))
        stroke(id, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 350, y: 300))
        XCTAssertEqual(try XCTUnwrap(overlay?.view(for: id)).drawnShapes.count, 2, "the editor does not show what it holds")
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(try XCTUnwrap(edited()).layers.map(\.tool), [.arrow, .rectangle])
    }

    /// P, L, O and H on a Russian layout make з, д, щ and р: the code names the tool.
    func testPencilLineEllipseAndMarkerAreKeyCodesOnARussianLayout() throws {
        let id = try build()
        select(id)
        let keys: [(UInt16, String, AnnotationTool)] = [(35, "з", .pencil), (37, "д", .line), (31, "щ", .ellipse), (4, "р", .highlighter)]
        for (index, (code, character, _)) in keys.enumerated() {
            overlay?.keyDown(key(code, character))
            stroke(id, from: CGPoint(x: 150, y: 150 + 20 * index), to: CGPoint(x: 300, y: 250 + 10 * index))
        }
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(try XCTUnwrap(edited()).layers.map(\.tool), keys.map(\.2))
    }

    /// ⇧ is read off each event: down for one drag event, up for the next, and the
    /// shape follows the pointer again; a flags change with the pointer still reshapes.
    func testShiftPressedAndReleasedMidDragIsReadFromEachEvent() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(37, "д"))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 160), flags: .shift)
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 160), flags: [])
        overlay?.mouseUp(on: id)
        overlay?.keyDown(key(37, "д"))
        overlay?.keyDown(key(37, "д"))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 250), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.flagsChanged(.shift)
        overlay?.mouseUp(on: id)
        overlay?.keyDown(key(kReturn, "\r"))
        let layers = try XCTUnwrap(edited()).layers
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[0].end, CGPoint(x: 300, y: 160), "⇧ released before the last event was still applied")
        XCTAssertEqual(layers[1].end.y, 250, accuracy: 0.001, "⇧ pressed with the pointer still did not snap the line")
    }

    func testTheCharacterWithTheWrongKeyCodePicksNothing() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(12, "a")) // the Q key, typing an "a": a character, not the A key
        stroke(id)
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertTrue(try XCTUnwrap(edited()).layers.isEmpty, "a tool was picked by a character")
    }

    func testUndoAndRedoByKeyCode() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(kA, "ф"))
        stroke(id)
        overlay?.keyDown(key(kZ, "я", flags: .command))
        XCTAssertEqual(try XCTUnwrap(overlay?.view(for: id)).drawnShapes.count, 0, "⌘Z on a Russian layout did not undo")
        overlay?.keyDown(key(kZ, "я", flags: [.command, .shift]))
        XCTAssertEqual(try XCTUnwrap(overlay?.view(for: id)).drawnShapes.count, 1, "⇧⌘Z did not redo")
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(try XCTUnwrap(edited()).layers.count, 1)
    }

    func testTheExitsAreOneEachAndFinishOnce() throws {
        for (code, chars, expected) in [(kC, "с", EditorExit.copy), (kS, "ы", .save), (kReturn, "\r", .confirm)] {
            results = []
            let id = try build()
            select(id)
            overlay?.keyDown(key(code, chars, flags: code == kReturn ? [] : .command))
            overlay?.keyDown(key(kReturn, "\r"))
            XCTAssertEqual(try XCTUnwrap(edited()).exit, expected)
            overlay?.close()
        }
    }

    // MARK: Selecting again

    func testWithNoToolAndNoLayersADragSelectsAgainAndAClickKeepsTheArea() throws {
        let id = try build()
        select(id)
        overlay?.mouseDown(on: id, at: CGPoint(x: 600, y: 600), flags: [])
        overlay?.mouseUp(on: id)
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(try XCTUnwrap(edited()).local, CGRect(x: 100, y: 100, width: 400, height: 300),
                       "a click that never moved threw the area away")
        overlay?.close(); results = []
        let again = try build()
        select(again)
        select(again, CGRect(x: 50, y: 60, width: 100, height: 80))
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(try XCTUnwrap(edited()).local, CGRect(x: 50, y: 60, width: 100, height: 80))
    }

    func testOnceThereIsALayerADragDoesNotSelectAgain() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(kR, "к"))
        stroke(id)
        overlay?.keyDown(key(kR, "к")) // the same key puts the tool down
        stroke(id, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 90))
        overlay?.keyDown(key(kReturn, "\r"))
        let done = try XCTUnwrap(edited())
        XCTAssertEqual(done.local, CGRect(x: 100, y: 100, width: 400, height: 300), "a drag over layers replaced the area")
        XCTAssertEqual(done.layers.count, 1)
    }

    // MARK: Esc and the right click

    func testEscWithNoLayersClosesAtOnceAsItAlwaysDid() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(kEsc))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    func testEscWithLayersAsksAndASecondCloses() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        select(id)
        overlay?.keyDown(key(kA, "ф")); stroke(id)
        overlay?.keyDown(key(kEsc))
        XCTAssertEqual(results.count, 0, "one Esc over an edited picture closed it")
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.confirmClose])
        overlay?.keyDown(key(kEsc))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    /// The question has no timeout: the plate is still up after the pointer has moved
    /// about, and the right click, the same door, closes at the first press that follows.
    func testTheQuestionStaysUpAndTheRightClickIsTheSameDoor() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        select(id)
        overlay?.keyDown(key(kA, "ф")); stroke(id)
        overlay?.keyDown(key(kEsc))
        overlay?.mouseMoved(on: id, at: CGPoint(x: 320, y: 220))
        XCTAssertEqual(results.count, 0, "a pointer move answered the question")
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.confirmClose], "a pointer move withdrew the plate")
        overlay?.rightMouseDown()
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    /// The plate follows the pointer at the other plates' offset (+14, -26 from it) and
    /// not the selection's bottom edge; moving the pointer moves it.
    func testTheEscPlateSitsAtThePointerAndFollowsIt() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        select(id)
        overlay?.keyDown(key(kA, "ф")); stroke(id)
        overlay?.mouseMoved(on: id, at: CGPoint(x: 200, y: 200))
        overlay?.keyDown(key(kEsc))
        let first = try XCTUnwrap(view.visiblePlates.first).frame
        overlay?.mouseMoved(on: id, at: CGPoint(x: 300, y: 250))
        let second = try XCTUnwrap(view.visiblePlates.first).frame
        XCTAssertEqual(first.minX, 214, accuracy: 1, "the plate is not at the pointer's offset")
        XCTAssertEqual(second.minX - first.minX, 100, accuracy: 1, "the plate did not follow the pointer across")
        XCTAssertEqual(first.minY - second.minY, 50, accuracy: 1, "the plate did not follow the pointer down")
    }

    func testAnyOtherInputWithdrawsTheQuestionAndUndoBackToEmptyClosesAtOnce() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        select(id)
        overlay?.keyDown(key(kA, "ф")); stroke(id)
        overlay?.keyDown(key(kEsc))
        overlay?.keyDown(key(kA, "ф")) // any other key
        XCTAssertTrue(view.visiblePlates.isEmpty, "the plate stayed up after another key")
        overlay?.keyDown(key(kEsc))
        XCTAssertEqual(results.count, 0, "the question was not asked again after being withdrawn")
        overlay?.keyDown(key(kZ, "я", flags: .command))
        overlay?.keyDown(key(kEsc))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    // MARK: Through the controller

    private struct Rig {
        let controller: CaptureController
        let board: Board
        let disk: Disk
        let opened: [CaptureOverlay]
        let first: DisplayID
    }
    @MainActor private final class Opened { var overlays: [CaptureOverlay] = [] }

    private func rig(target: SaveTarget, windows: [FrozenWindow] = []) throws -> (CaptureController, Board, Disk, Opened, DisplayID) {
        let (freeze, first) = try freeze(windows: windows)
        let board = Board(), disk = Disk(), opened = Opened()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, pasteboard: board,
                                     preferences: NoPreferences(), shutter: NoShutter(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session,
                                           presentOverlay: { overlay in
                                               let built = overlay.build()
                                               if built { opened.overlays.append(overlay) }
                                               return built
                                           },
                                           presentBar: { _ in })
        return (controller, board, disk, opened, first)
    }

    private func press(_ controller: CaptureController, _ opened: Opened) async throws -> CaptureOverlay {
        controller.begin(.area)
        await waitUntil("the overlay opened") { !opened.overlays.isEmpty }
        return try XCTUnwrap(opened.overlays.first)
    }

    private func drag(_ overlay: CaptureOverlay, _ id: DisplayID) {
        overlay.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: id)
    }

    /// What each exit does with the picture, under each target: Return as the hand-off always did,
    /// the copy key only the clipboard, the save key only a file — and under the clipboard target
    /// the save key still writes one.
    func testEachExitDeliversWhatItSays() async throws {
        let cases: [(SaveTarget, UInt16, String, NSEvent.ModifierFlags, copies: Int, files: Int)] = [
            (.desktop, kReturn, "\r", [], 1, 1), (.clipboard, kReturn, "\r", [], 1, 0),
            (.desktop, kC, "с", .command, 1, 0), (.desktop, kS, "ы", .command, 0, 1),
            (.clipboard, kS, "ы", .command, 0, 1), (.clipboard, kC, "с", .command, 1, 0),
        ]
        for (target, code, chars, flags, copies, files) in cases {
            let (controller, board, disk, opened, first) = try rig(target: target)
            let overlay = try await press(controller, opened)
            drag(overlay, first)
            overlay.keyDown(key(kA, "ф"))
            overlay.mouseDown(on: first, at: CGPoint(x: 120, y: 120), flags: [])
            overlay.mouseDragged(on: first, at: CGPoint(x: 250, y: 200), flags: [])
            overlay.mouseUp(on: first)
            overlay.keyDown(key(code, chars, flags: flags))
            await waitUntil("the press ended (\(target), \(code))") { !controller.isBusy }
            XCTAssertEqual(board.copies, copies, "\(target) key \(code): copies")
            XCTAssertEqual(disk.written, files, "\(target) key \(code): files")
        }
    }

    func testCancelWhileEditingDeliversNothing() async throws {
        let (controller, board, disk, opened, first) = try rig(target: .desktop)
        let overlay = try await press(controller, opened)
        drag(overlay, first)
        overlay.keyDown(key(kA, "ф"))
        overlay.mouseDown(on: first, at: CGPoint(x: 120, y: 120), flags: [])
        overlay.mouseDragged(on: first, at: CGPoint(x: 250, y: 200), flags: [])
        overlay.mouseUp(on: first)
        controller.cancel()
        XCTAssertFalse(controller.isBusy)
        // A sleep and not a yield: a yield buys a turn and no time. The control is
        // `testEachExitDeliversWhatItSays`, which sees the same press deliver.
        await grace(0.5)
        XCTAssertEqual(board.copies + disk.written, 0, "a cancelled editor delivered a picture")
    }

    /// ⌘Z, ⇧⌘Z and ⌘C sent to the panel with `sendEvent`, the window's own entry for a key down:
    /// nothing in the panel or its view takes a chord before `keyDown`, so no override is needed.
    /// The application's main menu runs before the window and is not part of this headless test.
    func testCommandChordsReachTheEditorThroughTheWindowsOwnPath() throws {
        let id = try build()
        anAreaWithAnArrow(id)
        let view = try XCTUnwrap(overlay?.view(for: id))
        let window = try XCTUnwrap(view.window)
        window.makeFirstResponder(view)
        func chord(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: chars,
                             charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        window.sendEvent(chord(kZ, "я", .command))
        XCTAssertEqual(view.drawnShapes.count, 0, "⌘Z sent to the panel did not undo")
        window.sendEvent(chord(kZ, "я", [.command, .shift]))
        XCTAssertEqual(view.drawnShapes.count, 1, "⇧⌘Z sent to the panel did not redo")
        XCTAssertEqual(results.count, 0)
        window.sendEvent(chord(kC, "с", .command))
        guard case .edited(_, _, let layers, .copy)? = results.first, results.count == 1 else {
            return XCTFail("⌘C sent to the panel did not leave with a copy: \(results)")
        }
        XCTAssertEqual(layers.count, 1)
    }

    /// An area with one arrow on it.
    private func anAreaWithAnArrow(_ id: DisplayID) {
        select(id)
        overlay?.keyDown(key(kA, "ф"))
        stroke(id)
    }

    func testAWindowAndAWholeDisplayStillReachTheHandOff() async throws {
        // Return with nothing selected: the whole display.
        let (controller, board, disk, opened, first) = try rig(target: .desktop)
        let overlay = try await press(controller, opened)
        overlay.mouseMoved(on: first, at: CGPoint(x: 40, y: 40))
        overlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the display press ended") { !controller.isBusy }
        XCTAssertEqual(board.copies, 1)
        XCTAssertEqual(disk.written, 1)

        // Space, then a click on a window the freeze knows: cut from the freeze, copied and saved.
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        let (windowController, windowBoard, windowDisk, windowOpened, id) = try rig(target: .desktop, windows: [window])
        let over = try await press(windowController, windowOpened)
        over.keyDown(key(49))
        over.mouseMoved(on: id, at: CGPoint(x: 150, y: 150))
        over.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        await waitUntil("the window press ended") { !windowController.isBusy }
        XCTAssertEqual(windowBoard.copies, 1)
        XCTAssertEqual(windowDisk.written, 1)
    }
}
