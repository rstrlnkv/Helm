import Foundation

/// Tells an engine that something happened in a watched folder.
///
/// Shared plumbing: Autopilot watches the folders its rules name, and the
/// Uninstaller watches `~/.Trash` so that dragging an app there is noticed
/// while Helm is running.
///
/// FSEvents rather than a poll, because "a file appeared and was sorted a
/// moment later" is the behaviour the module is for. It is not enough on its
/// own: a rule that says "older than 30 days" becomes true with nothing
/// happening at all, and no event will ever fire for it — hence the sweep on a
/// timer beside this. Two triggers, because neither one covers the other.
public final class FolderWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "helm.rules.watcher")
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable ([String]) -> Void

    public init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }

    deinit { stopStream() }

    /// Replaces whatever was being watched. Called when the folder list
    /// changes, which is rare enough that rebuilding the stream is simpler than
    /// adding to it — and an FSEvents stream cannot have paths added anyway.
    ///
    /// **`started` is how a caller finds out that it is not watching anything**:
    /// a nil from `FSEventStreamCreate` or a false from `FSEventStreamStart`, so
    /// a switch does not say «on» over a folder nothing is looking at. Watching
    /// *nothing* (an empty list) answers `false` too.
    ///
    /// A channel rather than a return value: the work runs on this instance's
    /// serial queue, where change callbacks are delivered too, so a
    /// `queue.sync` here would park whoever asked, the thread that draws
    /// included, behind a callback whose length is the caller's decision.
    public func watch(_ folders: [String], started: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { [self] in
            stopStream()
            guard !folders.isEmpty else { started?(false); return }
            started?(start(folders))
        }
    }

    public func stop() { queue.async { [self] in stopStream() } }

    /// Whether a stream is running when this returns.
    private func start(_ folders: [String]) -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                as UnsafeMutablePointer<UnsafePointer<CChar>?>? else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange((0..<count).compactMap { index in paths[index].map { String(cString: $0) } })
        }

        // A second of latency: a download in progress writes many times, and
        // acting on the first write would move a half-written file. Coalescing
        // is the difference between a rule that works and one that corrupts.
        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, folders as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                                     kFSEventStreamCreateFlagNoDefer |
                                     kFSEventStreamCreateFlagIgnoreSelf))
        guard let stream else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            // A stream that never started must not be stopped, so it is not left
            // in `self.stream` for `stopStream`. Released here, so the next
            // `watch` builds a fresh one.
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }
        return true
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
