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
///
/// `testTwoThreadsEmittingOneNameLeaveEverySubscriberOnWhatTheTransportKept`
/// holds the other side of the same lock, the order in which emits of one name
/// reach live subscribers; `testAHandlerThatEmitsOnItsOwnTransportAnswersThroughSend`
/// holds `send`, which must not keep the lock while a handler that emits on the
/// transport it was sent through runs.
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
    /// A plain buffer behind a lock, read after a fixed window or polled to a
    /// deadline, rather than a task group: a group whose collector may
    /// legitimately never finish needs a deadline child, and the first version
    /// of the replay row deadlocked on exactly that — the collector waited for a
    /// second event that a passing round never produces, and the timeout child
    /// could not make the parent stop waiting for it.
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var payloads: [Data] = []
        func record(_ payload: Data) { lock.lock(); payloads.append(payload); lock.unlock() }
        var all: [Data] { lock.lock(); defer { lock.unlock() }; return payloads }
    }

    /// One round: a subscriber wired up while the new state is emitted.
    private static func racedRound() async -> [UInt8] {
        let transport = transportWithHistory()
        let seen = Seen()

        let subscriber = Task.detached {
            for await event in transport.events where event.name == stateName {
                seen.record(event.payload)
            }
        }
        let emitter = Task.detached {
            transport.emit(EngineEvent(name: stateName, payload: Data([1])))
        }

        _ = await emitter.value
        try? await Task.sleep(nanoseconds: 40_000_000)
        subscriber.cancel()
        return seen.all.compactMap { $0.first }
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

    /// What one round of two emitting threads left behind.
    private struct EmitRound {
        var stored: Data?
        var lasts: [Data?]
        var drained: Bool
        var interleaved: Bool
        var disagreeing: Int
    }

    private static func emitRound(subscribers: Int, perThread: Int) -> EmitRound {
        let transport = LocalTransport()
        let received = (0..<subscribers).map { _ in Seen() }
        let readers = received.map { sink in
            Task.detached {
                for await event in transport.events where event.name == stateName {
                    sink.record(event.payload)
                }
            }
        }
        defer { readers.forEach { $0.cancel() } }

        let ready = Date().addingTimeInterval(5)
        while transport.subscriberCount < subscribers, Date() < ready { usleep(200) }

        // Both threads start on one signal and every payload is distinct:
        // byte 0 is the thread, the next two its running number.
        let gate = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        for thread in 0..<2 {
            finished.enter()
            Thread.detachNewThread {
                gate.wait()
                for number in 0..<perThread {
                    let payload = Data([UInt8(thread), UInt8(number >> 8), UInt8(number & 0xff)])
                    transport.emit(EngineEvent(name: stateName, payload: payload))
                }
                finished.leave()
            }
        }
        gate.signal(); gate.signal()
        _ = finished.wait(timeout: .now() + 10)

        let expected = 2 * perThread
        let drainBy = Date().addingTimeInterval(5)
        while received.contains(where: { $0.all.count < expected }), Date() < drainBy {
            usleep(500)
        }
        let sequences = received.map { $0.all }
        let drained = sequences.allSatisfy { $0.count == expected }

        // What the transport kept last is what a page opened now replays.
        let late = Seen()
        let lateReader = Task.detached {
            for await event in transport.events where event.name == stateName {
                late.record(event.payload)
            }
        }
        let replayBy = Date().addingTimeInterval(5)
        while late.all.isEmpty, Date() < replayBy { usleep(200) }
        lateReader.cancel()

        return EmitRound(
            stored: late.all.first,
            lasts: sequences.map { $0.last },
            drained: drained,
            interleaved: sequences.contains { sequence in
                zip(sequence, sequence.dropFirst()).contains { $0.0.first != $0.1.first }
            },
            disagreeing: sequences.filter { $0 != sequences[0] }.count)
    }

    /// Two threads emit one name while many subscribers listen. Every live
    /// subscriber must end on the value a subscriber opened afterwards is
    /// replayed, which is the one the transport stored last.
    ///
    /// The transport stores an event and then hands it out; if the handing out
    /// happens after the lock is released, one thread's older event can reach a
    /// subscriber after the other's newer one while the store holds the newer.
    /// A round that goes wrong is rare, hence the many rounds, and a pass is
    /// only read if the emits interleaved at some subscriber, every subscriber
    /// received every emit, and the late subscriber was replayed something.
    func testTwoThreadsEmittingOneNameLeaveEverySubscriberOnWhatTheTransportKept() {
        let rounds = 200, subscribers = 40, perThread = 20
        var wrong = 0, subscribersWrong = 0, disagreeing = 0
        var interleavedRounds = 0, undrained = 0, unreplayed = 0

        for _ in 0..<rounds {
            let round = Self.emitRound(subscribers: subscribers, perThread: perThread)
            if !round.drained { undrained += 1 }
            guard let stored = round.stored else { unreplayed += 1; continue }
            if round.interleaved { interleavedRounds += 1 }
            disagreeing += round.disagreeing
            let off = round.lasts.filter { $0 != stored }.count
            subscribersWrong += off
            if off > 0 { wrong += 1 }
        }
        print("emit race: \(rounds) rounds, \(subscribers) subscribers, \(2 * perThread) emits each: "
              + "\(wrong) rounds ended a subscriber off the stored value (\(subscribersWrong) subscribers), "
              + "\(interleavedRounds) interleaved, \(disagreeing) subscribers disagreed with the first, "
              + "\(undrained) undrained, \(unreplayed) without a replay")

        XCTAssertEqual(unreplayed, 0, "the late subscriber was never handed the stored event")
        XCTAssertEqual(undrained, 0, "a subscriber did not receive every emit within the deadline")
        XCTAssertGreaterThan(interleavedRounds, 0,
                             "no round saw the two threads' events interleave, so the "
                             + "emits never overlapped and a pass proves nothing")
        XCTAssertEqual(wrong, 0,
                       "\(wrong) of \(rounds) rounds ended \(subscribersWrong) live subscribers on a "
                       + "value other than the one the transport stored last")
    }

    /// The answer of one `send`, written from the task that made it.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        func set(_ value: Data?) { lock.lock(); data = value; lock.unlock() }
        var value: Data? { lock.lock(); defer { lock.unlock() }; return data }
    }

    /// `send` must return for a handler that emits on the transport it was
    /// sent through, and the event must reach a subscriber once.
    ///
    /// If `send` kept the transport's lock while the handler ran, that emit
    /// would wait for a lock only the handler's return releases. The emit runs
    /// on a thread of its own that the handler awaits, so such a `send` shows as
    /// a missed deadline and not as a blocked thread of the cooperative pool or
    /// a test process that never ends; after a miss the transport is not
    /// touched again, since cancelling the reader would ask the same lock.
    func testAHandlerThatEmitsOnItsOwnTransportAnswersThroughSend() {
        let transport = LocalTransport()
        let heard = Seen()
        let reader = Task.detached {
            for await event in transport.events where event.name == Self.stateName {
                heard.record(event.payload)
            }
        }

        let ready = Date().addingTimeInterval(5)
        while transport.subscriberCount < 1, Date() < ready { usleep(200) }

        transport.setHandler { _ in
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                Thread.detachNewThread {
                    transport.emit(EngineEvent(name: Self.stateName, payload: Data([7])))
                    done.resume()
                }
            }
            return Data([9])
        }

        let answer = Answer()
        let answered = DispatchSemaphore(value: 0)
        Task.detached {
            answer.set(try? await transport.send(EngineCommand(name: "go")))
            answered.signal()
        }

        guard answered.wait(timeout: .now() + 5) == .success else {
            XCTFail("`send` did not return within 5 s for a handler that emits on the "
                    + "same transport — the lock is still held while the handler runs")
            return
        }
        XCTAssertEqual(answer.value, Data([9]), "`send` did not hand back the handler's answer")

        let heardBy = Date().addingTimeInterval(5)
        while heard.all.isEmpty, Date() < heardBy { usleep(200) }
        reader.cancel()
        XCTAssertEqual(heard.all, [Data([7])],
                       "the event the handler emitted did not reach the subscriber exactly once")
    }
}
