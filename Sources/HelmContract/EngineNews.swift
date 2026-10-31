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
    /// that comes after the engine has spoken must still see it. Today that is a
    /// test: in the app the model subscribes before `activate()`
    /// (`ModuleHost.makeLive`), and no engine says anything in `init`.
    /// Keyed by slot, not one value.
    ///
    /// One slot is right for one kind of news and wrong for two. Homebrew says
    /// an operation's log (a streaming line) and its state (level-triggered) into
    /// the same engine: closing and reopening its page during a `brew upgrade` gave
    /// the new model whichever arrived last, and log lines stream continuously —
    /// so the page came back idle, buttons live, with an operation still running
    /// behind it.
    private var last: [String: Value] = [:]
    /// Replayed in the order the slots first appeared, so a subscriber sees
    /// state in the sequence the engine established rather than a dictionary's.
    private var order: [String] = []

    public init() {}

    /// **The history goes out before the subscriber goes live, and both
    /// happen under the one lock.** Registering first and yielding the
    /// replay afterwards left a window: a `say` landing in it reached
    /// the new subscriber immediately, and the replay — older by
    /// definition — followed it. The stream then carried the new state
    /// and then the state it had replaced, and a model that assigns
    /// what it receives ends on the stale one. That is precisely the
    /// defect this replay exists to prevent, produced by the replay
    /// itself.
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
    public var subscriberCount: Int {
        lock.lock(); defer { lock.unlock() }
        return subscribers.count
    }

    public func say(_ value: Value, slot: String = "state") {
        lock.lock()
        if last[slot] == nil { order.append(slot) }
        last[slot] = value
        let conts = Array(subscribers.values)
        lock.unlock()
        for c in conts { c.yield(value) }
    }
}
