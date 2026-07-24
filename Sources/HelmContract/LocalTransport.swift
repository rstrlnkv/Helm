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
    private var lastEvent: EngineEvent?

    public init() {}

    public var events: AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            let replay = lastEvent
            lock.unlock()
            if let replay { continuation.yield(replay) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers[id] = nil; self.lock.unlock()
            }
        }
    }

    public func setHandler(_ h: @escaping Handler) { handler = h }

    public func emit(_ e: EngineEvent) {
        lock.lock(); lastEvent = e; let conts = Array(subscribers.values); lock.unlock()
        for c in conts { c.yield(e) }
    }

    public func send(_ c: EngineCommand) async throws -> Data { try await handler(c) }
}
