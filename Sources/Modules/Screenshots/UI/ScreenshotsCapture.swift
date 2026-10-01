import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the overlay produced, ready for whatever comes next.
struct CapturedShot {
    enum Kind { case area, window, display }
    let image: CGImage
    let kind: Kind
}

/// The door a shortcut goes through: the host calls `begin` and nothing else.
///
/// **In-process, and not through the transport.** A 5K display's frozen frame is some
/// sixty megabytes and the transport is `Data` in both directions, so a capture that
/// crossed it would be copied at least twice for nothing. The host's action
/// lands here directly; the engine's own wire carries the settings page's state.
@MainActor public enum ScreenshotsCapture {
    private static var controller: CaptureController?

    /// A press. A press while a capture is already open or in flight is dropped:
    /// the overlay is one machine, and a second freeze over the first would
    /// photograph the overlay.
    public static func begin(_ hotkey: ScreenshotsHotkey, vm: ModuleViewModel, store: NamespacedStore) {
        shared(vm: vm, store: store).begin(hotkey)
    }

    /// Keyed to the host's view model, which is new on every enable, and dropped
    /// with the module: a cached controller would be holding a session built for
    /// an engine that is gone, and an overlay on screen when the module was
    /// switched off would be a window nothing owns.
    private static func shared(vm: ModuleViewModel, store: NamespacedStore) -> CaptureController {
        if let controller, controller.owner === vm { return controller }
        controller?.cancel()
        let created = CaptureController(owner: vm, store: store)
        controller = created
        ModuleUICache.dropWhenDisabled(ScreenshotsDescriptor.id.rawValue) {
            controller?.cancel()
            controller = nil
        }
        return created
    }
}

@MainActor final class CaptureController {
    let owner: ModuleViewModel
    private let store: NamespacedStore
    private let session: CaptureSession
    private let toast = ShotToast()
    private var overlay: CaptureOverlay?
    private var busy = false
    /// The press in flight, held so `cancel` can reach it: the freeze is the one
    /// long wait and the module's switch can be turned inside it.
    private var pressTask: Task<Void, Never>?
    /// Puts the overlay on the screens. A seam for a test, which must see whether
    /// the area shortcut reached it without putting panels on the screen of whoever runs the suite.
    private let presentOverlay: (CaptureOverlay) -> Bool

    /// `session` and `presentOverlay` are seams for a test, which builds a session
    /// over fake ports and counts the presentations; the running app passes
    /// nothing and gets the real ones.
    init(owner: ModuleViewModel, store: NamespacedStore, session: CaptureSession? = nil,
         presentOverlay: @escaping (CaptureOverlay) -> Bool = { $0.present() }) {
        self.owner = owner
        self.store = store
        self.presentOverlay = presentOverlay
        self.session = session ?? ScreenshotsEngine.makeSession(store: store, naming: { ScStr.naming })
    }

    func begin(_ hotkey: ScreenshotsHotkey) {
        guard !busy else { return }
        busy = true
        pressTask = Task {
            switch hotkey {
            case .area: await self.area()
            case .fullScreen: await self.fullScreen()
            }
        }
    }

    /// The overlay and the work in flight go with the module. The press is
    /// cancelled and every step after the freeze asks whether it still is: the
    /// task that was waiting on the freeze resumes regardless, and what it
    /// resumes into is a file, the clipboard or panels on every screen.
    func cancel() {
        pressTask?.cancel()
        pressTask = nil
        overlay?.close()
        overlay = nil
        toast.dismiss()
        busy = false
    }

    // MARK: - The full-screen shortcut

    private func fullScreen() async {
        let delivery = await session.captureScreens()
        // The session itself stops before it writes; this keeps the toast back.
        if !Task.isCancelled { present(delivery) }
        busy = false
    }

    // MARK: - The area shortcut

    private func area() async {
        let began = await session.begin()
        // The module went off during the freeze: no overlay for a module that is off.
        guard !Task.isCancelled else { return }
        switch began {
        case .refused(let reason):
            toast.showRefusal(reason)
            busy = false
        case .ready(let freeze):
            let overlay = CaptureOverlay(freeze: freeze) { [weak self] result in
                self?.overlayFinished(result, freeze: freeze)
            }
            self.overlay = overlay
            // Nothing to show when a display in the freeze has no screen any
            // more: the capture ends rather than covering half the desk.
            if !presentOverlay(overlay) {
                self.overlay = nil
                busy = false
            }
        }
    }

    private func overlayFinished(_ result: OverlayResult, freeze: Freeze) {
        overlay?.close()
        overlay = nil
        Task {
            switch result {
            case .cancelled:
                break
            case .area(let display, let local):
                if let image = session.crop(freeze, display: display, local: local) {
                    await handOff(CapturedShot(image: image, kind: .area))
                }
            case .wholeDisplay(let display):
                if let frame = freeze.frames.first(where: { $0.id == display }),
                   let image = session.crop(freeze, display: display,
                                            local: Selection.wholeDisplay(CGRect(origin: .zero, size: frame.frame.size))) {
                    await handOff(CapturedShot(image: image, kind: .display))
                }
            case .window(let id):
                switch await session.window(id, in: freeze) {
                case .image(let image): await handOff(CapturedShot(image: image, kind: .window))
                case .refused(let reason): toast.showRefusal(reason)
                }
            }
            busy = false
        }
    }

    // MARK: - The seam

    /// **Part 2 replaces the body of this and nothing else.** Every area, window
    /// and whole-display pick from the overlay arrives here — mouse up, Return,
    /// a click on a window — and the full-screen shortcut does not, because it never had an editor to
    /// open. Until the inline editor exists the picture is copied and saved,
    /// and the thumbnail says so.
    func handOff(_ shot: CapturedShot) async {
        let settings = ScreenshotsSettings.read(store)
        if settings.thumbnail { toast.showWorking(shot.image) }
        let delivery = await session.deliver(shot.image, saves: true, copies: true)
        present(delivery)
    }

    // MARK: - What the person is told

    private func present(_ delivery: Delivery) {
        if let refusal = delivery.refusals.first {
            toast.showRefusal(refusal)
            return
        }
        guard ScreenshotsSettings.read(store).thumbnail, let image = delivery.image else { return }
        let caption: String
        switch (delivery.files.isEmpty, delivery.copied) {
        case (false, true): caption = ScStr.savedAndCopied
        case (false, false): caption = ScStr.saved
        default: caption = ScStr.copied
        }
        toast.showDone(image, caption: caption, file: delivery.files.first)
    }
}
