import XCTest
@testable import HelmContract

/// What an engine says must reach a late subscriber as the current truth, in
/// the order the engine established, and never as a state older than one the
/// subscriber has already been handed.
///
/// `EngineNews.stream()` registers a subscriber and replays the last value of
/// every slot. Doing the two in two lock holds, or the replay outside the lock,
/// left a window: a `say` landing in it reached the new subscriber at once and
/// the replay — older by definition — followed it. A model that assigns what it
/// receives then ends on the stale state: a page that comes back idle with
/// `brew upgrade` still running behind it.
///
/// Values are `Int`, and the number carries the slot, because a stream hands
/// out values and not slot names: `state` holds a counter that only grows
/// (positive), filler slots hold negative numbers, `marker` ends a read.
final class EngineNewsReplayTests: XCTestCase {

    private static let marker = Int.max

    /// A flag two threads share.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func raise() { lock.lock(); value = true; lock.unlock() }
        var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Everything the stream carries, up to a marker said after `stream()`
    /// returned: no waiting on a clock, and a stream that lost its replay
    /// ends in a failed comparison, not in a hang.
    private static func collect(_ stream: AsyncStream<Int>, from news: EngineNews<Int>) async -> [Int] {
        news.say(marker, slot: "marker")
        var seen: [Int] = []
        for await value in stream {
            if value == marker { break }
            seen.append(value)
        }
        return seen
    }

    // MARK: - the window between replay and registration

    /// One round: a thread says a growing counter on `state` for as long as the
    /// subscription takes, while the main flow subscribes to a news object that
    /// already holds `fillers` slots of history, so the replay has work to do.
    /// Returns the `state` values in delivery order.
    private static func subscribeWhileSaying(fillers: Int) -> (EngineNews<Int>, AsyncStream<Int>) {
        let news = EngineNews<Int>()
        for index in 0..<fillers { news.say(-(index + 1), slot: "filler\(index)") }
        news.say(1, slot: "state")

        let stop = Flag()
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var counter = 1
            started.signal()
            while !stop.isRaised && counter < 50_000 {
                counter += 1
                news.say(counter, slot: "state")
            }
            finished.signal()
        }
        started.wait()

        let stream = news.stream()
        stop.raise()
        finished.wait()
        return (news, stream)
    }

    private static func racedRound(fillers: Int) async -> [Int] {
        let (news, stream) = subscribeWhileSaying(fillers: fillers)
        return await collect(stream, from: news).filter { $0 > 0 }
    }

    func testANewStateIsNeverFollowedByOneItReplaced() async {
        let rounds = 400
        var inversions = 0
        var entered = 0

        for _ in 0..<rounds {
            let states = await Self.racedRound(fillers: 200)
            // More than the replayed value means a `say` reached the stream
            // after the subscription began: the window was in play.
            if states.count > 1 { entered += 1 }
            if zip(states, states.dropFirst()).contains(where: { $0 > $1 }) { inversions += 1 }
        }

        XCTAssertGreaterThan(entered, 0,
                             "no round had a say land after the subscription began, so the "
                             + "window this test aims at was never entered and a pass proves nothing")
        XCTAssertEqual(inversions, 0,
                       "\(inversions) of \(rounds) subscriptions were handed an older state "
                       + "after a newer one (\(entered) rounds entered the window)")
    }

    // MARK: - what a late subscriber is handed

    func testALateSubscriberIsHandedTheHistoryBeforeAnythingLive() async {
        let news = EngineNews<Int>()
        news.say(1, slot: "first")
        news.say(2, slot: "second")
        news.say(3, slot: "third")

        let stream = news.stream()
        news.say(4, slot: "first")
        let seen = await Self.collect(stream, from: news)

        XCTAssertEqual(seen, [1, 2, 3, 4], "replay first, in order, then what was said afterwards")
    }

    func testASubscriberToNothingSaidGetsOnlyWhatIsSaidNext() async {
        let news = EngineNews<Int>()
        let stream = news.stream()
        news.say(7)
        let seen = await Self.collect(stream, from: news)
        XCTAssertEqual(seen, [7])
    }

    /// Homebrew's three slots: a state, a streaming log and a third, said in
    /// an interleaved order. Each slot replays its last value; the slots keep
    /// the order of their first appearance, not of their last update and not
    /// a dictionary's.
    func testThreeSlotsReplayTheirLastValueInOrderOfFirstAppearance() async {
        let news = EngineNews<Int>()
        news.say(10, slot: "opState")
        news.say(20, slot: "opLog")
        news.say(30, slot: "opResult")
        news.say(21, slot: "opLog")
        news.say(11, slot: "opState")
        news.say(22, slot: "opLog")

        let seen = await Self.collect(news.stream(), from: news)

        XCTAssertEqual(seen, [11, 22, 30])
    }

    /// Dictionary order is stable within a process, so one arrangement of names
    /// could agree with first appearance by luck. Several arrangements cannot.
    func testFirstAppearanceOrderHoldsForManyArrangementsOfNames() async {
        let names = (0..<12).map { "slot\($0)" }
        for shift in 0..<12 {
            let arranged = Array(names[shift...] + names[..<shift])
            let news = EngineNews<Int>()
            for (index, name) in arranged.enumerated() { news.say(index, slot: name) }
            let seen = await Self.collect(news.stream(), from: news)
            XCTAssertEqual(seen, Array(0..<12), "arrangement \(shift) replayed out of order")
        }
    }

    func testTwoSubscribersEachGetTheReplayAndTheLiveValue() async {
        let news = EngineNews<Int>()
        news.say(1, slot: "state")
        let first = news.stream()
        let second = news.stream()
        news.say(2, slot: "state")
        news.say(Self.marker, slot: "marker")

        for stream in [first, second] {
            var seen: [Int] = []
            for await value in stream {
                if value == Self.marker { break }
                seen.append(value)
            }
            XCTAssertEqual(seen, [1, 2])
        }
    }

    // MARK: - the count

    func testACancelledConsumerLeavesTheCountAndOnlyIt() async {
        let news = EngineNews<Int>()
        XCTAssertEqual(news.subscriberCount, 0)

        let kept = news.stream()
        let dropped = news.stream()
        XCTAssertEqual(news.subscriberCount, 2, "the count must be right as soon as stream() returns")

        let task = Task { for await _ in dropped {} }
        task.cancel()
        await task.value

        XCTAssertEqual(news.subscriberCount, 1, "the cancelled consumer stayed registered, or the kept one left")

        news.say(5)
        let seen = await Self.collect(kept, from: news)
        XCTAssertEqual(seen, [5], "the surviving subscriber lost what was said")
    }
}
