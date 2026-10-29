import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_KeepAwake_Engine

/// `KeepAwakeEngine.stream()` hands a late subscriber the latest state and then
/// every later one, in order, with nothing missing, repeated, or older than a
/// newer one already delivered.
///
/// The replay exists because state is level-triggered: a model built after
/// `activate()` must still see the current truth. Taking the stream in two steps
/// (read the state, then subscribe) loses an emit that lands between them;
/// registering before replaying delivers an older state after a newer one. Only
/// one hold of the transport's lock for both is right, and a race is the only way
/// to see either defect, so each round emits a numbered run of states while the
/// subscription is taken and checks the *structure* of what arrived: strictly
/// increasing, contiguous from its first element, ending on the last emit.
/// `Tests/HelmContractTests/ReplayOrderTests.swift` guards the same order in
/// `LocalTransport` itself, with raw bytes; this one is aimed at the engine's own
/// typed entry point.
///
/// The emit goes through the transport the engine was built on, with a numbered
/// payload (in `holdingApps`), because the engine's own emitter writes no number
/// a test could order by. No hook is needed from the engine.
final class TheStreamReplaysTheStateInOrderTests: KeepAwakeEngineRig {

    private var shared: LocalTransport!
    private var raced: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        shared = LocalTransport()
        raced = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                displayInfo: displayInfo, displayObserver: displayObserver,
                                power: power, apps: apps, pointer: pointer,
                                clamshell: clamshell, clock: clock, transport: shared)
    }

    private static func state(_ n: Int) -> KeepAwakeEngine.StatePayload {
        KeepAwakeEngine.StatePayload(isActive: true, conditions: [], clamshellActive: false,
                                     endDate: nil, startDate: nil, suppressed: false,
                                     holdingApps: ["\(n)"])
    }

    private static func number(_ p: KeepAwakeEngine.StatePayload) -> Int {
        Int(p.holdingApps.first ?? "") ?? -1
    }

    /// What one subscriber saw, in delivery order.
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var numbers: [Int] = []
        func record(_ n: Int) { lock.lock(); numbers.append(n); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return numbers }
    }

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private enum Order { case emitFirst, subscribeFirst }

    /// One round of `total` numbered emits (0..<total). Returns what arrived.
    private func round(_ order: Order, total: Int) async -> [Int] {
        let transport = shared!
        let engine = raced!
        let seen = Seen()
        let emitAll: @Sendable () -> Void = {
            for n in 0..<total { transport.emit(KeepAwakeEvent.state, encoding: Self.state(n)) }
        }
        var reader: Task<Void, Never>!
        switch order {
        case .emitFirst:
            transport.emit(KeepAwakeEvent.state, encoding: Self.state(0))
            let stream = engine.stream()
            reader = Task.detached {
                for await p in stream { seen.record(Self.number(p)) }
            }
            for n in 1..<total { transport.emit(KeepAwakeEvent.state, encoding: Self.state(n)) }
        case .subscribeFirst:
            let stream = engine.stream()
            reader = Task.detached {
                for await p in stream { seen.record(Self.number(p)) }
            }
            emitAll()
        }
        let deadline = Date().addingTimeInterval(2)
        while seen.all.last != total - 1, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        reader.cancel()
        await reader.value
        return seen.all
    }

    /// One round of the race: an emitter writes `total` numbered states while
    /// `subscribers` streams are taken one after another beside it, each only once
    /// the emitter is under way. Several subscriptions per round, because the gap
    /// a two-step subscription leaves is a few nanoseconds wide and each
    /// `stream()` call is one throw at it. Returns what each subscriber saw.
    private func racingRound(total: Int, subscribers: Int) async -> [[Int]] {
        let transport = shared!
        let engine = raced!
        let emitted = Count()
        let emitter = Task.detached {
            for n in 0..<total {
                transport.emit(KeepAwakeEvent.state, encoding: Self.state(n))
                emitted.bump()
            }
        }
        // Not before the emitter is under way, or every subscription lands ahead
        // of the first emit and the window is never entered.
        let patience = Date().addingTimeInterval(2)
        while emitted.value == 0, Date() < patience { await Task.yield() }
        var seens: [Seen] = []
        var readers: [Task<Void, Never>] = []
        for _ in 0..<subscribers {
            let seen = Seen()
            let stream = engine.stream()
            seens.append(seen)
            readers.append(Task.detached { for await p in stream { seen.record(Self.number(p)) } })
        }
        await emitter.value
        let deadline = Date().addingTimeInterval(2)
        while seens.contains(where: { $0.all.last != total - 1 }), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        for r in readers { r.cancel() }
        for r in readers { await r.value }
        return seens.map(\.all)
    }

    /// Strictly increasing, no gap after the first element, ends on the last emit.
    private func verdict(_ got: [Int], total: Int) -> String? {
        guard let first = got.first else { return "nothing arrived" }
        for (a, b) in zip(got, got.dropFirst()) {
            if b == a { return "doubled \(a)" }
            if b < a { return "stale \(b) after \(a)" }
            if b != a + 1 { return "lost \(a + 1)..<\(b)" }
        }
        if got.last != total - 1 { return "ended at \(got.last!), first \(first), never \(total - 1)" }
        return nil
    }

    func testEmitBeforeSubscribeReplaysTheLatestThenFollows() async {
        var bad: [String] = []
        for _ in 0..<200 {
            shared = LocalTransport()
            raced = makeRaced()
            let got = await round(.emitFirst, total: 50)
            if let why = verdict(got, total: 50) { bad.append(why) }
            // Replay is the first element: it can only be 0 or later, never nothing.
            XCTAssertEqual(got.first, 0, "the replay of the state emitted before subscribing")
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of 200 rounds: \(bad.prefix(3))")
    }

    func testSubscribeBeforeEmitSeesEveryState() async {
        var bad: [String] = []
        for _ in 0..<200 {
            shared = LocalTransport()
            raced = makeRaced()
            let got = await round(.subscribeFirst, total: 50)
            if let why = verdict(got, total: 50) { bad.append(why) }
            XCTAssertEqual(got.first, 0, "no replay existed, so the first emit is the first element")
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of 200 rounds: \(bad.prefix(3))")
    }

    func testAnEmitRacingTheSubscriptionIsNeitherLostNorReordered() async {
        let total = 2000
        var bad: [String] = []
        var enteredWindow = 0
        var checked = 0
        for _ in 0..<300 {
            shared = LocalTransport()
            raced = makeRaced()
            for got in await racingRound(total: total, subscribers: 16) {
                checked += 1
                if let why = verdict(got, total: total) { bad.append(why) }
                // The subscription landed amid the run, not before or after all of it.
                if let first = got.first, first > 0, first < total - 1 { enteredWindow += 1 }
            }
        }
        print("racing: \(enteredWindow) of \(checked) subscriptions landed mid-run")
        XCTAssertGreaterThan(enteredWindow, 0,
                             "no subscription landed in the middle of the emits, so the race "
                             + "this aims at never happened and a pass proves nothing")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) subscriptions: \(bad.prefix(3))")
    }

    func testTheSubscriberIsGoneWhenTheStreamsTaskIsCancelled() async {
        let before = shared.subscriberCount
        let stream = raced.stream()
        XCTAssertEqual(shared.subscriberCount, before + 1,
                       "stream() registers synchronously, before any await")
        let task = Task.detached { for await _ in stream {} }
        shared.emit(KeepAwakeEvent.state, encoding: Self.state(1))
        task.cancel()
        await task.value
        let deadline = Date().addingTimeInterval(2)
        while shared.subscriberCount != before, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(shared.subscriberCount, before, "a cancelled stream left its subscriber behind")
    }

    private func makeRaced() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                        displayInfo: displayInfo, displayObserver: displayObserver,
                        power: power, apps: apps, pointer: pointer,
                        clamshell: clamshell, clock: clock, transport: shared)
    }
}
