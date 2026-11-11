import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A shortcut the host reports reaches the model's press, by slot, once.**
///
/// The host hands `hotkeyPressed` a slot string; the descriptor must map it to the right press and the model must
/// build its capture session once, at the first of them. Each slot is told apart by what it does on a model over
/// `FakeScreenshotsWork` (the panel raises the bar and freezes nothing; the area freezes and presents the overlay;
/// the full screen freezes and copies), so a descriptor that mapped every slot to one press, or to none, is seen.
/// Nothing is shown and nothing constructs `SCKCapture`.
@MainActor
final class TheShortcutReachesTheModelTests: XCTestCase {

    private func makeScene() throws -> FakeScreenshotsScene {
        FakeScreenshotsScene(screen: FakeScreen(outcome: try FakeScreen.frozen(real: false)))
    }

    /// Fails against a descriptor that maps by position or ignores the slot: some slot has another's effect.
    func testEachSlotReachesItsOwnPress() async throws {
        let hotkeys = ScreenshotsDescriptor.hotkeys
        XCTAssertEqual(hotkeys.count, 3, "the descriptor declares the three shortcuts, or this walks nothing")
        let descriptor = ScreenshotsDescriptor()
        for hotkey in hotkeys {
            let scene = try makeScene()
            descriptor.hotkeyPressed(hotkey, scene.model)
            switch hotkey.slot {
            case ScreenshotsHotkey.panel.slot:
                XCTAssertEqual(scene.barsPresented, 1, "panel: the bar was not raised")
                XCTAssertEqual(scene.work.screen.freezes, 0, "panel: a press that only opens the bar froze the screen")
            case ScreenshotsHotkey.area.slot:
                await waitUntil("area: the overlay was presented") { scene.overlaysPresented == 1 }
                XCTAssertEqual(scene.work.screen.freezes, 1, "area")
                XCTAssertEqual(scene.barsPresented, 0, "area")
            case ScreenshotsHotkey.fullScreen.slot:
                await waitUntil("fullScreen: the screen was copied") { scene.work.board.copies == 1 }
                XCTAssertEqual(scene.work.screen.freezes, 1, "fullScreen")
                XCTAssertEqual(scene.overlaysPresented + scene.barsPresented, 0, "fullScreen")
            default:
                XCTFail("a slot the test does not know: \(hotkey.slot)")
            }
            XCTAssertEqual(scene.work.count("session"), 1, "\(hotkey.slot)")
        }
    }

    /// The control is the test above (a known slot does something on an identical scene); this one asserts the
    /// absence. Fails against a descriptor that falls to a default press for a slot it does not know.
    func testAnUnknownSlotReachesNothing() async throws {
        let scene = try makeScene()
        ScreenshotsDescriptor().hotkeyPressed(ModuleHotkey(slot: "\(ScreenshotsEngine.moduleID).nothing", prefix: "nothing"),
                                              scene.model)
        ScreenshotsDescriptor().hotkeyPressed(ModuleHotkey(slot: "", prefix: ""), scene.model)
        await grace(0.3)
        XCTAssertEqual(scene.work.calls, ["stream"], "an unknown slot reached the engine")
        XCTAssertEqual(scene.controllersBuilt, 0)
        XCTAssertEqual(scene.work.screen.freezes + scene.barsPresented + scene.overlaysPresented, 0)
    }

    /// Fails against a model that builds a session per
    /// press: the engine is asked twice, and the first controller's state is dropped on the floor.
    func testTwoPressesBuildOneSession() async throws {
        let scene = try makeScene()
        let panel = try XCTUnwrap(ScreenshotsDescriptor.hotkeys.first { $0.slot == ScreenshotsHotkey.panel.slot })
        ScreenshotsDescriptor().hotkeyPressed(panel, scene.model)
        XCTAssertEqual(scene.barsPresented, 1, "the control: the first press raised the bar")
        let first = try XCTUnwrap(scene.controller)
        // The bar is closed (Esc), so the second press is not dropped as one made over an open capture.
        first.cancel()
        ScreenshotsDescriptor().hotkeyPressed(panel, scene.model)
        XCTAssertEqual(scene.barsPresented, 2, "the second press was dropped, so it says nothing about the session")
        XCTAssertEqual(scene.work.count("session"), 1, "a session per press")
        XCTAssertEqual(scene.controllersBuilt, 1, "a controller per press")
        XCTAssertTrue(scene.controller === first)
    }
}
