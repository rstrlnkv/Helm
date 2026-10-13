import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// What an engine that keeps a copy of a setting the screen writes is told, and
/// when: `StoreWatch` over the keys it names.
///
/// `.helmStoreChanged` goes through `NotificationCenter.default`, which the whole
/// test process shares, so each test has a namespace of its own over an
/// `InMemoryKeyValueStore`.
///
/// **How an absence is proved.** Never after a sleep. A row that asserts "no
/// call" first waits for a call the same machinery does make, from a second
/// watch that names the key written. The main queue runs its blocks in order,
/// so when that call has come every call queued before it has been made; the
/// queue is then turned a few more times for one queued behind it. A row that
/// only asserts "no call" would pass for a watch that never calls at all.
///
/// The rows that count bytes, the row on what the closure holds and the row on
/// a stop that drops the engine wait for no call: what they measure is not a
/// call.
///
/// **What a watch does not do**, held by the rows on the writer: the announcement
/// carries the key and not the store (`NamespacedStore.set`), so the watch cannot
/// tell the engine's own write from the screen's. A named key written by anyone
/// calls it, and an engine therefore names no key it writes itself.
final class StoreWatchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - one call a turn, only the named keys, nothing after stop

    func testThreeNamedKeysWrittenInOneTurnGiveOneCall() {
        let store = freshStore()
        let calls = Calls()
        _ = watching(store, ["a", "b", "c"], calls)

        store.set(1, for: "a")
        store.set(2, for: "b")
        store.set(3, for: "c")
        waitForCalls(calls, 1, "three named keys written in one turn")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "three writes in one turn must give one call, not one each")
    }

    func testAKeyTheWatchDoesNotNameGivesNoCall() {
        let store = freshStore()
        let named = Calls(), marker = Calls()
        _ = watching(store, ["named"], named)
        _ = watching(store, ["other"], marker)

        store.set(1, for: "named")
        waitForCalls(named, 1, "the named key, which the watch must answer")
        store.set(1, for: "other")
        waitForCalls(marker, 1, "the key the first watch does not name, which was announced")
        theMainQueueTurns()

        XCTAssertEqual(named.count, 1, "a key the watch does not name called it")
    }

    func testAfterStopNothingIsCalled() {
        let store = freshStore()
        let stopped = Calls(), marker = Calls()
        let watch = watching(store, ["k"], stopped)
        _ = self.watching(store, ["k"], marker)

        store.set(1, for: "k")
        waitForCalls(stopped, 1, "the watch before it is stopped")
        waitForCalls(marker, 1, "the marker before the stop")
        watch.stop()
        store.set(2, for: "k")
        waitForCalls(marker, 2, "the marker after the stop, which was announced")
        theMainQueueTurns()

        XCTAssertEqual(stopped.count, 1, "a stopped watch was called")
    }

    // MARK: - the call is read after the last write of its turn

    func testTheCallComesAfterTheLastWriteOfTheTurn() {
        let store = freshStore()
        let box = Unsafe(store)
        let calls = Calls()
        let w = StoreWatch(store, keys: ["a", "b", "c"]) {
            let read = box.value
            calls.call {
                calls.note("\(read.int("a", default: 0)),\(read.int("b", default: 0)),\(read.int("c", default: 0))")
            }
        }
        addTeardownBlock { w.stop() }

        store.set(1, for: "a")
        store.set(2, for: "b")
        store.set(3, for: "c")
        waitForCalls(calls, 1, "three named keys written in one turn")
        theMainQueueTurns()

        XCTAssertEqual(calls.notes, ["1,2,3"],
                       "the call must read the three values as the turn left them, not a torn mix")
    }

    // MARK: - who writes

    func testTheStoreTheWatchWasBuiltOverCallsItForItsOwnWrite() {
        let store = freshStore()
        let calls = Calls()
        _ = watching(store, ["k"], calls)

        store.set(true, for: "k")
        waitForCalls(calls, 1, "a write by the store the watch was built over")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "the watch excludes nothing: its own store's write is a write")
    }

    func testAnotherStoreOverTheSameNamespaceAndBackingCallsIt() {
        let backing = InMemoryKeyValueStore()
        let namespace = freshNamespace()
        let watched = NamespacedStore(namespace: namespace, backing: backing)
        let writer = NamespacedStore(namespace: namespace, backing: backing)
        let calls = Calls()
        _ = watching(watched, ["k"], calls)

        writer.set(true, for: "k")
        waitForCalls(calls, 1, "a write by a second store over the same namespace and backing")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "the announcement does not say who wrote, so the writer is not excluded")
    }

    func testAStoreOverAnotherBackingInTheSameNamespaceAlsoCallsIt() {
        let namespace = freshNamespace()
        let watched = NamespacedStore(namespace: namespace, backing: InMemoryKeyValueStore())
        let elsewhere = NamespacedStore(namespace: namespace, backing: InMemoryKeyValueStore())
        let calls = Calls()
        _ = watching(watched, ["k"], calls)

        elsewhere.set(true, for: "k")
        waitForCalls(calls, 1, "a write by a store with the same namespace over another backing")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "the announcement carries the key and not the store, so the watch answers the key")
    }

    // MARK: - stopping and dropping

    func testACallPendingWhenStopComesIsNotDelivered() {
        let store = freshStore()
        let stopped = Calls(), marker = Calls()
        let watch = watching(store, ["k"], stopped)
        _ = self.watching(store, ["k"], marker)

        store.set(1, for: "k")
        watch.stop()
        waitForCalls(marker, 1, "the marker, which stands for the call that was due")
        theMainQueueTurns()

        XCTAssertEqual(marker.count, 1, "the marker was called more than once for one write")
        XCTAssertEqual(stopped.count, 0, "a call that was due when stop() came reached the engine afterwards")
    }

    func testADroppedWatchIsNeverCalledAgain() {
        let store = freshStore()
        let dropped = Calls(), marker = Calls()
        var held: StoreWatch? = StoreWatch(store, keys: ["k"]) { dropped.call() }
        _ = watching(store, ["k"], marker)

        store.set(1, for: "k")
        waitForCalls(dropped, 1, "the watch before it is dropped")
        waitForCalls(marker, 1, "the marker before the drop")
        held = nil
        XCTAssertNil(held)
        store.set(2, for: "k")
        waitForCalls(marker, 2, "the marker after the drop, which was announced")
        theMainQueueTurns()

        XCTAssertEqual(dropped.count, 1, "a watch that was dropped without stop() went on calling")
    }

    func testACallDueWhenTheWatchIsDroppedIsNeverDelivered() {
        let store = freshStore()
        let dropped = Calls(), marker = Calls()
        var held: StoreWatch? = StoreWatch(store, keys: ["k"]) { dropped.call() }
        _ = watching(store, ["k"], marker)

        store.set(1, for: "k")
        held = nil
        XCTAssertNil(held)
        waitForCalls(marker, 1, "the marker, which stands for the call that was due")
        theMainQueueTurns()

        XCTAssertEqual(marker.count, 1, "the marker was called more than once for one write")
        XCTAssertEqual(dropped.count, 0, "the call that was due held the watch alive and reached the engine after the drop")
    }

    func testStopLetsGoOfTheClosureAndWhatItHolds() {
        let store = freshStore()
        let (watch, probe) = watchWhoseClosureHoldsAProbe(store)
        XCTAssertNotNil(probe.value, "the closure did not hold the probe before stop(), so the row proves nothing")

        watch.stop()

        XCTAssertNil(probe.value, "a stopped watch still holds its closure and what the closure holds")
        withExtendedLifetime(watch) {}
    }

    /// Letting go of the closure can let go of the engine it holds, and that
    /// engine's `deinit` stops this same watch. A `stop()` that let the closure go
    /// while it held its lock would have the second `stop()` wait for a lock its
    /// own thread holds. The stop runs on a thread of its own, so such a wait
    /// ends this row by its bound and not the suite.
    func testStopWhoseClosureHoldsAnEngineThatStopsTheSameWatchReturns() {
        let store = freshStore()
        let ended = Flag()
        let (watch, engine) = watchWhoseClosureHoldsAnEngineThatStopsIt(store, ended)
        XCTAssertNotNil(engine.value, "the closure did not hold the engine before stop(), so the row proves nothing")
        XCTAssertFalse(ended.isRaised, "the engine ended before stop(), so the row proves nothing")

        let returned = expectation(description: "stop() returned")
        let thread = Thread {
            watch.stop()
            returned.fulfill()
        }
        thread.start()
        if XCTWaiter().wait(for: [returned], timeout: 4) != .completed {
            // The thread that is stuck holds the watch's lock for good: the watch
            // must outlive the row, or its `deinit` would wait for that lock on the
            // main thread.
            Immortal.shared.keep(watch)
            XCTFail("stop() did not return in 4 s: the engine it dropped stopped the same watch and waited for a lock its own thread holds")
        }

        XCTAssertTrue(ended.isRaised, "stop() returned without dropping the engine the closure held")
        XCTAssertEqual(ended.raisedOnMain, false, "the engine was dropped on the main thread and not by the thread that stopped the watch")
        XCTAssertNil(engine.value)
    }

    func testStoppingTwiceIsHarmless() {
        let store = freshStore()
        let calls = Calls(), marker = Calls()
        let watch = watching(store, ["k"], calls)
        _ = self.watching(store, ["k"], marker)

        store.set(1, for: "k")
        waitForCalls(calls, 1, "the watch before it is stopped")
        watch.stop()
        watch.stop()
        store.set(2, for: "k")
        waitForCalls(marker, 2, "the marker after both stops")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "a second stop() brought the watch back or called it")
    }

    // MARK: - the centre is left clean

    /// The call-count rows cannot see a leaked observer: its block holds the watch
    /// weakly, so it is harmless to every count. What it costs is the block and
    /// its token, which the allocator's books show per watch.
    ///
    /// The bound is 64 bytes a watch. Measured: a watch that is let go of cleanly
    /// grows the books by about 7 bytes (14256 bytes over 2000 watches, the same
    /// to the byte in two runs); a watch whose observer stays in the centre grows
    /// them by 245 to 293 bytes (490736 to 586928 over 2000). The bound sits
    /// 9 times above the first and 4 times below the second.
    func testWatchesThatWereStoppedLeaveNothingInTheCentre() {
        let store = freshStore()
        let watches = 2000
        let grown = growthOfTheBooks(watches: watches) { StoreWatch(store, keys: ["k"]) {}.stop() }

        XCTAssertLessThan(grown, watches * 64, "stop() left an observer in the notification centre per watch (\(grown) bytes grown over \(watches) watches)")
    }

    func testWatchesThatWereDroppedLeaveNothingInTheCentre() {
        let store = freshStore()
        let watches = 2000
        let grown = growthOfTheBooks(watches: watches) { _ = StoreWatch(store, keys: ["k"]) {} }

        XCTAssertLessThan(grown, watches * 64, "a watch released without stop() left an observer in the notification centre (\(grown) bytes grown over \(watches) watches)")
    }

    // MARK: - which writes count

    func testAnEmptyKeyListWatchesNothing() {
        let store = freshStore()
        let empty = Calls(), marker = Calls()
        _ = watching(store, [], empty)
        _ = watching(store, ["k"], marker)

        store.set(1, for: "k")
        waitForCalls(marker, 1, "the marker for a write the empty watch must not hear")
        theMainQueueTurns()

        XCTAssertEqual(empty.count, 0, "an empty key list must mean nothing, not the whole namespace")
    }

    func testTheSameShortKeyInAnotherNamespaceGivesNoCall() {
        let mine = freshStore(), theirs = freshStore()
        let myCalls = Calls(), theirCalls = Calls()
        _ = watching(mine, ["k"], myCalls)
        _ = watching(theirs, ["k"], theirCalls)

        mine.set(1, for: "k")
        waitForCalls(myCalls, 1, "a write to the watch's own namespace")
        theMainQueueTurns()
        XCTAssertEqual(theirCalls.count, 0, "a write to another namespace called this one")

        theirs.set(1, for: "k")
        waitForCalls(theirCalls, 1, "a write to the other namespace, which was announced")
        theMainQueueTurns()
        XCTAssertEqual(myCalls.count, 1, "a write to another namespace called the first watch")
    }

    func testKeysThatOnlyContainOrExtendANamedKeyGiveNoCall() {
        let store = freshStore()
        let named = Calls(), marker = Calls()
        _ = watching(store, ["flag"], named)
        _ = watching(store, ["flagged", "unflag", "Flag", "flag.x"], marker)

        store.set(1, for: "flag")
        waitForCalls(named, 1, "the exact key")
        store.set(1, for: "flagged")
        store.set(1, for: "unflag")
        store.set(1, for: "Flag")
        store.set(1, for: "flag.x")
        waitForCalls(marker, 1, "the near misses, which were announced")
        theMainQueueTurns()

        XCTAssertEqual(named.count, 1, "a key that merely contains or extends the named one called the watch")
    }

    func testAnAnnouncementWithoutAKeyGivesNoCallAndHarmsNothing() {
        let store = freshStore()
        let calls = Calls(), marker = Calls()
        _ = watching(store, ["k"], calls)
        _ = watching(store, ["m"], marker)

        store.set(1, for: "k")
        waitForCalls(calls, 1, "a real write")
        NotificationCenter.default.post(name: .helmStoreChanged, object: nil)
        NotificationCenter.default.post(name: .helmStoreChanged, object: 7)
        NotificationCenter.default.post(name: .helmStoreChanged, object: "")
        store.set(1, for: "m")
        waitForCalls(marker, 1, "a real write after the announcements that carried no key")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1, "an announcement that names no key called the watch")
    }

    func testAWriteMadeBeforeTheWatchWasBuiltDoesNotCallIt() {
        let store = freshStore()
        let late = Calls(), marker = Calls()
        _ = watching(store, ["k"], marker)

        store.set(1, for: "k")
        _ = watching(store, ["k"], late)
        waitForCalls(marker, 1, "the marker, built before the write")
        theMainQueueTurns()
        XCTAssertEqual(late.count, 0, "a watch built after a write was called for it")

        store.set(2, for: "k")
        waitForCalls(late, 1, "a write after the watch was built")
        theMainQueueTurns()
        XCTAssertEqual(late.count, 1)
    }

    // MARK: - turns

    /// `NamespacedStore.set` compares nothing, so a write of the value the key
    /// already holds is announced and called like any other. Red if the store
    /// began to announce only a change, or if the watch began to compare what it
    /// reads.
    func testTheSameValueWrittenAgainInAnotherTurnGivesAnotherCall() {
        let store = freshStore()
        let calls = Calls()
        _ = watching(store, ["k"], calls)

        store.set(1, for: "k")
        waitForCalls(calls, 1, "the first write")
        XCTAssertEqual(store.int("k", default: 0), 1, "the key does not hold the value the second write repeats, so the row proves nothing")
        store.set(1, for: "k")
        waitForCalls(calls, 2, "the same value written again, which the store announces")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 2, "a write of an equal value was swallowed or called more than once")
    }

    func testWritesInTwoTurnsGiveTwoCalls() {
        let store = freshStore()
        let calls = Calls()
        _ = watching(store, ["a", "b"], calls)

        store.set(1, for: "a")
        waitForCalls(calls, 1, "the first turn's write")
        store.set(1, for: "b")
        waitForCalls(calls, 2, "the second turn's write")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 2, "the second turn's write was swallowed by the first's call")
    }

    func testAWriteFromInsideTheCallGivesOneMoreCallAfterItAndNotInsideIt() {
        let store = freshStore()
        let box = Unsafe(store)
        let calls = Calls()
        let w = StoreWatch(store, keys: ["k"]) {
            calls.call {
                if calls.count == 1 { box.value.set(2, for: "k") }
            }
        }
        addTeardownBlock { w.stop() }

        store.set(1, for: "k")
        waitForCalls(calls, 2, "the write made from inside the first call")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 2, "a write from inside the call was lost or called more than once")
        XCTAssertEqual(calls.deepest, 1, "the second call began while the first was still running")
    }

    // MARK: - threads

    func testAWriteFromAnotherThreadIsCalledOnTheMainThread() {
        let store = freshStore()
        let box = Unsafe(store)
        let calls = Calls()
        _ = watching(store, ["k"], calls)
        let ran = Calls()

        onAThread(ran) { box.value.set(1, for: "k") }
        XCTAssertTrue(ran.ranOffMain, "the write did not run on another thread")
        waitForCalls(calls, 1, "a write made off the main thread")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls.allOnMain, "the call did not arrive on the main thread")
    }

    /// A poster that does not go through `NamespacedStore.set` reaches the watch on
    /// its own thread: `set` hops to main before it posts, a bare post does not.
    /// The full key is spelled as `Architecture/ModulePattern.md` spells it.
    func testAnAnnouncementPostedFromAnotherThreadIsCalledOnceOnTheMainThread() {
        let namespace = freshNamespace()
        let store = NamespacedStore(namespace: namespace, backing: InMemoryKeyValueStore())
        let calls = Calls(), ran = Calls()
        _ = watching(store, ["k"], calls)

        onAThread(ran) {
            NotificationCenter.default.post(name: .helmStoreChanged, object: "module.\(namespace).k")
        }
        XCTAssertTrue(ran.ranOffMain, "the post did not run on another thread")
        waitForCalls(calls, 1, "a post of the full key made off the main thread")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls.allOnMain, "the call was made on the thread that posted")
    }

    func testAWatchBuiltOnAnotherThreadCallsOnTheMainThread() {
        let store = freshStore()
        let box = Unsafe(store)
        let calls = Calls(), ran = Calls()
        let built = Holder<StoreWatch>()

        onAThread(ran) { built.value = StoreWatch(box.value, keys: ["k"]) { calls.call() } }
        XCTAssertTrue(ran.ranOffMain, "the watch was not built on another thread")
        addTeardownBlock { built.value?.stop() }

        store.set(1, for: "k")
        waitForCalls(calls, 1, "a write after a watch built off the main thread")
        theMainQueueTurns()

        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls.allOnMain, "the call did not arrive on the main thread")
    }

    func testAWatchStoppedFromAnotherThreadIsNeverCalledAgain() {
        let store = freshStore()
        let stopped = Calls(), marker = Calls(), ran = Calls()
        let watch = watching(store, ["k"], stopped)
        _ = self.watching(store, ["k"], marker)

        store.set(1, for: "k")
        waitForCalls(stopped, 1, "the watch before it is stopped")
        waitForCalls(marker, 1, "the marker before the stop")
        onAThread(ran) { watch.stop() }
        XCTAssertTrue(ran.ranOffMain, "the stop did not run on another thread")
        store.set(2, for: "k")
        waitForCalls(marker, 2, "the marker after the stop, which was announced")
        theMainQueueTurns()

        XCTAssertEqual(stopped.count, 1, "a watch stopped from another thread was called afterwards")
    }

    // MARK: - the pieces

    /// What malloc holds more of after `watches` rounds of `round`, with a
    /// warm-up of the same rounds first so that one-time tables are not counted.
    /// The books are the whole process's; the run is on the main thread with
    /// nothing else of this test running, so what grows by thousands of rounds is
    /// what the rounds kept.
    private func growthOfTheBooks(watches: Int, _ round: () -> Void) -> Int {
        for _ in 0..<200 { round() }
        theMainQueueTurns()
        let before = AllocatorBooks.allocatedBytes()
        for _ in 0..<watches { round() }
        theMainQueueTurns()
        return AllocatorBooks.allocatedBytes() - before
    }

    /// A watch whose closure holds a `Probe` strongly, and a weak look at the
    /// probe. Built in a function of its own so that no local of the test keeps it.
    private func watchWhoseClosureHoldsAProbe(_ store: NamespacedStore) -> (StoreWatch, WeakProbe) {
        let probe = Probe()
        let watch = StoreWatch(store, keys: ["k"]) { _ = probe }
        return (watch, WeakProbe(probe))
    }

    /// A watch whose closure holds an `Engine` strongly, and a weak look at the
    /// engine. The engine looks at the watch weakly, so there is no cycle, and
    /// stops it in its `deinit`. Built in a function of its own so that no local
    /// of the test keeps the engine.
    private func watchWhoseClosureHoldsAnEngineThatStopsIt(_ store: NamespacedStore, _ ended: Flag) -> (StoreWatch, WeakEngine) {
        let engine = Engine(ended)
        let watch = StoreWatch(store, keys: ["k"]) { _ = engine }
        engine.watch = watch
        return (watch, WeakEngine(engine))
    }

    private func freshNamespace() -> String { "storewatch-\(UUID().uuidString)" }

    private func freshStore() -> NamespacedStore {
        NamespacedStore(namespace: freshNamespace(), backing: InMemoryKeyValueStore())
    }

    /// A watch that counts its calls in `calls` and is stopped when the test ends.
    private func watching(_ store: NamespacedStore, _ keys: Set<String>, _ calls: Calls) -> StoreWatch {
        let w = StoreWatch(store, keys: keys) { calls.call() }
        addTeardownBlock { w.stop() }
        return w
    }

    /// Spins the main run loop until `calls` has reached `count`, and fails
    /// naming `what` if it never does.
    private func waitForCalls(_ calls: Calls, _ count: Int, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let reached = expectation(description: "the watch was called \(count) time(s) in all: \(what)")
        reached.assertForOverFulfill = false
        calls.arm(count, reached)
        if XCTWaiter().wait(for: [reached], timeout: 3) != .completed {
            XCTFail("the watch was never called \(count) time(s) in all (\(calls.count) so far): \(what)",
                    file: file, line: line)
        }
    }

    /// The marker that the main queue has run what was on it: each turn is a
    /// block put on the queue and waited for.
    private func theMainQueueTurns(times: Int = 3) {
        for _ in 0..<times {
            let turned = expectation(description: "the main queue turned")
            DispatchQueue.main.async { turned.fulfill() }
            wait(for: [turned], timeout: 3)
        }
    }

    /// Runs `body` on a thread of its own, which is not the main one, and spins
    /// the run loop until it is done. `ran` records which thread it was.
    private func onAThread(_ ran: Calls, _ body: @escaping @Sendable () -> Void) {
        let done = expectation(description: "the other thread's work finished")
        let thread = Thread {
            ran.call(body)
            done.fulfill()
        }
        thread.start()
        wait(for: [done], timeout: 5)
    }
}

/// A value a row carries into a `@Sendable` closure, which may run on another
/// thread; only one thread touches it at a time.
private final class Unsafe<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Stands for an engine that the watch's closure holds.
private final class Probe: @unchecked Sendable {}

private struct WeakProbe {
    weak var value: Probe?
    init(_ probe: Probe) { value = probe }
}

/// Stands for an engine that stops the watch whose closure holds it, when it
/// is let go of.
private final class Engine: @unchecked Sendable {
    weak var watch: StoreWatch?
    private let ended: Flag
    init(_ ended: Flag) { self.ended = ended }
    deinit {
        watch?.stop()
        ended.raise()
    }
}

private struct WeakEngine {
    weak var value: Engine?
    init(_ engine: Engine) { value = engine }
}

/// Raised once, and remembers on which thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    private var main: Bool?
    var isRaised: Bool { lock.withLock { raised } }
    var raisedOnMain: Bool? { lock.withLock { main } }
    func raise() {
        let onMain = Thread.isMainThread
        lock.withLock {
            raised = true
            main = onMain
        }
    }
}

/// Keeps what it is given for the life of the process.
private final class Immortal: @unchecked Sendable {
    static let shared = Immortal()
    private let lock = NSLock()
    private var kept: [AnyObject] = []
    func keep(_ object: AnyObject) { lock.withLock { kept.append(object) } }
}

private final class Holder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// What a watch's callback did: how many times, on which thread, how deep, and
/// anything it wrote down.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    private var onMain: [Bool] = []
    private var depth = 0
    private var deepestSeen = 0
    private var written: [String] = []
    private var waiter: (count: Int, reached: XCTestExpectation)?

    var count: Int { lock.withLock { total } }
    var allOnMain: Bool { lock.withLock { !onMain.isEmpty && !onMain.contains(false) } }
    var ranOffMain: Bool { lock.withLock { !onMain.isEmpty && !onMain.contains(true) } }
    var deepest: Int { lock.withLock { deepestSeen } }
    var notes: [String] { lock.withLock { written } }

    func call(_ body: () -> Void = {}) {
        let main = Thread.isMainThread
        lock.withLock {
            total += 1
            onMain.append(main)
            depth += 1
            deepestSeen = max(deepestSeen, depth)
            if let w = waiter, total >= w.count {
                w.reached.fulfill()
                waiter = nil
            }
        }
        body()
        lock.withLock { depth -= 1 }
    }

    func note(_ text: String) { lock.withLock { written.append(text) } }

    func arm(_ count: Int, _ reached: XCTestExpectation) {
        lock.withLock {
            if total >= count { reached.fulfill() } else { waiter = (count, reached) }
        }
    }
}
