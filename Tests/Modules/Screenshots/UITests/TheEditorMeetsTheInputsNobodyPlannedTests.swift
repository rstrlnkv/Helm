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

/// **The editor under the inputs its brief did not name:** a key held down, a tool
/// key under a modifier, the two doors of Esc mixed, every exit pressed after the
/// first, a release with no area, a click on another display, Return mid-stroke, and
/// a module switched off right after an exit. Panels are built and never ordered in.
@MainActor
final class TheEditorMeetsTheInputsNobodyPlannedTests: XCTestCase {

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
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
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
    private final class Shutter: ShutterPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var plays: Int { lock.withLock { count } }
        func play() { lock.withLock { count += 1 } }
    }

    /// One 1000×800-point frame at 1× per real screen, in screen order.
    private func freeze(windows: [FrozenWindow] = []) throws -> (Freeze, [DisplayID]) {
        let frames = try OverlayRig.frames()
        return (Freeze(displays: frames.map { .image($0) }, windows: windows), frames.map(\.id))
    }

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var displays: [DisplayID] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    @discardableResult
    private func build(mode: CaptureOverlay.Mode = .area, windows: [FrozenWindow] = []) throws -> DisplayID {
        let (freeze, ids) = try freeze(windows: windows)
        let built = CaptureOverlay(freeze: freeze, mode: mode) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        displays = ids
        return try XCTUnwrap(ids.first)
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = [],
                     repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: repeating, keyCode: code)!
    }

    private let kA: UInt16 = 0, kR: UInt16 = 15, kC: UInt16 = 8, kS: UInt16 = 1
    private let kReturn: UInt16 = 36, kEsc: UInt16 = 53, kSpace: UInt16 = 49

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

    /// An area with one arrow on it, the tool still in hand.
    private func edited(_ id: DisplayID) {
        select(id)
        overlay?.keyDown(key(kA, "ф"))
        stroke(id)
        XCTAssertEqual(overlay?.view(for: id)?.drawnShapes.count, 1, "no layer was drawn, so the rule below is another one")
    }

    private func onlyEdited(file: StaticString = #filePath, line: UInt = #line) -> [Annotation]? {
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)", file: file, line: line)
        guard case .edited(_, _, let layers, _)? = results.first else {
            XCTFail("not an edited area: \(results)", file: file, line: line)
            return nil
        }
        return layers
    }

    // MARK: A key held down

    /// A held Esc sends its first press and then repeats about every 30–80 ms. The
    /// question exists so that one press over an edited picture does not lose it; a
    /// repeat of that same press is not the second press it asks for.
    func testAHeldEscDoesNotAnswerItsOwnQuestion() throws {
        let id = try build()
        edited(id)
        overlay?.keyDown(key(kEsc))
        XCTAssertEqual(results.count, 0, "the first Esc closed an edited picture")
        overlay?.keyDown(key(kEsc, repeating: true))
        overlay?.keyDown(key(kEsc, repeating: true))
        XCTAssertEqual(results.count, 0, "one held Esc closed an edited picture: the repeat answered the question")
    }

    /// A tool key held a moment too long repeats; the tool must still be in hand afterwards.
    func testAHeldToolKeyLeavesTheToolPicked() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(kA, "ф"))
        overlay?.keyDown(key(kA, "ф", repeating: true))
        stroke(id)
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(onlyEdited()?.map(\.tool), [.arrow], "a repeat of the tool key put the tool down")
    }

    /// A Return or ⌘C held from before — the bar's Return, a copy in another app — repeats
    /// into the editor; only a fresh press leaves.
    func testARepeatedExitKeyDoesNotLeave() throws {
        let id = try build()
        edited(id)
        overlay?.keyDown(key(kReturn, "\r", repeating: true))
        overlay?.keyDown(key(kC, "с", flags: .command, repeating: true))
        overlay?.keyDown(key(kS, "ы", flags: .command, repeating: true))
        XCTAssertEqual(results.count, 0, "a repeated exit key left the editor")
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(onlyEdited()?.count, 1)
    }

    /// A Return held on the bar — its Capture key — repeats into the overlay once the
    /// freeze is up. Before any area exists that repeat is the whole-display gesture,
    /// and a picture the person never chose is taken; in window mode, a display
    /// instead of a window. Only a fresh press may take the whole display.
    func testARepeatedReturnBeforeAnyAreaTakesNothing() throws {
        for mode in [CaptureOverlay.Mode.area, .window] {
            results = []
            let id = try build(mode: mode)
            overlay?.mouseMoved(on: id, at: CGPoint(x: 40, y: 40))
            overlay?.keyDown(key(kReturn, "\r", repeating: true))
            XCTAssertEqual(results.count, 0, "a repeated Return took a picture in \(mode) mode: \(results)")
            overlay?.keyDown(key(kReturn, "\r"))
            guard case .wholeDisplay? = results.last else {
                return XCTFail("a fresh Return in \(mode) mode did not take the display, so the absence above says nothing: \(results)")
            }
            overlay?.close()
        }
    }

    /// The same held Return over a remembered selection: the repeat must not take the
    /// area into the editor, or the next fresh press — meant to enter it — takes the
    /// picture instead. Only fresh presses count: the first enters, the second takes.
    func testARepeatedReturnOverARememberedSelectionDoesNotEnterTheEditor() throws {
        let (freeze, ids) = try freeze()
        let id = try XCTUnwrap(ids.first)
        let rect = CGRect(x: 50, y: 60, width: 400, height: 300)
        let built = CaptureOverlay(freeze: freeze, mode: .area, preselection: (id, rect)) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        XCTAssertEqual(built.preselection?.rect, rect, "the overlay did not open on the remembered area, so nothing below is the case")
        built.keyDown(key(kReturn, "\r", repeating: true))
        built.keyDown(key(kReturn, "\r", repeating: true))
        XCTAssertEqual(built.preselection?.rect, rect, "a repeated Return took the remembered area into the editor")
        built.keyDown(key(kReturn, "\r"))
        XCTAssertNil(built.preselection, "a fresh Return did not take the remembered area into the editor")
        XCTAssertEqual(results.count, 0, "the first fresh Return took the picture: a repeat had already entered the editor")
        built.keyDown(key(kReturn, "\r"))
        guard case .edited(let display, let local, _, _)? = results.first, results.count == 1 else {
            return XCTFail("the second fresh Return did not take the remembered area: \(results)")
        }
        XCTAssertEqual(display, id)
        XCTAssertEqual(local, rect)
    }

    // MARK: Modifiers

    /// ⌘A, ⌥A, ⌃R, ⇧A and the rest are somebody else's shortcuts: no tool. Caps Lock is
    /// not a chord and the Fn flag rides on many keys; A under either is still the arrow.
    func testAToolKeyUnderAModifierPicksNoToolAndCapsLockIsNoModifier() throws {
        let chords: [(UInt16, NSEvent.ModifierFlags)] = [
            (kA, .command), (kA, .option), (kA, .control), (kA, .shift),
            (kR, .command), (kR, .option), (kR, [.command, .shift]),
        ]
        for (code, flags) in chords {
            XCTAssertNil(EditorKeys.action(keyCode: code, flags: flags), "key \(code) with \(flags.rawValue) picked something")
        }
        XCTAssertEqual(EditorKeys.action(keyCode: kA, flags: .capsLock), .tool(.arrow), "Caps Lock read as a chord")
        XCTAssertEqual(EditorKeys.action(keyCode: kR, flags: .function), .tool(.rectangle), "Fn read as a chord")

        let id = try build()
        select(id)
        for (code, flags) in chords { overlay?.keyDown(key(code, "x", flags: flags)) }
        stroke(id)
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(onlyEdited()?.count, 0, "a chord picked a tool in the overlay")
    }

    // MARK: The two doors of Esc

    func testEscThenARightClickAndARightClickThenEscAreOneQuestion() throws {
        for escFirst in [true, false] {
            results = []
            let id = try build()
            edited(id)
            if escFirst { overlay?.keyDown(key(kEsc)) } else { overlay?.rightMouseDown() }
            XCTAssertEqual(results.count, 0, "the first press closed (esc first: \(escFirst))")
            if escFirst { overlay?.rightMouseDown() } else { overlay?.keyDown(key(kEsc)) }
            guard case .cancelled? = results.first, results.count == 1 else {
                return XCTFail("the other door did not answer the question (esc first: \(escFirst)): \(results)")
            }
            overlay?.close()
        }
    }

    /// The question is withdrawn by any input — including a click on a display that is
    /// not the edited one. The overlay covers every screen; a click anywhere is input.
    func testAClickOnAnotherDisplayWithdrawsTheQuestion() throws {
        let id = try build()
        guard displays.count > 1 else { throw XCTSkip("one screen: there is no other display to click on") }
        let other = displays[1]
        edited(id)
        overlay?.keyDown(key(kEsc))
        overlay?.mouseDown(on: other, at: CGPoint(x: 50, y: 50), flags: [])
        overlay?.mouseUp(on: other)
        overlay?.keyDown(key(kEsc))
        XCTAssertEqual(results.count, 0, "a click on another display left the question standing, and Esc closed")
    }

    // MARK: Exactly once

    /// Every way out pressed after the first one, and the screen-change notification
    /// that ends a capture: the overlay finishes once, with the first.
    func testEveryExitAfterTheFirstFindsNothingToFinish() throws {
        let id = try build()
        edited(id)
        overlay?.keyDown(key(kC, "с", flags: .command))
        overlay?.keyDown(key(kReturn, "\r"))
        overlay?.keyDown(key(kS, "ы", flags: .command))
        overlay?.keyDown(key(kEsc))
        overlay?.keyDown(key(kEsc))
        overlay?.rightMouseDown()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(results.count, 1, "the overlay finished more than once: \(results)")
        guard case .edited(_, _, _, .copy)? = results.first else { return XCTFail("the first exit did not win: \(results)") }
    }

    // MARK: No area

    /// A release that never moved, and one that moved along one axis only: neither is
    /// an area, the editor does not open, and Return is the whole display as before.
    func testAReleaseWithNoAreaOpensNoEditor() throws {
        for end in [CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 500), CGPoint(x: 600, y: 200), CGPoint(x: 200.5, y: 200.5)] {
            results = []
            let id = try build()
            overlay?.mouseDown(on: id, at: CGPoint(x: 200, y: 200), flags: [])
            overlay?.mouseDragged(on: id, at: end, flags: [])
            overlay?.mouseUp(on: id)
            XCTAssertEqual(results.count, 0)
            overlay?.keyDown(key(kA, "ф"))
            overlay?.mouseMoved(on: id, at: CGPoint(x: 200, y: 200))
            overlay?.keyDown(key(kReturn, "\r"))
            guard case .wholeDisplay? = results.first, results.count == 1 else {
                return XCTFail("a release ending at \(end) opened an editor: \(results)")
            }
            overlay?.close()
        }
    }

    // MARK: The window and the display

    /// Window mode and Return over nothing finish at the press, with no editor between.
    func testAWindowAndAWholeDisplayFinishAtThePress() throws {
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        let id = try build(mode: .window, windows: [window])
        overlay?.mouseMoved(on: id, at: CGPoint(x: 150, y: 150))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        guard case .window(7)? = results.first, results.count == 1 else { return XCTFail("\(results)") }
        overlay?.close(); results = []

        let display = try build()
        overlay?.mouseMoved(on: display, at: CGPoint(x: 40, y: 40))
        overlay?.keyDown(key(kReturn, "\r"))
        guard case .wholeDisplay? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    /// Space switches the camera while selecting; inside the editor it must not, or a
    /// click meant for the picture becomes a window capture.
    func testSpaceInTheEditorDoesNotTurnTheCameraOnWindows() throws {
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        let id = try build(windows: [window])
        select(id)
        overlay?.keyDown(key(kSpace, " "))
        overlay?.mouseMoved(on: id, at: CGPoint(x: 150, y: 150))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(results.count, 0, "a click in the editor after Space took a window: \(results)")
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertNotNil(onlyEdited())
    }

    // MARK: Mid-stroke

    /// Return while the button is still down: the picture delivered is the one on the
    /// screen, the stroke under the pointer included.
    func testReturnMidStrokeDeliversWhatTheScreenShows() throws {
        let id = try build()
        select(id)
        overlay?.keyDown(key(kA, "ф"))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        let shown = try XCTUnwrap(overlay?.view(for: id)).drawnShapes.count
        XCTAssertEqual(shown, 1, "the stroke under the pointer was not drawn, so the claim below is empty")
        overlay?.keyDown(key(kReturn, "\r"))
        XCTAssertEqual(onlyEdited()?.count, shown, "Return mid-stroke delivered less than the screen showed")
    }

    // MARK: Through the controller

    private func rig(target: SaveTarget, shutter: Shutter = Shutter()) throws
        -> (CaptureController, Board, Disk, Opened, DisplayID) {
        let (freeze, ids) = try freeze()
        let board = Board(), disk = Disk(), opened = Opened()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: Frames(freeze: freeze), writer: disk, trash: NoTrash(), pasteboard: board,
                                     preferences: NoPreferences(), shutter: shutter,
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
        return (controller, board, disk, opened, try XCTUnwrap(ids.first))
    }
    @MainActor private final class Opened { var overlays: [CaptureOverlay] = [] }

    private func editedThroughTheController(_ target: SaveTarget, shutter: Shutter = Shutter()) async throws
        -> (CaptureController, Board, Disk, CaptureOverlay) {
        let (controller, board, disk, opened, first) = try rig(target: target, shutter: shutter)
        controller.begin(.area)
        await waitUntil("the overlay opened") { !opened.overlays.isEmpty }
        let overlay = try XCTUnwrap(opened.overlays.first)
        overlay.mouseDown(on: first, at: CGPoint(x: 100, y: 100), flags: [])
        overlay.mouseDragged(on: first, at: CGPoint(x: 300, y: 250), flags: [])
        overlay.mouseUp(on: first)
        overlay.keyDown(key(kA, "ф"))
        overlay.mouseDown(on: first, at: CGPoint(x: 120, y: 120), flags: [])
        overlay.mouseDragged(on: first, at: CGPoint(x: 250, y: 200), flags: [])
        overlay.mouseUp(on: first)
        return (controller, board, disk, overlay)
    }

    /// One Return, then every other exit on the same overlay: one copy and one file.
    func testOneExitIsOneDeliveryWhateverIsPressedAfter() async throws {
        let (controller, board, disk, overlay) = try await editedThroughTheController(.desktop)
        overlay.keyDown(key(kReturn, "\r"))
        overlay.keyDown(key(kC, "с", flags: .command))
        overlay.keyDown(key(kS, "ы", flags: .command))
        overlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the press ended") { !controller.isBusy }
        await waitUntil("the delivery landed") { board.copies + disk.written >= 2 }
        await grace(0.5)
        XCTAssertEqual(board.copies, 1, "one Return copied more than once")
        XCTAssertEqual(disk.written, 1, "one Return wrote more than one file")
    }

    /// The module switched off in the same turn as the exit: `cancel` promises that work
    /// in flight goes with the module, so nothing is written or copied afterwards. The
    /// control is the same press left alone.
    func testAModuleSwitchedOffRightAfterAnExitDeliversNothing() async throws {
        let (alone, aloneBoard, aloneDisk, aloneOverlay) = try await editedThroughTheController(.desktop)
        aloneOverlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the press left alone was delivered") { aloneBoard.copies + aloneDisk.written == 2 }
        await waitUntil("the press left alone ended") { !alone.isBusy }

        let (controller, board, disk, overlay) = try await editedThroughTheController(.desktop)
        overlay.keyDown(key(kReturn, "\r"))
        // What `ModuleUICache.dropWhenDisabled` does when the switch is turned.
        controller.cancel()
        await grace(0.5)
        XCTAssertEqual(disk.written, 0, "a module switched off right after Return still wrote the file")
        XCTAssertEqual(board.copies, 0, "a module switched off right after Return still took the clipboard")
    }

    /// The shutter is the sound of a picture being taken; a delivery cancelled with the
    /// module makes none. The engine cannot hold it back — the controller plays it before
    /// handing the picture over — so this is the check on the controller's own refusal.
    /// The control is the same press left alone, which sounds once.
    func testAModuleSwitchedOffRightAfterAnExitSoundsNoShutter() async throws {
        let aloneShutter = Shutter()
        let (alone, _, _, aloneOverlay) = try await editedThroughTheController(.desktop, shutter: aloneShutter)
        aloneOverlay.keyDown(key(kReturn, "\r"))
        await waitUntil("the press left alone ended") { !alone.isBusy }
        XCTAssertEqual(aloneShutter.plays, 1, "the press left alone sounded no shutter, so the absence below says nothing")

        let shutter = Shutter()
        let (controller, _, _, overlay) = try await editedThroughTheController(.desktop, shutter: shutter)
        overlay.keyDown(key(kReturn, "\r"))
        controller.cancel()
        await grace(0.5)
        XCTAssertEqual(shutter.plays, 0, "a module switched off right after Return still sounded the shutter")
    }
}
