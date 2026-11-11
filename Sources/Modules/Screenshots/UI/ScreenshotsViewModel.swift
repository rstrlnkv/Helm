import SwiftUI
import HelmRuntime
import Module_Screenshots_Engine

/// What the model asks of the engine: the state it last read, a fresh read, and the
/// ports a capture is made from.
protocol ScreenshotsWork: AnyObject, Sendable {
    /// The last state, then every later one, in order; registered before it returns.
    func stream() -> AsyncStream<ScreenshotsState>
    /// Reads again; the answer comes on the stream.
    func refresh()
    /// A session on the real ports. The only way the UI target reaches them: a frame
    /// never crosses this port, the session lives here and holds it.
    func session(store: NamespacedStore, naming: @escaping () -> ShotNaming) -> CaptureSession
}

extension ScreenshotsEngine: ScreenshotsWork {}

/// What the settings page knows about the world outside Helm (the folder and the
/// system's boxes, as the engine last read them), and the capture a shortcut starts.
///
/// Built once by `ScreenshotsDescriptor.makeModule`, so it lives as long as the module is
/// switched on and the page reads it instead of owning it. Its init asks the engine for
/// nothing but its stream; the session and the capture controller are built at the first press, because
/// they make the capture ports, a panel and a toast.
@MainActor public final class ScreenshotsViewModel: ObservableObject {
    @Published private(set) var state = ScreenshotsState.unread
    /// The module's settings, which the page reads and writes and the session is built over.
    let store: NamespacedStore
    private let work: any ScreenshotsWork
    /// The one way to the engine. A stopped model has none, so no call site can forget.
    private var door: (any ScreenshotsWork)? { closed ? nil : work }
    private var closed = false
    private var eventsTask: Task<Void, Never>?
    private var capture: CaptureController?
    private let makeController: (NamespacedStore, CaptureSession) -> CaptureController

    /// `makeController` is a seam for a test, which must not put a real overlay on the
    /// screen of whoever runs the suite; the running app passes nothing.
    init(work: any ScreenshotsWork, store: NamespacedStore,
         makeController: @escaping (NamespacedStore, CaptureSession) -> CaptureController =
            { CaptureController(store: $0, session: $1) }) {
        self.work = work
        self.store = store
        self.makeController = makeController
        let news = work.stream()
        eventsTask = Task { [weak self] in
            for await state in news {
                guard let self, !self.closed else { break }
                self.state = state
            }
        }
    }

    /// Ends the event loop, which unregisters the engine's subscriber.
    deinit { eventsTask?.cancel() }

    /// A shortcut's press, from the host. A press while a capture is already open or in
    /// flight is dropped by the controller: the overlay is one machine, and a second
    /// freeze over the first would photograph the overlay.
    func press(_ hotkey: ScreenshotsHotkey) {
        guard let door else { return }
        let controller = capture ?? makeController(store, door.session(store: store, naming: { ScStr.naming }))
        capture = controller
        controller.begin(hotkey)
    }

    /// Asked on every opening of the page and whenever Helm comes back to the
    /// front: the folder and the boxes are changed in System Settings, which
    /// means this window is behind while it happens.
    func refresh() { door?.refresh() }

    /// The host calls this before the engine's `deactivate()`: the model hears nothing
    /// more and asks nothing more, and the capture goes with it. The press is cancelled,
    /// and the overlay, the bar, the toast and the pins are closed: windows nothing else
    /// owns, left up by a switch that came in the middle of a capture or after it.
    func stop() {
        closed = true
        eventsTask?.cancel(); eventsTask = nil
        capture?.teardown()
        capture = nil
    }
}
