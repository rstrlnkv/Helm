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
        controller?.teardown()
        let created = CaptureController(owner: vm, store: store)
        controller = created
        ModuleUICache.dropWhenDisabled(ScreenshotsDescriptor.id.rawValue) {
            controller?.teardown()
            controller = nil
        }
        return created
    }
}

@MainActor final class CaptureController {
    let owner: ModuleViewModel
    private let store: NamespacedStore
    private let session: CaptureSession
    /// Not private: a test drives the thumbnail's lifetime and the Share sheet through it.
    let toast: ShotToast
    /// The capsule's Copy in flight, held so `cancel` can reach it.
    private var copyTask: Task<Void, Never>?
    /// Not private: a test reads what is pinned through it. The pins outlive a capture and
    /// the module's switch ends them (`teardown`); `cancel` leaves them be.
    let pins: PinBoard
    /// Not private: a test reads what the bar says through it, and puts no window on a screen.
    let bar: CapturePanel
    private var overlay: CaptureOverlay?
    /// One flag for the bar, its countdown and the overlay: they are one
    /// capture in three stages, and a second press at any of them is dropped.
    private var busy = false
    /// The press in flight, held so `cancel` can reach it: the freeze is the one
    /// long wait and the module's switch can be turned inside it.
    private var pressTask: Task<Void, Never>?
    /// The delivery after an exit, held for the same reason: the module's switch
    /// can be turned between the exit and the file.
    private var deliveryTask: Task<Void, Never>?
    /// Puts the overlay on the screens. A seam for a test, which must see whether
    /// the area shortcut reached it without putting panels on the screen of whoever runs the suite.
    private let presentOverlay: (CaptureOverlay) -> Bool
    /// Puts the bar on the screen; a seam for the same reason.
    private let presentBar: (CapturePanel) -> Void
    /// One second of the countdown. A seam: a test passes a wait it controls,
    /// and the running app sleeps.
    private let tick: (Duration) async throws -> Void

    /// `session`, `presentOverlay`, `presentBar`, `pins`, `toast` and `tick` are seams for a test,
    /// which builds a session over fake ports, counts the presentations and holds
    /// the countdown still; the running app passes nothing and gets the real ones.
    init(owner: ModuleViewModel, store: NamespacedStore, session: CaptureSession? = nil,
         presentOverlay: @escaping (CaptureOverlay) -> Bool = { $0.present() },
         presentBar: @escaping (CapturePanel) -> Void = { $0.show() },
         pins: PinBoard = PinBoard(), toast: ShotToast = ShotToast(),
         tick: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.owner = owner
        self.store = store
        self.presentOverlay = presentOverlay
        self.presentBar = presentBar
        self.tick = tick
        self.pins = pins
        self.toast = toast
        self.bar = CapturePanel(store: store)
        self.session = session ?? ScreenshotsEngine.makeSession(store: store, naming: { ScStr.naming })
        bar.model.capture = { [weak self] mode in self?.capture(from: mode) }
        bar.model.cancel = { [weak self] in self?.cancel() }
        toast.onEdit = { [weak self] in self?.editFromThumbnail() }
        toast.onCopy = { [weak self] in self?.copyFromThumbnail() }
        toast.onPin = { [weak self] image, frame in self?.pins.open(image, frame: frame) }
    }

    /// Whether a press is in progress at any stage. A test waits on it.
    var isBusy: Bool { busy }

    func begin(_ hotkey: ScreenshotsHotkey) {
        guard !busy else { return }
        busy = true
        switch hotkey {
        case .panel:
            // A press that finished leaves its task behind; the bar's own Capture
            // starts a new one and asks that none is in flight.
            pressTask = nil
            presentBar(bar)
        case .area:
            pressTask = Task { await self.area() }
        case .fullScreen:
            pressTask = Task { await self.fullScreen() }
        }
    }

    // MARK: - The panel

    /// Capture pressed on the bar: the countdown if there is one, then the mode
    /// the bar was on. A second press while one is running is dropped.
    func capture(from mode: PanelMode) {
        guard busy, pressTask == nil else { return }
        pressTask = Task {
            let seconds = ScreenshotsSettings.read(store).timer.seconds
            // The bar is where the countdown shows, so it stays up through it and
            // goes before the freeze: Esc, the close control and a module
            // switched off all end the press here, with no freeze taken.
            if seconds > 0 {
                do { try await countdown(seconds) } catch { return }
            }
            guard !Task.isCancelled else { return }
            bar.close()
            switch mode {
            case .screen: await fullScreen()
            case .window: await area(mode: .window)
            case .area: await area(mode: .area, remembered: true)
            }
        }
    }

    /// Counts down on the bar, and **asks after every wait whether it was
    /// cancelled**: a wait that ends normally is not evidence that nobody
    /// pressed Esc during it.
    private func countdown(_ seconds: Int) async throws {
        for remaining in stride(from: seconds, to: 0, by: -1) {
            bar.model.countdown = remaining
            try await tick(.seconds(1))
            try Task.checkCancellation()
        }
        bar.model.countdown = nil
    }

    /// The overlay and the work in flight go with the module. The press is
    /// cancelled and every step after the freeze asks whether it still is: the
    /// task that was waiting on the freeze resumes regardless, and what it
    /// resumes into is a file, the clipboard or panels on every screen.
    func cancel() {
        pressTask?.cancel()
        pressTask = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        copyTask?.cancel()
        copyTask = nil
        bar.close()
        overlay?.close()
        overlay = nil
        toast.dismiss()
        busy = false
    }

    /// The module is going: everything `cancel` ends, and the pins too. A pin is a window the
    /// person asked to keep, so only the module's own end closes it, never an Esc on the bar.
    func teardown() {
        cancel()
        pins.closeAll()
    }

    // MARK: - The full-screen shortcut

    private func fullScreen() async {
        let delivery = await session.captureScreens()
        // The session itself stops before it writes; this keeps the toast back.
        if !Task.isCancelled { present(delivery) }
        busy = false
    }

    // MARK: - The area shortcut

    private func area(mode: CaptureOverlay.Mode = .area, remembered: Bool = false) async {
        let began = await session.begin()
        // The module went off during the freeze: no overlay for a module that is off.
        guard !Task.isCancelled else { return }
        switch began {
        case .refused(let reason):
            toast.showRefusal(reason)
            busy = false
        case .ready(let freeze):
            // Read after the freeze, against the displays it found: only the
            // panel's Area mode opens on the last selection, and only while the
            // option is on.
            let preselection = remembered && ScreenshotsSettings.read(store).rememberSelection
                ? RememberedSelection.read(store)?.landing(in: freeze.frames) : nil
            let overlay = CaptureOverlay(freeze: freeze, mode: mode, preselection: preselection, store: store,
                                    pinRoom: { [weak self] in self?.pins.hasRoom ?? false }) { [weak self] result in
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

    // MARK: - «Edit» on the thumbnail

    /// What an editor opened from the thumbnail was opened on: the picture over its freeze, and the shot whose file
    /// a save replaces. `original` is nil for a shot that was only copied, which has nothing to replace.
    struct ShotEdit {
        let shown: PictureOnScreen
        let original: WrittenShot?
    }

    /// The thumbnail's click and the capsule's Edit: the palette round the finished picture. One capture at a time,
    /// so a press while another is open or in flight is dropped, as a shortcut's is.
    func editFromThumbnail() {
        guard !busy, let source = toast.model.editSource else { return }
        busy = true
        pressTask = Task { await self.edit(source.shot, held: source.held) }
    }

    private func edit(_ shot: WrittenShot?, held: CGImage?) async {
        let opened = await session.openEdit(of: shot, held: held, on: Self.displayUnderPointer())
        // The module went off while the file was read or the screen frozen: no overlay for a module that is off.
        guard !Task.isCancelled else { return }
        switch opened {
        case .refused(let reason):
            toast.showRefusal(reason)
            busy = false
        case .ready(let shown):
            let editing = ShotEdit(shown: shown, original: shot)
            let overlay = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: store,
                                         pinRoom: { [weak self] in self?.pins.hasRoom ?? false }) { [weak self] result in
                self?.overlayFinished(result, freeze: shown.freeze, editing: editing)
            }
            self.overlay = overlay
            if presentOverlay(overlay) {
                // The picture is in the editor now, and the thumbnail would lie under the overlay.
                toast.dismiss()
            } else {
                self.overlay = nil
                busy = false
            }
        }
    }

    private static func displayUnderPointer() -> DisplayID? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32).map { DisplayID($0) }
    }

    private func overlayFinished(_ result: OverlayResult, freeze: Freeze, editing: ShotEdit? = nil) {
        overlay?.close()
        overlay = nil
        deliveryTask = Task {
            // Asked at the start and after every wait: a delivery cancelled by the
            // module's switch must reach neither the disk nor the clipboard.
            guard !Task.isCancelled else { return }
            switch result {
            case .cancelled:
                break
            case .edited(let display, let local, let layers, let exit):
                let image: CGImage?
                if let editing {
                    // The picture's own pixels, and an area on the display it was shown on: any other display's
                    // points are not the picture's.
                    image = display == editing.shown.display
                        ? await session.annotated(editing.shown, local: local, layers: layers) : nil
                } else {
                    remember(display: display, local: local, in: freeze)
                    image = await session.annotated(freeze, display: display, local: local, layers: layers,
                                                    detached: exit == .pin)
                }
                if let image, !Task.isCancelled {
                    // No `default:`: a new exit must say here what it does, or it would be a save.
                    switch exit {
                    case .confirm, .copy, .save, .share:
                        await handOff(CapturedShot(image: image, kind: .area),
                                      saves: exit != .copy, copies: exit != .save,
                                      fileEvenFromClipboard: exit == .save, thenShare: exit == .share, editing: editing)
                    case .pin:
                        pin(image, display: display, local: local, in: freeze)
                    }
                }
            case .wholeDisplay(let display):
                if let frame = freeze.frames.first(where: { $0.id == display }),
                   let image = session.crop(freeze, display: display,
                                            local: Selection.wholeDisplay(CGRect(origin: .zero, size: frame.frame.size))) {
                    await handOff(CapturedShot(image: image, kind: .display))
                }
            case .window(let id):
                let picked = await session.window(id, in: freeze)
                guard !Task.isCancelled else { return }
                switch picked {
                case .image(let image): await handOff(CapturedShot(image: image, kind: .window))
                case .refused(let reason): toast.showRefusal(reason)
                }
            }
            // A cancelled delivery leaves `busy` to `cancel`, which has already cleared it:
            // a press begun since is not this one's to release.
            if !Task.isCancelled { busy = false }
        }
    }

    /// The picture as a window on the selection's own place: no file, no clipboard, no shutter, no toast.
    private func pin(_ image: CGImage, display: DisplayID, local: CGRect, in freeze: Freeze) {
        guard let frame = freeze.frames.first(where: { $0.id == display }),
              let primary = NSScreen.screens.first else { return }
        pins.open(image, frame: PinGeometry.opening(local: local, scale: frame.scale, imageWidth: frame.image.width,
                                                    imageHeight: frame.image.height, display: frame.frame,
                                                    primaryHeight: primary.frame.height))
    }

    /// Written for every confirmed area while the option is on, whichever door it
    /// came through; read only by the bar's Area mode.
    private func remember(display: DisplayID, local: CGRect, in freeze: Freeze) {
        guard ScreenshotsSettings.read(store).rememberSelection,
              let uuid = freeze.frames.first(where: { $0.id == display })?.uuid,
              let record = RememberedSelection(display: uuid, rect: local) else { return }
        record.write(to: store)
    }

    // MARK: - The seam

    /// Where a finished picture is delivered: copied and/or saved, the shutter, the
    /// thumbnail. A window or a whole display arrives here straight from the overlay
    /// and does both; an area is **not** picked here any more — its seam is
    /// `OverlayResult.edited`, which composes the editor's layers over the crop and
    /// then calls this with the two things its exit asked for (Return asks for both
    /// and so behaves as this always did, ⌘C only copies, ⌘S only saves). The
    /// full-screen shortcut never came through here: it has no editor.
    ///
    /// `editing` marks the exit of an editor opened from the thumbnail: **a save then replaces that shot's file**,
    /// and the order of that replacement is the session's (`CaptureSession.deliver(…replacing:)`), not this
    /// type's. No shutter, since no picture was taken, and the thumbnail comes back whatever the setting says,
    /// since it is where the edit was asked for. A shot that had no file replaces nothing: it is saved as a new one,
    /// or only copied under the clipboard target, as any shot is.
    func handOff(_ shot: CapturedShot, saves: Bool = true, copies: Bool = true,
                 fileEvenFromClipboard: Bool = false, thenShare: Bool = false, editing: ShotEdit? = nil) async {
        guard !Task.isCancelled else { return }
        let settings = ScreenshotsSettings.read(store)
        if editing == nil { session.shutter() }
        // A person who asked for the Share sheet needs the thumbnail it opens at, whatever the setting says.
        let shows = settings.thumbnail || thenShare || editing != nil
        if shows { toast.showWorking(shot.image) }
        let delivery = await session.deliver(shot.image, saves: saves, copies: copies,
                                             fileEvenFromClipboard: fileEvenFromClipboard,
                                             replacing: editing?.original)
        if !Task.isCancelled { present(delivery, showing: shows, sharing: thenShare) }
    }

    /// The capsule's Copy: the shot's full picture to the clipboard, from memory or read back from its file.
    private func copyFromThumbnail() {
        guard let image = toast.fullPicture() else { toast.showRefusal(.encoding); return }
        copyTask?.cancel()
        copyTask = Task {
            let delivery = await session.deliver(image, saves: false, copies: true)
            if !Task.isCancelled, let refusal = delivery.refusals.first { toast.showRefusal(refusal) }
        }
    }

    // MARK: - What the person is told

    /// `showing` is nil for a delivery that asks the setting itself, which is the full-screen shortcut's.
    private func present(_ delivery: Delivery, showing: Bool? = nil, sharing: Bool = false) {
        if let refusal = delivery.refusals.first {
            toast.showRefusal(refusal)
            return
        }
        guard showing ?? ScreenshotsSettings.read(store).thumbnail, let image = delivery.image else { return }
        let caption: String
        switch (delivery.files.isEmpty, delivery.copied) {
        case (false, _) where delivery.replaced: caption = ScStr.replaced
        case (false, true): caption = ScStr.savedAndCopied
        case (false, false): caption = ScStr.saved
        default: caption = ScStr.copied
        }
        let shot = delivery.written.first
        toast.showDone(image, caption: caption, file: shot?.url, share: sharing, reading: shot?.reading)
    }
}
