import XCTest
@testable import HelmContract

/// A late subscriber must never be handed a **stale** state as its last word.
///
/// The replay in `LocalTransport.events` exists because engine state is
/// level-triggered: the last "state" event *is* the current truth, so a view
/// model built after `activate()` has already emitted must still see it, or the
/// page sits at its defaults with the engine running behind it. That is the
/// defect the mechanism was written for, and the mechanism could produce it
/// itself.
///
/// The subscriber was registered **before** its replay was delivered, and the
/// delivery happened outside the lock:
///
/// ```swift
/// lock.lock()
/// subscribers[id] = continuation          // live: emit() reaches it from here
/// let replay = eventOrder.compactMap { lastEvents[$0] }
/// lock.unlock()
/// for event in replay { continuation.yield(event) }   // …older values, after
/// ```
///
/// So an `emit` landing in that window was yielded first and the replay
/// followed it — the stream carried the new state and then the old one, and a
/// view model that assigns what it receives ends on the old. It is the Homebrew
/// defect `LocalTransport`'s own comments already describe (a page that came
/// back idle with `brew upgrade` still running behind it), reached by a
/// different road.
///
/// **This test was watched failing before the fix**, which for a race is the
/// only claim worth making: 60 rounds, and the `sawBoth` assertion is there
/// because a round that never entered the window proves nothing either way.
final class ReplayOrderTests: XCTestCase {

    private static let stateName = "state"

    /// Filler names, so the replay loop has real work to do and the window is
    /// wide enough to be hit rather than argued about.
    private static func transportWithHistory() -> LocalTransport {
        let transport = LocalTransport()
        for index in 0..<80 {
            transport.emit(EngineEvent(name: "filler\(index)", payload: Data([0])))
        }
        transport.emit(EngineEvent(name: stateName, payload: Data([0])))  // the old state
        return transport
    }

    /// What one subscriber saw, in the order the stream delivered it.
    ///
    /// A plain buffer behind a lock, read after a fixed window, rather than a
    /// task group: a group whose collector may legitimately never finish needs a
    /// deadline child, and the first version of this deadlocked on exactly that
    /// — the collector waited for a second event that a passing round never
    /// produces, and the timeout child could not make the parent stop waiting
    /// for it.
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: [UInt8] = []
        func record(_ byte: UInt8) { lock.lock(); bytes.append(byte); lock.unlock() }
        var all: [UInt8] { lock.lock(); defer { lock.unlock() }; return bytes }
    }

    /// One round: a subscriber wired up while the new state is emitted.
    private static func racedRound() async -> [UInt8] {
        let transport = transportWithHistory()
        let seen = Seen()

        let subscriber = Task.detached {
            for await event in transport.events where event.name == stateName {
                if let byte = event.payload.first { seen.record(byte) }
            }
        }
        let emitter = Task.detached {
            transport.emit(EngineEvent(name: stateName, payload: Data([1])))
        }

        _ = await emitter.value
        try? await Task.sleep(nanoseconds: 40_000_000)
        subscriber.cancel()
        return seen.all
    }

    func testANewStateIsNeverFollowedByTheOneItReplaced() async {
        var inversions = 0
        var sawBoth = 0
        let rounds = 60

        for _ in 0..<rounds {
            let payloads = await Self.racedRound()

            if payloads.contains(1), payloads.contains(0) { sawBoth += 1 }
            if let new = payloads.firstIndex(of: 1), let old = payloads.lastIndex(of: 0),
               old > new {
                inversions += 1
            }
        }

        XCTAssertGreaterThan(sawBoth, 0,
                             "no round ever saw both states, so the window this test aims "
                             + "at was never entered and a pass proves nothing")
        XCTAssertEqual(inversions, 0,
                       "\(inversions) of \(rounds) subscriptions ended on the state that "
                       + "had already been replaced — the replay reached the subscriber "
                       + "after a newer event did")
    }
}
