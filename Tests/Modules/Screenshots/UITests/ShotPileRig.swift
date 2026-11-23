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

/// A controller as the running app builds it, over real files in a scratch folder, a toast with no window whose clock
/// never steps by itself (a test that passes its own clock steps it), a Trash that is a folder, and an overlay that is built and never ordered in: the group's
/// controls are pressed through the model, as the views press them.
@MainActor
final class PileScene {
    let controller: CaptureController
    let toast: ShotToast
    let board = CountingBoard(groups: true)
    let trash: AsideTrash
    let capture: FakeScreen
    let desktop: URL
    let frames: [FrozenDisplay]
    final class Box { var overlay: CaptureOverlay?; var count = 0 }
    let box = Box()
    let store: NamespacedStore
    var editors: Int { box.count }
    var overlay: CaptureOverlay? { box.overlay }

    /// The defaulted ports are the rig's own fixed ones, named here: `CountingBoard` (`board`), `CountingShutter` and the toast's
    /// never-ticking clock. A test that needs another passes it: `pasteboard` stands in for `board` where a test counts its
    /// own kind of write (then `board` stays unused), `shutter` replaces the silent one, `clock` gives the toast a clock
    /// the test steps.
    init(_ test: XCTestCase, name: String, target: SaveTarget = .desktop, thumbnail: Bool = true,
         pasteboard: (any ShotPasteboard)? = nil, shutter: any ShutterPlaying = CountingShutter(), clock: StepClock? = nil) throws {
        let frames = try OverlayRig.frames(ground: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        self.frames = frames
        let home = test.scratchDirectory(name)
        desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let aside = home.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        trash = AsideTrash(aside)
        capture = FakeScreen(outcome: .frozen(Freeze(displays: frames.map { .image($0) }, windows: [])))
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        self.store = store
        store.set(thumbnail, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let session = CaptureSession(capture: capture, writer: FileShotWriter(), trash: trash, pasteboard: pasteboard ?? board,
                                     preferences: NoPreferences(), shutter: shutter, textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        toast = clock.map(ShotToastRig.toast) ?? ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
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

    /// The text of the refusal the toast is telling, nil where it tells none.
    var refusalBody: String? {
        if case .refusal(_, let body, _)? = toast.model.refusal { body } else { nil }
    }

    /// The width in pixels of a picture written to the board.
    static func width(of png: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil), "a write that is no picture")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    /// The names in a folder, flat and sorted.
    static func names(_ folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }

    func press(_ shot: ShotToastModel.Shot) {
        toast.model.focus = shot.id
        toast.model.edit()
    }

    func draw(_ overlay: CaptureOverlay) {
        let display = display(of: overlay)
        overlay.perform(.tool(.rectangle))
        OverlayRig.drag(overlay, on: display, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 500, y: 450))
    }
}

extension ShotToastModel {
    /// The shot at a place, nil where there is none: a test that indexes a list a defect emptied would trap, and take
    /// every test after it out of the run.
    func shot(_ index: Int) -> Shot? { shots.indices.contains(index) ? shots[index] : nil }
}
