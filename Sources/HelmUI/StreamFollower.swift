/// Follows an engine's stream for a view model: each element goes to `apply`
/// on the main actor, with the owner as an argument.
///
/// The caller passes the stream already taken, synchronously in its `init`,
/// before the first suspension: `EngineNews.stream()` registers the subscriber
/// and replays the latest state in one step, so nothing emitted from then on is
/// missed. The task holds the owner weakly and re-acquires it per element, and
/// `apply` captures nothing, so there is no cycle. `Task.isCancelled` is read
/// before each element, so one already buffered is not applied after `cancel()`.
///
/// `cancel()` is what the model's `stop()` calls, the explicit teardown a page
/// that outlives its module needs; the `deinit` is only the backstop for a model
/// dropped without `stop()`.
@MainActor public final class StreamFollower {
    private let task: Task<Void, Never>

    public init<Owner: AnyObject, Element>(_ stream: AsyncStream<Element>, owner: Owner,
                                           _ apply: @escaping @MainActor (Owner, Element) -> Void) {
        task = Task { [weak owner] in
            for await element in stream {
                guard !Task.isCancelled, let owner else { break }
                apply(owner, element)
            }
        }
    }

    public func cancel() { task.cancel() }

    deinit { task.cancel() }
}
