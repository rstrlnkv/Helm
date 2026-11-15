import XCTest
import CoreGraphics
@testable import Module_Layout_Engine

/// Keystrokes the engine itself sends while converting are not typing.
///
/// Defect class kept: the engine reading its own output back and converting it
/// again, typing over the person's text a second time (data overwritten; REQUIRED
/// in ARCHITECTURE.md § What proves what).
///
/// Every `perform` runs on main and only posts, so the echo reaches the tap after
/// main is back in its run loop, so a flag set around `perform` would always be
/// down by then: the marker on every event Helm builds, dropped in `CGKeyTap.deliver`,
/// is the only guard. It is tested as a pair, what Helm builds
/// (`SynthesisTyping.events(for:)`) and what the tap drops (`deliver`), because
/// `deliver` alone fed a hand-marked event would stay green with the setter
/// deleted. The events are built and NEVER posted; `install` creates no tap.
final class HelmsOwnKeystrokesAreNotReadAsTypingTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var typed: [TypingBuffer.Event] = []
        private var modifiers = 0
        var events: [TypingBuffer.Event] { lock.withLock { typed } }
        var modifierInputs: Int { lock.withLock { modifiers } }
        func add(_ event: TypingBuffer.Event) { lock.withLock { typed.append(event) } }
        func addModifier() { lock.withLock { modifiers += 1 } }
    }

    func testAnEventHelmBuiltNeverReachesTheHandlers() throws {
        let plan = try XCTUnwrap(SwitchPlan.make(replacing: "g", with: "п"))
        let events = try XCTUnwrap(SynthesisTyping.events(for: plan))
        XCTAssertFalse(events.isEmpty, "the plan built no events")

        let recorder = Recorder()
        let tap = CGKeyTap()
        tap.install({ recorder.add($0) }, onModifier: { _ in recorder.addModifier() }, died: {})

        for event in events { tap.deliver(event) }
        XCTAssertEqual(recorder.events, [], "the tap handed the engine its own keystrokes")
        XCTAssertEqual(recorder.modifierInputs, 0,
                       "the modifier machine heard Helm's own keystrokes")

        // Control: the same events with the marker taken off are typing. This
        // proves the handlers record and that the marker is the one difference.
        for event in events {
            guard let copy = event.copy() else { return XCTFail("an event could not be copied") }
            copy.setIntegerValueField(.eventSourceUserData, value: 0)
            tap.deliver(copy)
        }
        XCTAssertTrue(recorder.events.contains(.character("п")),
                      "control: an unmarked copy was not heard as typing: \(recorder.events)")
        XCTAssertTrue(recorder.events.contains(.backspace),
                      "control: an unmarked delete was not heard: \(recorder.events)")
    }
}
