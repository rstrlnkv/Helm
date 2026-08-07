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

    /// In memory. The namespace is fixed, so this one overwrote its own keys
    /// rather than growing — but it still wrote Helm's data into
    /// `com.apple.dt.xctest.tool`, the runner's own domain, which is nobody's
    /// to keep. Both recorders share the store on purpose: the point of the
    /// test is that arming one disarms the other *through* it.
    private func recorder(_ prefix: String, store: NamespacedStore) -> HelmHotkeyRecorder {
        HelmHotkeyRecorder(store: store, prefix: prefix)
    }

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "test.hotkey", backing: InMemoryKeyValueStore())
    }

    func testArmingOneRecorderDisarmsTheOther() {
        let shared = store()
        let first = recorder("a", store: shared), second = recorder("b", store: shared)
        first.startRecording()
        XCTAssertTrue(first.recording)

        second.startRecording()
        XCTAssertTrue(second.recording)
        XCTAssertFalse(first.recording, "the first recorder is still armed")
    }

    func testStoppingTheArmedOneLeavesNoneArmed() {
        // One store for both, because the coordination this asserts on runs
        // *through* it: on separate stores `other` could not reach `only` at
        // all and the assertion below would hold for the wrong reason.
        let shared = store()
        let only = recorder("c", store: shared)
        only.startRecording()
        only.stop()
        XCTAssertFalse(only.recording)
        // Arming a second must not resurrect the first.
        let other = recorder("d", store: shared)
        other.startRecording()
        XCTAssertFalse(only.recording)
        other.stop()
    }

    func testRearmingTheSameRecorderIsHarmless() {
        let one = recorder("e", store: store())
        one.startRecording()
        one.startRecording()
        XCTAssertTrue(one.recording)
        one.stop()
        XCTAssertFalse(one.recording)
    }
}
