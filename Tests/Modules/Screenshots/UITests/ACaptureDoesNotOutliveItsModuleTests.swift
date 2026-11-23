import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A capture the module was switched off under does nothing afterwards.**
///
/// The freeze is the one long wait in a capture — some hundred milliseconds of
/// ScreenCaptureKit on three displays — and the module's switch can be turned
/// in it. The model's `stop()` then calls `CaptureController.cancel`, which cancels the press and
/// closes an overlay that does not exist yet, and the model lets the controller go;
/// the task that was waiting on the freeze still holds the controller and
/// resumes. On the area shortcut what it resumes into is `CaptureOverlay.present` — panels
/// above the menu bar on every screen, owned by a controller nobody holds, for
/// a module that is off. That path cannot be shown here without putting the
/// overlay on the screen of whoever runs the suite, so this reads the same
/// resumption on the full-screen shortcut, where what it resumes into is a file and the clipboard.
///
/// The freeze is held open by a gate, because a fake that answers at once is
/// over before the switch can be turned.
///
/// Mutant, red here: `cancel` skips the press task's cancel.
@MainActor
final class ACaptureDoesNotOutliveItsModuleTests: XCTestCase {

    private typealias Disk = FakeWorkDisk

    private typealias Board = CountingBoard

    /// The thumbnail is off, so no toast is put on anybody's screen.
    private func rig(_ target: SaveTarget, realScreens: Bool = false,
                     presenting: @escaping (CaptureOverlay) -> Bool = { _ in false })
        throws -> (CaptureController, PromptGate, Disk, Board) {
        let gate = PromptGate(), disk = Disk(), board = Board()
        let capture = FakeScreen(outcome: try FakeScreen.frozen(real: realScreens), gate: gate)
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: capture, writer: disk, trash: NoTrash(), pasteboard: board, preferences: NoPreferences(), shutter: NoShutter(), textReader: NoTextReader(),
                                     settings: { ScreenshotsSettings.read(store) }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(store: store,
                                           session: session, presentOverlay: presenting)
        return (controller, gate, disk, board)
    }

    /// The control: the same press, nobody touching the switch, is a file under a
    /// file target and a copy under the clipboard — each of the two outcomes the
    /// cancelled press below must not reach.
    func testAPressLeftAloneIsDelivered() async throws {
        for target in [SaveTarget.desktop, .clipboard] {
            let (controller, gate, disk, board) = try rig(target)
            controller.begin(.fullScreen)
            await gate.reached()
            await gate.open()
            await waitUntil("the press became its file or its copy under \(target)") {
                disk.written + board.copies == 1
            }
            XCTAssertEqual(disk.written, target == .clipboard ? 0 : 1, "\(target)")
            XCTAssertEqual(board.copies, target == .clipboard ? 1 : 0, "\(target)")
        }
    }

    func testAPressWhoseModuleWentOffMidFreezeWritesAndCopiesNothing() async throws {
        for target in [SaveTarget.desktop, .clipboard] {
            let (controller, gate, disk, board) = try rig(target)
            controller.begin(.fullScreen)
            await gate.reached()
            // What the model's `stop()` calls when the switch is turned.
            controller.cancel()
            await gate.open()
            await grace(0.5)
            XCTAssertEqual(disk.written, 0,
                           "a capture of a module switched off during its freeze still wrote a file afterwards (\(target))")
            XCTAssertEqual(board.copies, 0,
                           "a capture of a module switched off during its freeze still took the clipboard afterwards (\(target))")
        }
    }

    /// The area shortcut: the freeze is the same wait, and what it resumes into is the overlay.
    /// The presentation is counted and declined, so no panel reaches a screen; the
    /// control first, because an absence is only worth something beside the same
    /// press that did present.
    func testAnAreaPressLeftAloneReachesTheOverlay() async throws {
        let presented = LockedCount()
        let (controller, gate, _, _) = try rig(.desktop, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await gate.reached()
        await gate.open()
        await waitUntil("the area press reached the overlay") { presented.value == 1 }
    }

    func testAnAreaPressWhoseModuleWentOffMidFreezeShowsNoOverlay() async throws {
        let presented = LockedCount()
        let (controller, gate, _, _) = try rig(.desktop, presenting: { _ in presented.bump(); return false })
        controller.begin(.area)
        await gate.reached()
        controller.cancel()
        await gate.open()
        await grace(0.5)
        XCTAssertEqual(presented.value, 0,
                       "a module switched off during the freeze still put the area-shortcut overlay on every screen")
    }

    /// The overlay is held through the presentation seam (built, never shown), a shot is taken and the module
    /// goes off while the overlay waits for its flash: the panels must be gone at once, not when the timer
    /// finds them. The control is the same shot left alone, which is still open and leaving right after it.
    func testTheModuleGoingOffDuringTheFlashClosesTheOverlayAtOnce() async throws {
        for cancelled in [false, true] {
            let held = PanelRig.Held()
            let (controller, gate, _, _) = try rig(.clipboard, realScreens: true, presenting: { overlay in
                overlay.reducesMotion = { false }
                held.overlay = overlay
                return overlay.build()
            })
            controller.begin(.area)
            await gate.reached()
            await gate.open()
            await waitUntil("the overlay reached the seam") { held.overlay != nil }
            let overlay = try XCTUnwrap(held.overlay)
            let display = try XCTUnwrap(try OverlayRig.frames().first?.id)
            OverlayRig.drag(overlay, on: display, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
            overlay.perform(.exit(.confirm))
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "the subject: the shot is flashing (\(cancelled))")
            if cancelled {
                controller.cancel()
                XCTAssertFalse(overlay.isOpen, "the module went off in the flash and the panels stayed up")
                XCTAssertFalse(overlay.leaving)
            } else {
                XCTAssertTrue(overlay.isOpen, "the control: left alone it is open until the flash is over")
                await waitUntil("the flash ended by itself") { !overlay.isOpen }
            }
            overlay.close()
        }
    }

}
