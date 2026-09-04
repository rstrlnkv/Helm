import AppKit

/// Which application is in front, readable from any thread.
///
/// `NSWorkspace` is main-thread-only. Reading it from anywhere else does not
/// give stale data — it takes the process down, and ARCHITECTURE.md § Running
/// applications carries the stack trace from the four releases where the VPN
/// engine proved it.
///
/// The Keyboard module then proved it a second time. `frontmostBundleID` read
/// `NSWorkspace.shared.frontmostApplication` on whatever thread asked, which was
/// survivable while the callers were the tap's own main-thread callback — and
/// stopped being survivable the moment the gesture moved to a background queue
/// to keep a slow accessibility call off the main run loop. Eight call sites
/// went with it.
///
/// So the same answer `RunningApps` already gives: AppKit is read on the main
/// thread, from the workspace notification that arrives there anyway, and every
/// other thread reads the snapshot. There is no way to offer "who is in front,
/// right now, from a background queue", so this does not offer one. A caller off
/// the main thread gets who was in front a moment ago — which, for deciding
/// whether a conversion may touch the app the person is typing in, is the same
/// answer.
public final class FrontmostApp: @unchecked Sendable {
    public static let shared = FrontmostApp()

    private let lock = NSLock()
    private var snapshot = ""
    private var watchers: [UUID: (String) -> Void] = [:]

    private init() {}

    /// On the main thread this reads AppKit and refreshes. Off it, this returns
    /// the snapshot and never touches AppKit at all.
    public func bundleID() -> String {
        if Thread.isMainThread { return refresh() }
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    /// Main thread only. Off it this refuses and leaves the snapshot alone,
    /// because this type exists to stop a wrong-thread read, and it will not
    /// perform one to report that a wrong-thread read happened. Debug builds
    /// trap so the caller is found here rather than in a crash log.
    @discardableResult
    public func refresh() -> String {
        guard Thread.isMainThread else {
            assertionFailure("FrontmostApp.refresh() off the main thread")
            lock.lock(); defer { lock.unlock() }
            return snapshot
        }
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        lock.lock()
        let changed = snapshot != current
        snapshot = current
        lock.unlock()
        if changed { tell(current) }
        return current
    }

    /// Keeps the snapshot current without anybody having to ask. The
    /// notification arrives on the main thread already.
    public func startObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// **Told, not asked.** A caller that wants to act when the front
    /// application changes had no way to hear it and would have added a second
    /// observer for a notification this type already owns — and `NSWorkspace`
    /// is main-thread-only, which is why there is exactly one observer.
    ///
    /// The handler runs on the main thread, with the new bundle id, and only
    /// when it differs from the last one delivered: coming back to a window you
    /// were already in is not a change, and a caller acting on it would select
    /// an input source for nothing.
    ///
    /// The token is the caller's to keep and to hand back. A watcher that
    /// cannot be stopped is a watcher that outlives whatever owned it.
    @discardableResult
    public func onChange(_ handler: @escaping (String) -> Void) -> UUID {
        let token = UUID()
        lock.lock(); watchers[token] = handler; lock.unlock()
        return token
    }

    public func stopWatching(_ token: UUID) {
        lock.lock(); watchers.removeValue(forKey: token); lock.unlock()
    }

    /// Every watcher, on the main thread, outside the lock.
    ///
    /// Outside deliberately: a handler is other people's code and may call
    /// straight back into this type, and a lock held across a call out is the
    /// shape `LocalTransport.setHandler` is on record for.
    private func tell(_ bundleID: String) {
        lock.lock(); let handlers = Array(watchers.values); lock.unlock()
        for handler in handlers { handler(bundleID) }
    }

    /// Tests only: seeds the snapshot without AppKit, and tells the watchers,
    /// because the whole point of the seam is that a test can drive what the
    /// workspace would have driven.
    public func setForTesting(_ bundleID: String) {
        lock.lock()
        let changed = snapshot != bundleID
        snapshot = bundleID
        lock.unlock()
        if changed { tell(bundleID) }
    }
}
