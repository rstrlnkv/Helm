import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// The silence watchdog's own timer, not a hand-called `checkSilence()`: a scrub that begins before the previous scrub's check tick
/// (the chain is reused), one that begins after the chain died (it is armed again), a watch restarted with a check still on its
/// way (the stale check ends the old scrub's silence only, and never a live scrub of the new watch), and a pad that comes back after
/// the watchdog ended it (silent until its lift, then a hand like any other). The clock is injected, the ticks are real (0.25 s).
final class TheSilenceWatchUnderUntriedSequencesTests: XCTestCase {
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [PinchEvent] = []
        func add(_ e: PinchEvent) { lock.withLock { all.append(e) } }
        var list: [PinchEvent] { lock.withLock { all } }
        func count(_ e: PinchEvent) -> Int { list.filter { $0 == e }.count }
        var began: Int { list.filter { if case .began = $0 { true } else { false } }.count }
    }

    private let clock = Locked<Double>(0)
    private func set(_ t: Double) { clock.withLock { $0 = t } }
    private func rig(_ label: String) -> (LaunchpadEngine, FakeTouchPort, Heard) {
        let clock = self.clock, port = FakeTouchPort(), heard = Heard()
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory(label)),
                                     touches: port, pinchEnabled: { true }, now: { clock.withLock { $0 } })
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        engine.activate()
        return (engine, port, heard)
    }
    /// Runs main for the whole time: `RunLoop.run(until:)` alone returns at once when it has no source, and the hops to main are blocks.
    private func wait(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    func testAScrubThatBeginsBeforeTheNextTickIsWatchedByTheSameChain() {
        let (engine, port, heard) = rig("silence-reuse")
        defer { withExtendedLifetime(engine) {} }
        Hand.completedPinch().forEach(port.send)
        port.send(Hand.frame(0, radius: 0.2)) // a clock that starts over; the hand lands again below
        Hand.completedPinch().dropLast(1).prefix(20).forEach(port.send)
        wait(0.05)
        XCTAssertEqual(heard.began, 2, "the subject: two scrubs began, the second before the first's check tick: \(heard.list)")
        XCTAssertEqual(heard.count(.ended(.complete)), 1)
        set(1)
        wait(0.6)
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "the second scrub fell silent and was ended by the timer: \(heard.list)")
    }

    func testAScrubThatBeginsAfterTheChainDiedIsWatchedAgain() {
        let (engine, port, heard) = rig("silence-rearm")
        defer { withExtendedLifetime(engine) {} }
        Hand.completedPinch().forEach(port.send)
        wait(0.45) // the chain's tick finds no owner and ends
        Hand.completedPinch().prefix(20).forEach(port.send)
        wait(0.05)
        XCTAssertEqual(heard.began, 2, "the subject: \(heard.list)")
        set(1)
        wait(0.6)
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "\(heard.list)")
    }

    func testARestartWithACheckOnItsWayAnswersOneRevertAndTheStaleCheckEndsQuietly() {
        let (engine, port, heard) = rig("silence-restart")
        Hand.completedPinch().prefix(20).forEach(port.send)
        wait(0.05)
        XCTAssertEqual(heard.began, 1, "the subject: \(heard.list)")
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        wait(0.05)
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "the stop told main: \(heard.list)")
        set(5)
        wait(0.7) // the old chain's tick, with the new watch running and nobody owning
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "a stale check made up an end: \(heard.list)")
        XCTAssertEqual(heard.began, 1)
    }

    func testAStaleCheckNeverRevertsALiveScrubOfTheNewWatchButARealSilenceEndsItOnce() {
        let (engine, port, heard) = rig("silence-stale-live")
        Hand.completedPinch().prefix(20).forEach(port.send)
        wait(0.05)
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        set(0.5)
        Hand.completedPinch().prefix(20).forEach(port.send) // heard at 0.5
        set(0.6)
        wait(0.35) // both the old chain and the new one tick: 0.1 s of silence is no silence
        XCTAssertEqual(heard.began, 2, "the subject: \(heard.list)")
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "only the stop's end so far: \(heard.list)")
        set(3)
        wait(0.35)
        XCTAssertEqual(heard.count(.ended(.revert)), 2, "now it is silent, and ended once however many chains tick: \(heard.list)")
        wait(0.6)
        XCTAssertEqual(heard.count(.ended(.revert)), 2, "\(heard.list)")
    }

    func testAPadThatComesBackAfterTheWatchdogIsSilentToItsLiftAndThenAHandLikeAnyOther() {
        let (engine, port, heard) = rig("silence-resume")
        let hand = Hand.completedPinch()
        hand.prefix(20).forEach(port.send)
        wait(0.05)
        set(2)
        engine.checkSilence()
        wait(0.1)
        XCTAssertEqual(heard.began, 1, "the subject: main heard the scrub begin: \(heard.list)")
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "the subject: \(heard.list)")
        set(2.1)
        hand.dropFirst(20).forEach(port.send) // the rest of the sweep and the lift
        Hand.completedPinch().prefix(20).forEach(port.send) // after the lift above: a new hand
        wait(0.1)
        let afterLift = heard.list
        XCTAssertEqual(afterLift.filter { $0 == .ended(.complete) }.count, 0, "the abandoned hand completed: \(afterLift)")
        XCTAssertEqual(heard.began, 2, "after its lift the pad is a hand like any other: \(afterLift)")
    }

    func testAnAbandonedPadWithItsFingersStillDownNeverBeginsAgainUntilAllLift() {
        let (engine, port, heard) = rig("silence-resume-down")
        let hand = Hand.completedPinch()
        hand.prefix(20).forEach(port.send)
        wait(0.05)
        set(2)
        engine.checkSilence()
        // Fingers never lift: the pad lands, closes and opens again over a second's worth of frames.
        let again = Hand.landing(radius: 0.2).map { f in TouchFrame(device: 0, time: f.time + 1, count: 5) { i in
            let a = 2 * Double.pi * Double(i) / 5
            return (0.5 + 0.2 * cos(a), 0.5 + 0.2 * sin(a), TouchFrame.touchingState) }! }
        let sweep = Hand.sweep(from: 0.2, to: 0.05, steps: 20, after: 1.10)
        (again + sweep).forEach(port.send)
        wait(0.1)
        XCTAssertEqual(heard.began, 1, "no lift came, so no new scrub: \(heard.list)")
        XCTAssertEqual(heard.count(.ended(.revert)), 1, "\(heard.list)")
    }
}
