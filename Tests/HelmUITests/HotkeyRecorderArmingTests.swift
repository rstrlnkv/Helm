import XCTest
@testable import HelmUI
import Foundation
import HelmRuntime

/// Two recorders on one page, and nothing stopped the first.
///
/// The keyboard page has carried two since 0.7.1 — "change the last word" and
/// "undo the last change". `startRecording` installs a local key monitor and
/// had no notion of another recorder; a mouse click is not a `keyDown`, so
/// clicking Set on the second row never reached the first monitor. Both stayed
/// armed: one keystroke landed in both, or one monitor sat there swallowing
/// every keypress in the window with nothing on screen to say so.
@MainActor
final class HotkeyRecorderArmingTests: XCTestCase {

    private func recorder(_ prefix: String) -> HelmHotkeyRecorder {
        HelmHotkeyRecorder(
            store: NamespacedStore(namespace: "test.hotkey", backing: UserDefaults.standard),
            prefix: prefix)
    }

    func testArmingOneRecorderDisarmsTheOther() {
        let first = recorder("a"), second = recorder("b")
        first.startRecording()
        XCTAssertTrue(first.recording)

        second.startRecording()
        XCTAssertTrue(second.recording)
        XCTAssertFalse(first.recording, "the first recorder is still armed")
    }

    func testStoppingTheArmedOneLeavesNoneArmed() {
        let only = recorder("c")
        only.startRecording()
        only.stop()
        XCTAssertFalse(only.recording)
        // Arming a second must not resurrect the first.
        let other = recorder("d")
        other.startRecording()
        XCTAssertFalse(only.recording)
        other.stop()
    }

    func testRearmingTheSameRecorderIsHarmless() {
        let one = recorder("e")
        one.startRecording()
        one.startRecording()
        XCTAssertTrue(one.recording)
        one.stop()
        XCTAssertFalse(one.recording)
    }
}
