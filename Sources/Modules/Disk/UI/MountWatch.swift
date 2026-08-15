import AppKit
import Foundation

/// Disks appearing and disappearing, for as long as this object is held.
///
/// A separate type because its `deinit` is the whole point and a `@MainActor`
/// class cannot have one that reads its own tokens — Swift 6 refuses a
/// nonisolated `deinit` touching non-`Sendable` state, which is how «the
/// observer nobody takes out» gets written by accident. Here the subscription
/// *is* the lifetime, so there is nothing left to remember.
///
/// `NSWorkspace`'s own centre, not `NotificationCenter.default`: these two
/// notifications are posted there and nowhere else. Delivered on the main
/// queue, where every reader of this lives. Local to Disk while Disk is the
/// only module that wants it; a second one moves it to `HelmRuntime`.
final class MountWatch {
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
