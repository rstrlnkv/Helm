import Foundation

/// A block run after a delay for exactly as long as its token is held: releasing
/// the token cancels it, so an engine that drops its token in `stop()`,
/// `deactivate()` or `deinit` cannot have a tick land afterwards.
///
/// The queue is the caller's choice and the caller says why: Keep Awake's clock
/// ticks on main, Homebrew's ticker never does.
public enum DelayedWork {
    public static func schedule(on queue: DispatchQueue, after interval: TimeInterval,
                                _ block: @escaping @Sendable () -> Void) -> AnyObject {
        let item = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + interval, execute: item)
        return Token(item)
    }

    private final class Token {
        private let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        deinit { item.cancel() }
    }
}
