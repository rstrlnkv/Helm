import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine

/// Main is told of a scrub's `began` and must be told of its `ended` (`Architecture/Launchpad.md` § The trackpad pinch: "A scrub that main
/// was told began is always told it ended"). The mailbox holds what main has not yet heard; a watch that stops while main is busy must keep
/// every end of a scrub main did hear began.
final class AScrubMainWasToldOfIsEndedWhateverPilesUpTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [PinchEvent] = []
        func add(_ e: PinchEvent) { lock.withLock { all.append(e) } }
        var list: [PinchEvent] { lock.withLock { all } }
    }

    private func engine(_ port: FakeTouchPort) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("pinch-pile")),
                        touches: port, pinchEnabled: { true })
    }
    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }

    /// A whole completed pinch whose frames start at `start` seconds.
    private func pinch(from start: Double) -> [TouchFrame] {
        (0...10).map { Hand.frame(start + Double($0) / 100, radius: 0.2) }
            + Hand.sweep(from: 0.2, to: 0.05, steps: 20, after: start + 0.10) + [Hand.lift(at: start + 0.32)]
    }

    /// Open scrubs after the events, in order: a began opens one, an ended closes it; an ended with none open or a began inside one is a grammar break.
    private func open(_ events: [PinchEvent]) -> (open: Int, broken: Bool) {
        var open = 0
        for event in events {
            switch event {
            case .began: if open > 0 { return (open, true) }; open += 1
            case .moved: if open == 0 { return (open, true) }
            case .ended: if open == 0 { return (open, true) }; open -= 1
            }
        }
        return (open, false)
    }

    func testAnEndMainWasOwedSurvivesAWholeLaterScrubAndAStopWhileMainIsBusy() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let first = pinch(from: 0)
        first[..<20].forEach(port.send)
        drain()
        guard case .began? = heard.list.first else { return XCTFail("the subject: main must have heard the first scrub begin: \(heard.list)") }
        first[20...].forEach(port.send)
        pinch(from: 1).forEach(port.send)
        engine.setPinchWatching(false)
        drain()
        let state = open(heard.list)
        XCTAssertFalse(state.broken, "grammar broke: \(heard.list)")
        XCTAssertEqual(state.open, 0, "main was told a scrub began and never that it ended: \(heard.list)")
    }

    func testTheSameWithTheModuleDeactivatingInsteadOfTheSwitch() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let first = pinch(from: 0)
        first[..<20].forEach(port.send)
        drain()
        first[20...].forEach(port.send)
        pinch(from: 1).forEach(port.send)
        engine.deactivate()
        drain()
        XCTAssertEqual(open(heard.list).open, 0, "\(heard.list)")
    }

    /// Control: the same piling up with no stop ends in order, so a red above is the stop's.
    func testControlTheSamePileWithNoStopIsInOrderAndWhole() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let first = pinch(from: 0)
        first[..<20].forEach(port.send)
        drain()
        first[20...].forEach(port.send)
        pinch(from: 1).forEach(port.send)
        drain()
        let state = open(heard.list)
        XCTAssertFalse(state.broken)
        XCTAssertEqual(state.open, 0)
        XCTAssertEqual(heard.list.filter { if case .ended = $0 { true } else { false } }.count, 2)
    }

    /// Control for `ThePinchWatchUnderUntriedSequencesTests.testLateFramesOfAnEarlierWatchAreNotFedToTheNewOne`, whose frames must be a
    /// hand that scrubs when one watch sees them all: if they began nothing there, that test would pass with the guard removed.
    func testControlTheLateFramesOfThatTestScrubWhenOneWatchSeesThemAll() {
        let port = FakeTouchPort(), engine = engine(port), heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        let closing = [Hand.frame(0.11, radius: 0.1)] + Hand.still(radius: 0.05, steps: 9, after: 0.11)
        (Hand.landing() + closing).forEach(port.send)
        drain()
        guard case .began(.pinch, _)? = heard.list.first else { return XCTFail("the frames begin no scrub: \(heard.list)") }
    }
}
