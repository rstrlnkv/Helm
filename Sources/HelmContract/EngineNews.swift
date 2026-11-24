import Foundation

/// What an engine says unasked, to every model that listens. `stream()` is a
/// BROADCAST: every call returns a fresh `AsyncStream`, and `say` fans out to all
/// live subscribers. (A plain single `AsyncStream` is single-consumer — the second
/// `for await` would starve.) Typed values, nothing encoded: the engine and its
/// page are one process.
public final class EngineNews<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Value>.Continuation] = [:]
    /// Last value said in each slot, replayed to every new subscriber. Engine state
    /// is level-triggered (the last "state" IS the current truth), so a subscriber
    /// that comes after the engine has spoken must still see it. In the app the
    /// model subscribes before `activate()` (`ModuleHost.makeLive`); tests may not.
    ///
    /// Keyed by slot, because one value is wrong for two kinds of news: Homebrew
    /// streams an operation's log lines beside its level-triggered state, and a
    /// page reopened mid-operation must get the state, not the last line.
    private var last: [String: Value] = [:]
    /// Replayed in the order the slots first appeared, so a subscriber sees
    /// state in the sequence the engine established rather than a dictionary's.
    private var order: [String] = []

    public init() {}

    /// **The history goes out before the subscriber goes live, and both
    /// happen under the one lock.** Registering first would leave a window
    /// where a `say` reaches the new subscriber before the older replay,
    /// and a model that assigns what it receives ends on the stale state.
    ///
    /// Yielding while holding the lock is safe here and is the point: a
    /// `say` during the replay blocks until it is done and is delivered
    /// after it, in order. `yield` appends to an unbounded buffer and
    /// resumes the consumer on its own executor — it runs no consumer
    /// code inline, and `onTermination` is not called from it, so there
    /// is nothing to re-enter this lock.
    ///
    /// Synchronous, because a model's `init` subscribes and Swift 6 makes
    /// `NSLock.lock()` unavailable from an `async` context outright.
    public func stream() -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            for slot in order {
                if let value = last[slot] { continuation.yield(value) }
            }
            subscribers[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers[id] = nil; self.lock.unlock()
            }
        }
    }

    /// How many consumers are registered right now.
    ///
    /// An observability seam, not a feature: a subscriber that outlives the page
    /// that made it is invisible from the outside, and the only regression guard
    /// that works for it is a count that must not grow.
    public var subscriberCount: Int { lock.withLock { subscribers.count } }

    public func say(_ value: Value, slot: String = "state") {
        lock.lock()
        if last[slot] == nil { order.append(slot) }
        last[slot] = value
        let conts = Array(subscribers.values)
        lock.unlock()
        for c in conts { c.yield(value) }
    }
}
