import AppKit
import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import SwiftUI
import ImageIO
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The board of a scene that holds a group: it counts every write by the call that made it, one entry a list.
final class PileBoard: ShotPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var _singles = 0
    private var _lists: [[Data]] = []
    private var _accepts = true
    var singles: Int { lock.withLock { _singles } }
    var lists: [[Data]] { lock.withLock { _lists } }
    var accepts: Bool {
        get { lock.withLock { _accepts } }
        set { lock.withLock { _accepts = newValue } }
    }
    func copy(png: Data) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _singles += 1
            return .accepted
        }
    }
    func copy(pngs: [Data]) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _lists.append(pngs)
            return .accepted
        }
    }
    func copy(text: String) -> PasteOutcome { .accepted }
}

/// The Trash as a folder of the test's: what the session moves there is really moved, and listed; it can hold a
/// move at its door, fail it, or run something in the moment after it. Shared by the editor's and the pile's scenes.
final class AsideTrash: ShotTrashing, @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private var _moved: [URL] = [], _asked: [URL] = []
    private var _holding = false
    private let _failure = Locked<NSError?>(nil)
    private let _after = Locked<((URL) -> Void)?>(nil)
    private let gate = DispatchSemaphore(value: 0)
    init(_ folder: URL) { self.folder = folder }
    /// Run in the moment between the Trash and the claim, with the path that was moved.
    var after: ((URL) -> Void)? { get { _after.value } set { _after.value = newValue } }
    var moved: [URL] { lock.withLock { _moved } }
    var asked: [URL] { lock.withLock { _asked } }
    var failure: NSError? { get { _failure.value } set { _failure.value = newValue } }
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

/// The freeze, which can be held open: the editor is then still being opened.
final class PileFrames: ScreenCapturing, @unchecked Sendable {
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
            await withCheckedContinuation { continuation in lock.withLock { waiting = continuation } }
        }
        return .frozen(freeze)
    }
    func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .gone }
}

/// A controller as the running app builds it, over real files in a scratch folder, a toast with no window whose clock
/// never steps by itself, a Trash that is a folder, and an overlay that is built and never ordered in: the group's
/// controls are pressed through the model, as the views press them.
@MainActor
final class PileScene {
    let controller: CaptureController
    let toast: ShotToast
    let board = PileBoard()
    let trash: AsideTrash
    let capture: PileFrames
    let desktop: URL
    let frames: [FrozenDisplay]
    private final class Box { var overlay: CaptureOverlay?; var count = 0 }
    private let box = Box()
    var editors: Int { box.count }
    var overlay: CaptureOverlay? { box.overlay }

    init(_ test: XCTestCase, name: String) throws {
        let frames = try OverlayRig.frames(ground: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        self.frames = frames
        let home = test.scratchDirectory(name)
        desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let aside = home.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        trash = AsideTrash(aside)
        capture = PileFrames(Freeze(displays: frames.map { .image($0) }, windows: []))
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(true, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let session = CaptureSession(capture: capture, writer: FileShotWriter(), trash: trash, pasteboard: board,
                                     preferences: NoPreferences(), shutter: NoShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        let box = box
        controller = CaptureController(store: store, session: session,
                                       presentOverlay: { overlay in box.count += 1; box.overlay = overlay; return overlay.build() },
                                       toast: toast)
        test.addTeardownBlock { @MainActor [self] in teardown() }
    }

    private func teardown() {
        controller.cancel()
        toast.dismiss()
    }

    /// The display the editor's picture stands on: the one under the pointer, which on a Mac with two screens is wherever
    /// the person's pointer is.
    func display(of overlay: CaptureOverlay) -> DisplayID { frames.map(\.id).first { overlay.chrome(on: $0) != nil } ?? frames[0].id }

    /// One more shot, written and shown, whose picture is `width` points wide so that no two files are alike.
    @discardableResult
    func take(width: Int, height: Int = 300) async throws -> ShotToastModel.Shot {
        let before = toast.model.shots.count
        await controller.handOff(try ShotToastRig.picture(width: width, height: height))
        let shot = try XCTUnwrap(toast.model.shots.last, "no shot after a hand-off")
        XCTAssertNotNil(shot.file, "the shot has no file")
        XCTAssertNotNil(shot.reading, "the shot has no reading, so it cannot be edited")
        XCTAssertEqual(toast.model.shots.count, min(before + 1, 20))
        return shot
    }

    func press(_ shot: ShotToastModel.Shot) {
        toast.model.focus = shot.id
        toast.model.edit()
    }

    func draw(_ overlay: CaptureOverlay) {
        let display = display(of: overlay)
        overlay.perform(.tool(.rectangle))
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 500, y: 450), flags: [])
        overlay.mouseUp(on: display)
    }
}

extension ShotToastModel {
    /// The shot at a place, nil where there is none: a test that indexes a list a defect emptied would trap, and take
    /// every test after it out of the run.
    func shot(_ index: Int) -> Shot? { shots.indices.contains(index) ? shots[index] : nil }
}
