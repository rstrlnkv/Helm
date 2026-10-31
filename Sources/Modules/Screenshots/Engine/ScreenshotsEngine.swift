import Foundation
import HelmContract
import HelmRuntime

/// The screenshots module's engine: what lives outside Helm and the settings
/// page needs to know, and the ports a capture is made from.
///
/// **It does not capture.** A capture is a frame of tens of megabytes held for
/// as long as the overlay is open, and a frame never crosses the port between a
/// model and an engine. The capture runs in the UI target — `CaptureController` —
/// from a `CaptureSession` built out of the same ports `session(store:naming:)`
/// hands over; the engine's own stream carries the settings page's state and
/// nothing else.
public final class ScreenshotsEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down. It reaches disk
    /// in shapes nothing would flag if they disagreed — the `module.screenshots.*`
    /// keys of a store, and the shortcuts' slots — so the descriptor builds its
    /// id from this. **The string never changes.**
    public static let moduleID = "screenshots"

    private let preferences: CapturePreferences
    private let locations: ScreenshotsLocations
    private let news: EngineNews<ScreenshotsState>
    private let lock = NSLock()
    private var refreshing: Task<Void, Never>?
    private var stopped = false

    public init(preferences: CapturePreferences = SystemCapturePreferences(),
                locations: ScreenshotsLocations = .system,
                news: EngineNews<ScreenshotsState> = EngineNews()) {
        self.preferences = preferences
        self.locations = locations
        self.news = news
    }

    /// A session on the real ports, for the UI target to hold. A factory here
    /// rather than the port types named over there: the ports are this
    /// target's and the UI target should not know which conform.
    public func session(store: NamespacedStore, naming: @escaping () -> ShotNaming) -> CaptureSession {
        CaptureSession(capture: SCKCapture(store: store), writer: FileShotWriter(), trash: SystemShotTrash(),
                       pasteboard: SystemShotPasteboard(), preferences: SystemCapturePreferences(),
                       shutter: SystemShutter(), textReader: VisionTextReader(),
                       settings: { ScreenshotsSettings.read(store) }, naming: naming)
    }

    /// The state, as a stream: the last one first, then every later one, in order.
    ///
    /// **Registered before this returns, in the one hold of the lock that replays
    /// what was last said** (`EngineNews.stream`): reading the state and then
    /// subscribing leaves a window an emit falls into, and subscribing before the
    /// replay hands over an older state after a newer one. Synchronous and not
    /// actor-isolated, so the model takes it in its own synchronous `init`, before
    /// its first suspension; the subscriber is counted when this returns. Ending
    /// the iteration removes the subscriber.
    public func stream() -> AsyncStream<ScreenshotsState> { news.stream() }

    public var subscriberCount: Int { news.subscriberCount }

    public func activate() {
        lock.lock(); stopped = false; lock.unlock()
        refresh()
    }

    /// Stops the read in flight so its result cannot be published after the
    /// module is off. The task holds `self` weakly and checks `stopped`: a task
    /// that resolved its weak capture once holds the object for as long as it
    /// runs, so the cancel belongs here and not in `deinit`.
    public func deactivate() {
        lock.lock()
        stopped = true
        let task = refreshing
        refreshing = nil
        lock.unlock()
        task?.cancel()
    }

    deinit { refreshing?.cancel() }

    /// A synchronous property, because Swift
    /// refuses `NSLock.lock()` across a suspension, and the read is taken on
    /// both sides of one.
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// Reads both domains off the cooperative pool — each is an exchange with
    /// `cfprefsd` — and publishes what they say.
    public func refresh() {
        let task = Task { [weak self] in
            guard let self else { return }
            let state = await self.read()
            guard !Task.isCancelled else { return }
            guard !self.isStopped else { return }
            self.news.say(state)
        }
        lock.lock(); refreshing?.cancel(); refreshing = task; lock.unlock()
    }

    func read() async -> ScreenshotsState {
        let preferences = preferences, locations = locations
        return await offTheCooperativePool {
            let folder = SaveLocation.resolve(raw: preferences.location().value,
                                              desktop: locations.desktop, home: locations.home)
            return ScreenshotsState(folder: folder.url.path, folderRefused: folder.refused,
                                    boxes: SystemShortcuts.boxes(from: preferences.symbolicHotkeys()))
        }
    }
}
