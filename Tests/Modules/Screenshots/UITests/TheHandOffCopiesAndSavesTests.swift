import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **With its defaults, `CaptureController.handOff` copies the picture under every target and saves it by the save target.** Every
/// pick from the overlay — an area, a window, a whole display by Return — arrives at that one call. The full-screen
/// shortcut never goes through it.
///
/// The thumbnail is switched off in every store here, because the toast is a real
/// panel and this must not put one on the screen of whoever runs it.
/// Mutant, red here: `Sources/Modules/Screenshots/UI/ScreenshotsCapture.swift`: `let delivery = await session.deliver(shot.image, saves: saves, copies: copies,` -> `let delivery = await session.deliver(shot.image, saves: saves, copies: false,`.
@MainActor
final class TheHandOffCopiesAndSavesTests: XCTestCase {

    private typealias Board = CountingBoard

    private typealias Disk = FakeWorkDisk

    private func controller(saving target: SaveTarget) -> (CaptureController, Board, Disk) {
        let board = Board(), disk = Disk()
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = scratchDirectory("shots-handoff")
        let session = CaptureSession(capture: FakeScreen(outcome: .failed, access: .denied, window: .failed), writer: disk, trash: AsideTrash.refusing(), pasteboard: board, preferences: NoPreferences(), shutter: CountingShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(store: store,
                                           session: session)
        return (controller, board, disk)
    }

    /// The save target decides the file of an area: the clipboard target makes none, every other makes one. The copy
    /// is made under every target; this is the hand-off's default, which the editor's exits narrow.
    func testTheOneSaveTargetDecidesWhatAnAreaMakes() async throws {
        for target in SaveTarget.allCases {
            let (controller, board, disk) = controller(saving: target)
            await controller.handOff(try ShotToastRig.picture(width: 20, height: 10))
            XCTAssertEqual(board.copies, 1, "target \(target): an area was not copied")
            XCTAssertEqual(disk.written, target == .clipboard ? 0 : 1,
                           "target \(target): an area was \(target == .clipboard ? "saved as a file though the target is the clipboard" : "not saved")")
        }
    }
}
