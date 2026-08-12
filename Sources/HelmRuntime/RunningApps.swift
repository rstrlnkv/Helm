import AppKit
import Foundation

/// Who is running, readable from any thread.
///
/// `NSWorkspace.runningApplications` is main-thread-only, and reading it from
/// anywhere else is not merely stale — it crashes. AppKit keeps the list in a
/// mutable array behind a KVO helper; `-applications` copies that array under a
/// lock while the main thread mutates it as apps come and go. Helm's VPN engine
/// read it from its own serial queue, and quitting an app at the wrong instant
/// segfaulted the whole program inside `_cow_copy`:
///
/// ```
/// Thread 0  -[NSWorkspaceApplicationKVOHelper removeApplication:]   ← mutating
/// Thread 9  -[NSWorkspaceApplicationKVOHelper applications]         ← copying
///           __NSArrayM_copy → _cow_copy → EXC_BAD_ACCESS at 0x0
/// ```
///
/// So the list is read where AppKit publishes it — on the main thread — and
/// kept as a snapshot everything else reads. A caller on a background queue
/// gets the last snapshot, which is what it wanted anyway: a set of bundle
/// identifiers as of a moment ago. There is no version of "the live list, off
/// the main thread" that is safe to offer, so this does not offer one.
public final class RunningApps: @unchecked Sendable {
    public static let shared = RunningApps()

    private let lock = NSLock()
    private var snapshot: Set<String> = []
    /// Where each running identifier's bundle is, taken in the same main-thread
    /// read as the identifiers themselves.
    ///
    /// Here rather than asked for on demand for the reason the whole class exists:
    /// `NSRunningApplication` is AppKit's, and a caller on a background queue
    /// asking «where is the bundle for this id» would be the same crash the
    /// identifiers were moved here to avoid. Two instances of one identifier
    /// collapse to one entry, which is what the identifier-set diff above does
    /// too — a bundle squatting a running app's identifier is invisible to both,
    /// and `VPNRuleTrust` says why that is the safe direction.
    private var bundleURLs: [String: URL] = [:]
    private var seeded = false

    private init() {}

    /// The bundle identifiers of every running application.
    ///
    /// On the main thread this reads AppKit and refreshes the snapshot. Off it,
    /// this returns the snapshot and never touches AppKit at all.
    public func bundleIDs() -> Set<String> {
        if Thread.isMainThread { return refresh() }
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    /// Reads AppKit and stores the result. Main thread only — callers that are
    /// already there (a KVO callback, a workspace notification) should call
    /// this so the snapshot is current before they hand control onwards.
    ///
    /// Off the main thread it refuses and returns the snapshot unchanged —
    /// this type exists because reading the live list from the wrong thread
    /// killed the process, and shipping code will not repeat that even to
    /// report a mistake. Debug and test builds do trap, deliberately: a
    /// wrong-thread caller should be found here rather than in a crash log.
    @discardableResult
    public func refresh() -> Set<String> {
        guard Thread.isMainThread else {
            assertionFailure("RunningApps.refresh() off the main thread")
            lock.lock(); defer { lock.unlock() }
            return snapshot
        }
        let running = NSWorkspace.shared.runningApplications
        let current = Set(running.compactMap(\.bundleIdentifier))
        let urls = running.reduce(into: [String: URL]()) { map, app in
            if let id = app.bundleIdentifier, let url = app.bundleURL { map[id] = url }
        }
        lock.lock()
        snapshot = current
        bundleURLs = urls
        seeded = true
        lock.unlock()
        return current
    }

    /// Where the bundle of the instance running under that identifier is, as of
    /// the last snapshot. Nil when nothing of that identifier is running, or when
    /// macOS did not say where it came from.
    public func bundleURL(of bundleID: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return bundleURLs[bundleID]
    }

    /// Refreshes on the main thread, then runs the block there. For an
    /// observer that may or may not already be on it.
    public func refreshOnMain(then done: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            refresh()
            done()
        } else {
            DispatchQueue.main.async { [self] in
                refresh()
                done()
            }
        }
    }

    /// Whether the snapshot has ever been filled. A background caller reading
    /// before the first refresh gets an empty set, which reads as "nothing is
    /// running" — worth being able to tell apart in a test.
    public var hasSnapshot: Bool {
        lock.lock(); defer { lock.unlock() }
        return seeded
    }

    /// Test seam: fills the snapshot without AppKit. The bundle locations come
    /// with it, because a snapshot that knows who is running and not where they
    /// came from is a state the real read cannot be in.
    func seed(_ ids: Set<String>, urls: [String: URL] = [:]) {
        lock.lock()
        snapshot = ids
        bundleURLs = urls
        seeded = true
        lock.unlock()
    }
}
