import Foundation

/// Tells an engine that something happened in a watched folder.
///
/// Shared plumbing, in `HelmRuntime` because two modules now need it: Autopilot
/// watches the folders its rules name, and the Uninstaller watches `~/.Trash` so
/// that dragging an app there is noticed while Helm is running. It lived inside
/// Autopilot until the second caller appeared — which is the point at which the
/// house rule says it moves rather than being written twice.
///
/// FSEvents rather than a poll, because "a file appeared and was sorted a
/// moment later" is the behaviour the module is for. It is not enough on its
/// own: a rule that says "older than 30 days" becomes true with nothing
/// happening at all, and no event will ever fire for it — hence the sweep on a
/// timer beside this. Two triggers, because neither one covers the other.
public final class FolderWatcher: @unchecked Sendable {

    /// What the stream's context points at, and the reason the stream is not
    /// given the watcher.
    ///
    /// **The stream holds this object and never the watcher.** The context's
    /// retain and release make FSEvents keep the sink from the stream's creation
    /// to its deallocation, so a delivery still pending when the watcher goes
    /// finds a live object, and the callback resolves nothing else. A callback
    /// that resolved the watcher could be inside it when the last reference was
    /// dropped on another thread, and the runtime aborts the process for an
    /// object freed while something still holds it. The watcher stays unretained
    /// by the stream: retaining it would keep it alive until the stream is
    /// stopped, and for an owner that only drops the watcher nothing stops the
    /// stream but the watcher's own `deinit`
    /// (ARCHITECTURE.md § An observer outlives the thing it points at).
    ///
    /// **Only the watcher's queue touches the stream.** `start` and `stopStream`
    /// run there, and so does every callback, so none is in flight while the
    /// stream is stopped and invalidated. When `deinit` returns, this object is
    /// held by the block it has put on that queue, and that block stops the
    /// stream before it lets go. That is why `stream` needs no lock and `action`
    /// does: `clear` comes from whatever thread ran `deinit`.
    ///
    /// **Clearing the action ends the watcher's callbacks at the drop, before
    /// the stream is stopped.** A delivery that begins after `clear` finds a
    /// live sink with nothing to call. One that took the action out just before
    /// the clear still runs it once; it touches the closure and nothing of the
    /// watcher. `fire` calls the action outside the lock: under it, `clear`
    /// would park the thread that dropped the watcher behind a callback whose
    /// length is the caller's, and a callback that dropped its own watcher would
    /// wait for itself.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (@Sendable ([String]) -> Void)?
        /// Read and written on the watcher's queue only.
        private var stream: FSEventStreamRef?

        init(_ action: @escaping @Sendable ([String]) -> Void) { self.action = action }

        func fire(_ changed: [String]) {
            lock.lock()
            let action = action
            lock.unlock()
            action?(changed)
        }

        func clear() {
            lock.lock()
            action = nil
            lock.unlock()
        }

        /// Whether a stream is running when this returns.
        func start(_ folders: [String], on queue: DispatchQueue) -> Bool {
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    return UnsafeRawPointer(Unmanaged<Sink>.fromOpaque(info).retain().toOpaque())
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<Sink>.fromOpaque(info).release()
                },
                copyDescription: nil)

            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info, let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                    as UnsafeMutablePointer<UnsafePointer<CChar>?>? else { return }
                let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
                var changed: [String] = []
                for index in 0..<count {
                    if let raw = paths[index] { changed.append(String(cString: raw)) }
                }
                sink.fire(changed)
            }

            // A second of latency: a download in progress writes many times, and
            // acting on the first write would move a half-written file. Coalescing
            // is the difference between a rule that works and one that corrupts.
            // The first event of a quiet folder waits it out too, which is why
            // `kFSEventStreamCreateFlagNoDefer` is absent: with it the first event
            // would be delivered at once and only those behind it would wait.
            // `AWatchedFoldersFirstEventWaitsOutItsLatencyTests` holds that the
            // first delivery comes no sooner than 0.9 s after the writer was
            // launched, which is before the write. It is a wait, not a
            // guarantee that the writer has finished.
            stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, folders as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                                         kFSEventStreamCreateFlagIgnoreSelf))
            guard let stream else { return false }
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                // A stream that never started must not be stopped — and leaving it in
                // `self.stream` would have `stopStream` do exactly that, on a stream
                // FSEvents never started. Released here, so the next `watch` builds
                // a fresh one rather than reusing a dead handle.
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
                return false
            }
            return true
        }

        func stopStream() {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private let queue = DispatchQueue(label: "helm.rules.watcher")
    /// Not private so that a test can hold it weakly and see it leave memory
    /// once the watcher is dropped; nothing else reads it.
    let sink: Sink

    public init(onChange: @escaping @Sendable ([String]) -> Void) {
        sink = Sink(onChange)
    }

    /// **Calls no FSEvents function.** This runs on whichever thread dropped the
    /// last reference, while a callback may be running on the queue, so the
    /// stream is not stopped here. It clears the action, so a callback that
    /// begins after this returns calls nothing, and puts one block on the queue
    /// that stops the stream there, behind any callback in flight. The block
    /// holds the sink and not `self`, which is already dying; and it is put on
    /// the queue even when no stream is running, because whether one is belongs
    /// to the queue to say.
    deinit {
        sink.clear()
        queue.async { [sink] in sink.stopStream() }
    }

    /// Replaces whatever was being watched. Called when the folder list
    /// changes, which is rare enough that rebuilding the stream is simpler than
    /// adding to it — and an FSEvents stream cannot have paths added anyway.
    ///
    /// **`started` is how a caller finds out that it is not watching anything.**
    /// This used to answer nothing at all: `FSEventStreamStart`'s return was
    /// discarded and a nil from `FSEventStreamCreate` returned silently, so both
    /// engines logged that they were watching a folder with no way to know whether
    /// they were — the Uninstaller's switch said «on» over a Trash nothing was
    /// looking at. Watching *nothing* answers `false` too: an empty folder list is
    /// how a caller reaches this with nothing to do, and that is not a stream.
    ///
    /// A channel rather than a return value, and the queue is the reason: the work
    /// is handed to this instance's serial queue, where the change callbacks are
    /// delivered as well — so a `queue.sync` here would park whoever asked, up to
    /// and including the thread that draws, until a change notification finished.
    /// How long a callback takes is the caller's decision, not this class's:
    /// Autopilot's used to read a keychain item on this queue before it learned
    /// to enqueue instead, and nothing stops the next caller doing the same.
    public func watch(_ folders: [String], started: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { [self] in
            sink.stopStream()
            guard !folders.isEmpty else { started?(false); return }
            started?(sink.start(folders, on: queue))
        }
    }

    /// Stops the stream and leaves the action in place, so a stopped watcher can
    /// be asked to `watch` again; only `deinit` ends the action.
    public func stop() { queue.async { [self] in sink.stopStream() } }
}
