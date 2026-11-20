import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// A pad that stops sending frames in the middle of a scrub (a Bluetooth drop) has no lift to end it: after `silenceLimit` the engine
/// reverts the scrub itself, once, and what the pad sends after is dropped, since it no longer owns a scrub.
final class APadThatFallsSilentInAScrubEndsItTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [PinchEvent] = []
        func add(_ e: PinchEvent) { lock.withLock { all.append(e) } }
        var list: [PinchEvent] { lock.withLock { all } }
    }

    private let clock = Locked<Double>(0)
    private func engine(_ port: FakeTouchPort) -> LaunchpadEngine {
        let clock = self.clock
        return LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("pinch-silence")),
                               touches: port, pinchEnabled: { true }, now: { clock.withLock { $0 } })
    }
    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    private func ended(_ events: [PinchEvent]) -> [PinchEvent] { events.filter { if case .ended = $0 { true } else { false } } }

    func testAScrubWhoseFramesStopDeliversExactlyOneRevertAndTheRestOfTheHandSaysNothing() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let frames = Hand.completedPinch()
        frames[..<20].forEach(port.send)
        drain()
        guard case .began? = heard.list.first else { return XCTFail("the subject: a scrub must have begun: \(heard.list)") }
        clock.withLock { $0 = LaunchpadEngine.silenceLimit - 0.1 }
        engine.checkSilence()
        drain()
        XCTAssertTrue(ended(heard.list).isEmpty, "too early: \(heard.list)")
        clock.withLock { $0 = LaunchpadEngine.silenceLimit + 0.1 }
        engine.checkSilence()
        engine.checkSilence()
        drain()
        XCTAssertEqual(ended(heard.list), [.ended(.revert)], "\(heard.list)")
        // The pad comes back mid-hand: nothing until a lift.
        frames[20...].dropLast().forEach(port.send)
        drain()
        XCTAssertEqual(ended(heard.list).count, 1, "\(heard.list)")
    }

    func testAScrubWhoseFramesKeepComingIsNotEnded() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let frames = Hand.completedPinch()
        frames[..<20].forEach(port.send)
        clock.withLock { $0 = 10 }
        frames[20..<22].forEach(port.send)
        engine.checkSilence()
        drain()
        XCTAssertTrue(ended(heard.list).isEmpty, "\(heard.list)")
    }
}
