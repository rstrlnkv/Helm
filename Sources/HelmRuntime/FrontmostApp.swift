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
        lock.lock(); snapshot = current; lock.unlock()
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

    /// Tests only: seeds the snapshot without AppKit.
    public func setForTesting(_ bundleID: String) {
        lock.lock(); snapshot = bundleID; lock.unlock()
    }
}
