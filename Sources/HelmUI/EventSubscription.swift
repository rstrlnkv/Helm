import HelmContract

/// One view model's loop over its engine's events, as an object that owns the task
/// and can end it.
///
/// **The stream is taken before the task and the task holds neither this object
/// nor the model.** `Task { [weak self] in await self?.observeEvents() }` resolves
/// its weak capture once, and the method then holds `self` for as long as it runs,
/// which over a stream that never finishes is the life of the app: a `deinit` that
/// cancels the task never runs. Here the loop is `for await` over a stream captured
/// ahead of the task, and the model is reached again for every event through the
/// closure the caller wrote, `[weak self]` in it.
///
/// `cancel()` ends the loop, and with it the subscriber on the transport
/// (`LocalTransport.subscriberCount` falls): on the same line when the loop is
/// already waiting for an event, and when the task first runs if it is
/// cancelled before that. `ModuleUICache.shared` calls it on the subscription a
/// model named through `events` when it drops or replaces that model, so such
/// a model is not subscribed any more though nobody has released it yet. The
/// subscription cancels itself in `deinit` as well, for a model released
/// without passing through the cache.
@MainActor public final class EventSubscription {
    private var task: Task<Void, Never>?

    /// Starts listening at once: `events` is the stream of the transport, taken
    /// by the caller in the same statement, so the transport counts the subscriber
    /// from here.
    public init(_ events: AsyncStream<EngineEvent>,
                handle: @escaping @MainActor (EngineEvent) -> Void) {
        task = Task {
            for await event in events {
                if Task.isCancelled { break }
                handle(event)
            }
        }
    }

    /// Ends the loop. Cancelling again does nothing.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
