import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **With its defaults, `CaptureController.handOff` copies the picture under every target and saves it by the save target.** Every
/// pick from the overlay — an area, a window, a whole display by Return — arrives at that one call, the editor's Pin apart. The full-screen
/// shortcut never goes through it.
///
/// The thumbnail is switched off in every store here, because the toast is a real
/// panel and this must not put one on the screen of whoever runs it.
@MainActor
final class TheHandOffCopiesAndSavesTests: XCTestCase {

    private typealias Board = CountingBoard

    private final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var written: Int { lock.withLock { count } }
        // A disk that counts its writes and keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1 }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
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
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { .failed }
    }

    private func controller(saving target: SaveTarget) -> (CaptureController, Board, Disk) {
        let board = Board(), disk = Disk()
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: NeverAsked(), writer: disk, trash: NoTrash(), pasteboard: board, preferences: NoPreferences(), shutter: NoShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(store: store,
                                           session: session)
        return (controller, board, disk)
    }

    func testEveryKindOfPickIsCopiedAndSaved() async throws {
        for kind in [CapturedShot.Kind.area, .window, .display] {
            let (controller, board, disk) = controller(saving: .desktop)
            await controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 20, height: 10), kind: kind))
            XCTAssertEqual(board.copies, 1, "\(kind): the picture was not copied")
            XCTAssertEqual(disk.written, 1, "\(kind): the picture was not saved")
        }
    }

    /// The save target decides the file of an area: the clipboard target makes none, every other makes one. The copy
    /// is made under every target; this is the hand-off's default, which the editor's exits narrow.
    func testTheOneSaveTargetDecidesWhatAnAreaMakes() async throws {
        for target in SaveTarget.allCases {
            let (controller, board, disk) = controller(saving: target)
            await controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 20, height: 10), kind: .area))
            XCTAssertEqual(board.copies, 1, "target \(target): an area was not copied")
            XCTAssertEqual(disk.written, target == .clipboard ? 0 : 1,
                           "target \(target): an area was \(target == .clipboard ? "saved as a file though the target is the clipboard" : "not saved")")
        }
    }
}
