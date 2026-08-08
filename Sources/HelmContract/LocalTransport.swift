import Foundation

/// In-process transport. `events` is a BROADCAST stream: every access returns a
/// fresh `AsyncStream`, and `emit` fans out to all live subscribers. (A plain
/// single `AsyncStream` is single-consumer — the second `for await` would starve,
/// which is exactly what broke a module that builds its own view model on top of
/// the host's generic one.)
public final class LocalTransport: EngineTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (EngineCommand) async throws -> Data
    private let lock = NSLock()
    private var handler: Handler = { _ in Data() }
    private var subscribers: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]
    /// Last emitted event, replayed to every new subscriber. Engine state is
    /// level-triggered (the last "state" IS the current truth), so a late
    /// subscriber — e.g. a view model built AFTER the engine already emitted its
    /// initial state during `activate()` — must still see it, or the UI stays
    /// stuck at defaults (toggle reads off while the engine is actually active).
    /// Keyed by name, not one slot.
    ///
    /// One slot is right for one event name and wrong for two. Homebrew emits
    /// `opLog` (a streaming line) and `opState` (level-triggered state) into the
    /// same engine: closing and reopening its page during a `brew upgrade` gave
    /// the new view model whichever arrived last, and log lines stream
    /// continuously — so the page came back idle, buttons live, with an
    /// operation still running behind it. Disk sits one event name away from
    /// the same defect.
    private var lastEvents: [String: EngineEvent] = [:]
    /// Replayed in the order the names first appeared, so a subscriber sees
    /// state in the sequence the engine established rather than a dictionary's.
    private var eventOrder: [String] = []

    public init() {}

    public var events: AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            // **The history goes out before the subscriber goes live, and both
            // happen under the one lock.** Registering first and yielding the
            // replay afterwards left a window: an `emit` landing in it reached
            // the new subscriber immediately, and the replay — older by
            // definition — followed it. The stream then carried the new state
            // and then the state it had replaced, and a view model that assigns
            // what it receives ends on the stale one. That is precisely the
            // defect this replay exists to prevent, produced by the replay
            // itself; measured at 26 rounds in 60 (`ReplayOrderTests`).
            //
            // Yielding while holding the lock is safe here and is the point: an
            // `emit` during the replay blocks until it is done and is delivered
            // after it, in order. `yield` appends to an unbounded buffer and
            // resumes the consumer on its own executor — it runs no consumer
            // code inline, and `onTermination` is not called from it, so there
            // is nothing to re-enter this lock.
            for name in eventOrder {
                if let event = lastEvents[name] { continuation.yield(event) }
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

    public func setHandler(_ h: @escaping Handler) {
        // Under the same lock as everything else here. It is set once during
        // `init` today, but it was the single unguarded field in a class whose
        // own comment explains why it needs a lock.
        lock.lock(); handler = h; lock.unlock()
    }

    public func emit(_ e: EngineEvent) {
        lock.lock()
        if lastEvents[e.name] == nil { eventOrder.append(e.name) }
        lastEvents[e.name] = e
        let conts = Array(subscribers.values)
        lock.unlock()
        for c in conts { c.yield(e) }
    }

    /// The handler, read under the lock.
    ///
    /// A synchronous property because Swift 6 makes `NSLock.lock()` unavailable
    /// from an `async` context outright — which is very likely why the read was
    /// left unguarded when `setHandler` was given the lock. A lock taken on one
    /// side of a field guards nothing, and this class is `@unchecked Sendable`,
    /// so the compiler is trusting the author for exactly this.
    private var currentHandler: Handler {
        lock.lock(); defer { lock.unlock() }
        return handler
    }

    /// The lock is released before the handler runs, and that is not an
    /// oversight: the handler is engine work, and every `emit` it makes would
    /// deadlock against a lock its own caller still held.
    public func send(_ c: EngineCommand) async throws -> Data {
        try await currentHandler(c)
    }
}
