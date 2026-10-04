import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Part 2 replaces the body of `CaptureController.handOff` and nothing else,
/// and until it does the body is this: the picture is copied *and* saved.** Every
/// pick from the overlay — an area, a window, a whole display by Return — arrives
/// at that one call. Whatever «After a full-screen capture» says is for the full-screen shortcut,
/// which never goes through it, so a setting that means «clipboard only» must not
/// leak into the area path and leave the file unwritten.
///
/// The thumbnail is switched off in every store here, because the toast is a real
/// panel and this must not put one on the screen of whoever runs it; its content
/// is `TheRefusalToastOffersSettingsOnlyForAMissingGrantTests`' subject.
@MainActor
final class TheHandOffCopiesAndSavesTests: XCTestCase {

    private final class Board: ShotPasteboard, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var copies: Int { lock.withLock { count } }
        func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1 }; return .accepted }
        func copy(text: String) -> PasteOutcome { .accepted }
    }

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(folder.appendingPathComponent(base + "." + pathExtension))
        }
    }

    private struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }

    private struct NoShutter: ShutterPlaying {
        func play() {}
    }

    /// A grant nobody asks about: a hand-off never freezes anything.
    private struct NeverAsked: ScreenCapturing {
        func access() -> CaptureAccess { .denied }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome { .failed }
        func window(_ id: UInt32, cursor: Bool) async -> WindowShot { .failed }
    }

    private func picture() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func controller(saving target: SaveTarget) -> (CaptureController, Board, Disk) {
        let board = Board(), disk = Disk()
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: NeverAsked(), writer: disk, pasteboard: board, preferences: NoPreferences(), shutter: NoShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store,
                                           session: session)
        return (controller, board, disk)
    }

    func testEveryKindOfPickIsCopiedAndSaved() async throws {
        for kind in [CapturedShot.Kind.area, .window, .display] {
            let (controller, board, disk) = controller(saving: .desktop)
            await controller.handOff(CapturedShot(image: try picture(), kind: kind))
            XCTAssertEqual(board.copies, 1, "\(kind): the picture was not copied")
            XCTAssertEqual(disk.written, 1, "\(kind): the picture was not saved")
        }
    }

    /// One setting decides where a capture goes, and an area follows it like a
    /// screen does: the clipboard target is a copy and no file, every other is a
    /// copy and a file until the editor's own buttons take that over.
    func testTheOneSaveTargetDecidesWhatAnAreaMakes() async throws {
        for target in SaveTarget.allCases {
            let (controller, board, disk) = controller(saving: target)
            await controller.handOff(CapturedShot(image: try picture(), kind: .area))
            XCTAssertEqual(board.copies, 1, "target \(target): an area was not copied")
            XCTAssertEqual(disk.written, target == .clipboard ? 0 : 1,
                           "target \(target): an area was \(target == .clipboard ? "saved as a file though the target is the clipboard" : "not saved")")
        }
    }
}
