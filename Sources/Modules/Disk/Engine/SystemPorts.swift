import AppKit
import Foundation

extension SystemVolumeCapacity {
    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        MountWatch(onChange)
    }
}

/// Disks appearing and disappearing, for as long as this object is held.
///
/// A separate type because its `deinit` is the whole point, and Swift 6
/// refuses a `@MainActor` class a nonisolated `deinit` that reads its own
/// non-`Sendable` tokens. Here the subscription *is* the lifetime.
///
/// `NSWorkspace`'s own centre, not `NotificationCenter.default`: these two
/// notifications are posted there and nowhere else. Delivered on the main
/// queue, where every reader of this lives.
private final class MountWatch {
    private let tokens: [NSObjectProtocol]

    init(_ onChange: @escaping @Sendable () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        tokens = [NSWorkspace.didMountNotification,
                  NSWorkspace.didUnmountNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in onChange() }
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
    }
}
