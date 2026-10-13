import Foundation

/// Tells an engine that keeps a copy of a setting the screen writes that one of
/// the keys it copies was written, so it reads them again.
///
/// **It hands over no value.** The call says "something you named changed" and
/// the engine reads its keys from its own store inside the call, so what it
/// reads is the store as it stands then and never a payload captured earlier.
///
/// **One call per main-loop turn.** A control that writes three keys in a row
/// would otherwise call three times, and the first two calls would read a value
/// that is part new and part old. The announcement is noted when it arrives and
/// the call is made from the main queue after the turn that wrote, so the
/// engine reads all three as the turn left them. That holds for a writer on the
/// main thread. A writer off the main thread changes the store at once and its
/// announcement arrives on a later main turn (`NamespacedStore.set`), so a call
/// may read a value of several keys that is part new, and at least one more
/// call follows, the last with the whole. The call is made on the main thread
/// whichever thread wrote or built the watch. A write made inside the call is
/// not lost and is not delivered inside it: it gives one more call after it.
///
/// **Only the keys it is given.** A write to another key, or to the same short
/// key in another namespace, calls nothing, and an empty set watches nothing —
/// never the whole namespace.
///
/// **Its own engine's writes are not told apart.** `.helmStoreChanged` carries
/// the key in its namespace and neither the writer nor the store
/// (`NamespacedStore.set`), so a write of a named key calls the watch whoever
/// made it, the engine itself included. An engine therefore names no key it
/// writes, or its own write calls it.
///
/// The call is not a person's gesture. It says that something in this process
/// announced a named key — a write by the screen, another window, a second
/// store over the same namespace or the engine itself, or a bare post of
/// `.helmStoreChanged` — and never that a person did. An engine that would
/// treat a change seen inside the call as a person's act names no key that is
/// written unattended, or keeps that act on a command of its own.
///
/// `NamespacedStore.set` announces a write of an equal value too, for it
/// compares nothing. So the call writes no key the watch names, an unchanged
/// value included, or it calls itself on every turn.
///
/// **It ends once.** `stop()` is final and may be called twice and from any
/// thread. A call still queued when it comes is not delivered. Stopped on the
/// main thread, no call begins once `stop()` has returned. Stopped from another
/// thread, a call the main thread has already taken or is making runs once to
/// its end, possibly after `stop()` has returned, so an engine that can be
/// deactivated off the main thread checks, first thing inside the closure, that
/// it is still running. A watch that is released without `stop()` ends as well,
/// in its own `deinit`, because the notification centre keeps the observer
/// until it is removed (ARCHITECTURE.md § An observer outlives the thing it
/// points at). The observer and the queued call hold the watch weakly while
/// they wait and strongly while they run. So a watch dropped while neither runs
/// is never called again; one dropped while either runs, as a drop from another
/// thread can be, lives until that returns, and a call may still be made in
/// that time. The watch holds the closure only until it ends, so a closure that
/// holds its engine does not keep the engine alive afterwards.
///
/// An engine builds the watch before its first read, so that a write between
/// the two is not missed, and takes it down in `deactivate()` and in `deinit`.
/// The closure holds the engine weakly: the engine holds the watch.
///
///     private var settingsWatch: StoreWatch?
///
///     func activate() {
///         settingsWatch = StoreWatch(store, keys: ["chord", "gap"]) { [weak self] in
///             self?.reloadSettings()
///         }
///         reloadSettings()
///     }
///
///     func deactivate() {
///         settingsWatch?.stop()
///         settingsWatch = nil
///     }
///
///     deinit { settingsWatch?.stop() }
public final class StoreWatch: @unchecked Sendable {
    private let store: NamespacedStore
    private let keys: Set<String>
    private let lock = NSLock()
    /// Guarded by `lock`. Nil once the watch has ended, which is what both
    /// `heard` and `deliver` read to refuse.
    private var onChange: (@Sendable () -> Void)?
    private var observer: NSObjectProtocol?
    /// Guarded by `lock`. A call is queued on the main queue and has not run.
    /// `deliver` clears it before it calls, so a write made inside the call
    /// queues the next one.
    private var due = false

    /// Building it starts the watch.
    public init(_ store: NamespacedStore, keys: Set<String>, onChange: @escaping @Sendable () -> Void) {
        self.store = store
        self.keys = keys
        self.onChange = onChange
        // `queue: nil`: the note is judged on the posting thread and only the
        // call is moved to main. The closure holds the watch weakly, as the
        // centre outlives it.
        observer = NotificationCenter.default.addObserver(
            forName: .helmStoreChanged, object: nil, queue: nil
        ) { [weak self] note in self?.heard(note) }
    }

    deinit { stop() }

    /// Final, idempotent and callable from any thread.
    public func stop() {
        // Both are let go after the lock is released: dropping the closure may
        // drop the engine, whose `deinit` stops this watch and takes the lock.
        let (token, released) = lock.withLock { () -> (NSObjectProtocol?, (@Sendable () -> Void)?) in
            defer { observer = nil; onChange = nil; due = false }
            return (observer, onChange)
        }
        if let token { NotificationCenter.default.removeObserver(token) }
        withExtendedLifetime(released) {}
    }

    private func heard(_ note: Notification) {
        guard keys.contains(where: { store.changed(note, is: $0) }) else { return }
        let queue = lock.withLock { () -> Bool in
            guard onChange != nil, !due else { return false }
            due = true
            return true
        }
        if queue { DispatchQueue.main.async { [weak self] in self?.deliver() } }
    }

    private func deliver() {
        let call = lock.withLock { () -> (@Sendable () -> Void)? in
            due = false
            return onChange
        }
        call?()
    }
}
