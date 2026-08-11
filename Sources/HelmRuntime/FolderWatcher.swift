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
    public func watch(_ folders: [String]) {
        queue.async { [self] in
            stopStream()
            guard !folders.isEmpty else { return }
            start(folders)
        }
    }

    public func stop() { queue.async { [self] in stopStream() } }

    private func start(_ folders: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                as UnsafeMutablePointer<UnsafePointer<CChar>?>? else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            var changed: [String] = []
            for index in 0..<count {
                if let raw = paths[index] { changed.append(String(cString: raw)) }
            }
            watcher.onChange(changed)
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
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
