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
            subscribers[id] = continuation
            let replay = eventOrder.compactMap { lastEvents[$0] }
            lock.unlock()
            for event in replay { continuation.yield(event) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers[id] = nil; self.lock.unlock()
            }
        }
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

    public func send(_ c: EngineCommand) async throws -> Data { try await handler(c) }
}
