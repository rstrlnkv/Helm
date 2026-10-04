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
    /// The overlay that has delivered its result and is in its flash: the panels are up and deaf for up to a
    /// flash's length, and the module's end closes them at once (`cancel`). Kept after the flash until the next
    /// result or `cancel`; by then the overlay has closed itself and holds no panels.
    private var flashing: CaptureOverlay?
    /// One flag for the bar, its countdown and the overlay: they are one
    /// capture in three stages, and a second press at any of them is dropped.
    private var busy = false
    /// The press in flight, held so `cancel` can reach it: the screen's countdown and its freeze, the one long wait,
    /// and the module's switch can be turned inside either.
    private var pressTask: Task<Void, Never>?
    /// The freeze the panel's overlay is waiting on, held so the module's end can cancel it. A mode that puts the overlay
    /// away leaves it be: what the panel shows when the freeze returns says whether an overlay opens (`area`).
    private var selectionTask: Task<Void, Never>?
    /// The freeze for the panel's overlay is being taken: a second mode press is dropped, and the overlay that opens is
    /// the one the panel's mode asks for when the freeze returns.
    private var freezing = false
    /// The overlay now open is the panel's, where the person picks and presses Capture, and not a shortcut's.
    private var picking = false
    /// The delivery after an exit, held for the same reason: the module's switch can be turned between the exit and the
    /// file. With a timer, a window or an area picked on the panel is held here from the pick: the countdown, then the shot.
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
        bar.model.modeChosen = { [weak self] in self?.pick(in: $0) }
        toast.onEdit = { [weak self] in self?.editFromThumbnail() }
        toast.onCopy = { [weak self] in self?.copyFromThumbnail() }
        toast.onCopyAll = { [weak self] in self?.copyAllFromPile() }
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
            selectionTask = nil
            presentBar(bar)
        case .area:
            pressTask = Task { await self.area() }
        case .fullScreen:
            pressTask = Task { await self.fullScreen() }
        }
    }

    // MARK: - The panel

    /// Capture pressed on the bar. **The whole screen**: the countdown if there is one, then the shot. **A window or an
    /// area**: the target the panel's overlay holds, taken as a click or Return on that overlay would take it
    /// (`overlayFinished` does the countdown, which for these comes after the pick); with no overlay open yet the press
    /// opens one and has nothing to take. A second press while one is running is dropped.
    func capture(from mode: PanelMode) {
        guard busy, pressTask == nil, !bar.model.counting else { return }
        guard mode == .screen else {
            if let overlay, picking { overlay.takeTarget() } else { pick(in: mode) }
            return
        }
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
            await fullScreen()
        }
    }

    /// A mode was pressed on the panel, the shown one too. **Window and Area** pick on a frozen screen at once: the
    /// freeze and the overlay open in selection-only mode with the panel above them, or — with that overlay already open —
    /// it picks in the new mode on the same freeze; while the freeze is still out the press is dropped and the overlay
    /// opens in the mode the panel shows when it returns. **Screen** has nothing to pick, so the overlay goes and Capture
    /// is the whole screen's. Not while a countdown or a shot is running.
    func pick(in mode: PanelMode) {
        guard busy, pressTask == nil, !bar.model.counting else { return }
        switch mode {
        case .screen:
            endPicking()
        case .window, .area:
            if let overlay, picking {
                overlay.select(mode == .window ? .window : .area)
                return
            }
            guard !freezing else { return }
            selectionTask = Task { await area(mode: mode == .window ? .window : .area, remembered: mode == .area, picking: true) }
        }
    }

    /// The panel's overlay is put away, the panel stays: no result is delivered. A freeze still out is not cancelled:
    /// when it returns, `area` opens nothing if the panel shows Screen and an overlay in the mode it shows otherwise.
    private func endPicking() {
        guard picking else { return }
        overlay?.close()
        overlay = nil
        picking = false
        bar.selecting = false
        bar.model.hasTarget = false
    }

    /// Counts down on the bar, and **asks after every wait whether it was
    /// cancelled**: a wait that ends normally is not evidence that nobody
    /// pressed Esc during it.
    private func countdown(_ seconds: Int) async throws {
        bar.model.countdownLength = seconds
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
        selectionTask?.cancel()
        selectionTask = nil
        freezing = false
        picking = false
        copyTask?.cancel()
        copyTask = nil
        bar.close()
        overlay?.close()
        overlay = nil
        flashing?.close()
        flashing = nil
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

    /// `picking` is the panel's: the overlay only picks (`CaptureOverlay.selectionOnly`), the panel stands above it and
    /// the mode is the panel's as it is when the freeze arrives, which the person may have changed meanwhile (Screen: no
    /// overlay).
    private func area(mode: CaptureOverlay.Mode = .area, remembered: Bool = false, picking panel: Bool = false) async {
        freezing = panel
        let modeAtPress = bar.model.mode
        let began = await session.begin()
        // A cancelled freeze returning is not the one `freezing` stands for now: `cancel` cleared the flag, and a panel
        // opened since may have a freeze of its own out.
        if !Task.isCancelled { freezing = false }
        // The module went off during the freeze: no overlay for a module that is off.
        guard !Task.isCancelled else { return }
        var mode = mode, remembered = remembered
        if panel, bar.model.mode != modeAtPress {
            switch bar.model.mode {
            case .screen: return
            case .window: mode = .window; remembered = false
            case .area: mode = .area; remembered = true
            }
        }
        switch began {
        case .refused(let reason):
            toast.showRefusal(reason)
            if panel { bar.close() }
            busy = false
        case .ready(let freeze):
            // Read after the freeze, against the displays it found: only the
            // panel's Area mode opens on the last selection, and only while the
            // option is on.
            let preselection = remembered && ScreenshotsSettings.read(store).rememberSelection
                ? RememberedSelection.read(store)?.landing(in: freeze.frames) : nil
            let overlay = CaptureOverlay(freeze: freeze, mode: mode, preselection: preselection, store: store,
                                    pinRoom: { [weak self] in self?.pins.hasRoom ?? false },
                                    textTools: EditorTextTools(read: { [session] in await session.readText(freeze, display: $0, local: $1) },
                                                               copy: { [session] in session.copyText($0) }),
                                    selectionOnly: panel) { [weak self] result in
                self?.overlayFinished(result, freeze: freeze, picked: panel)
            }
            self.overlay = overlay
            if panel {
                picking = true
                bar.selecting = true
                bar.model.hasTarget = overlay.hasTarget
                overlay.targetChanged = { [weak self] in self?.bar.model.hasTarget = $0 }
            }
            // Nothing to show when a display in the freeze has no screen any
            // more: the capture ends rather than covering half the desk.
            if !presentOverlay(overlay) {
                self.overlay = nil
                if panel { picking = false; bar.close() }
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
    /// so a press while another is open or in flight is dropped, as a shortcut's is. **Which shot is read here, at
    /// the press**: in a row it is the one the pointer is on, and by the time the screen is frozen the pointer may
    /// be on another.
    func editFromThumbnail() {
        guard !busy, let source = toast.model.editSource, let taken = toast.model.current?.id else { return }
        busy = true
        pressTask = Task { await self.edit(source.shot, held: source.held, taking: taken) }
    }

    private func edit(_ shot: WrittenShot?, held: CGImage?, taking taken: ShotToastModel.Shot.ID) async {
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
                toast.takeForEditing(taken)
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

    /// `picked`: the overlay was the panel's. With no timer the panel closes at the pick and the shot is delivered as the
    /// overlay's result says (an area is cut from its freeze, a window is asked for by its id and cut from the freeze
    /// only where the system gives none). With a timer the overlay goes at once and the panel stays with its ring until
    /// the last second, when it closes and the shot is taken from the screen as it is then (`timedShot`).
    private func overlayFinished(_ result: OverlayResult, freeze: Freeze, picked: Bool = false,
                                 editing: ShotEdit? = nil) {
        if picked {
            picking = false
            bar.selecting = false
            bar.model.hasTarget = false
            let seconds = ScreenshotsSettings.read(store).timer.seconds
            if seconds > 0, let wait = timedShot(of: result, freeze: freeze) {
                overlay?.close()
                overlay = nil
                deliveryTask = Task {
                    do { try await countdown(seconds) } catch { return }
                    guard !Task.isCancelled else { return }
                    bar.close()
                    await wait()
                    if !Task.isCancelled { busy = false }
                }
                return
            }
            bar.close()
        }
        // The panels stay for the flash of a shot that is taken (and close at once for the rest); the delivery
        // below does not wait for them, since its picture is the freeze's or the window's own.
        overlay?.close(after: result)
        flashing = overlay?.leaving == true ? overlay : nil
        overlay = nil
        if editing != nil { toast.editorClosed() }
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
            case .window(let id, let shadow):
                let picked = await session.window(id, in: freeze, shadow: shadow)
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

    /// What takes a picked target from the screen as it is **after** the countdown, or nil for a result that is no target.
    /// A window is asked for again by its id, as at a click; the freeze of the pick stays for the cut a window that has
    /// gone is saved from (a window closed during the wait is saved as it looked at the pick). An area is a rectangle of
    /// one display, so the screen is frozen again and the same rectangle is cut from the same display, found by its UUID
    /// as `RememberedSelection` does (by id where the system gave none). **A display that is gone, or no longer holds the
    /// whole rectangle, is a refusal (`displayGone`), never a smaller picture than was drawn.** The old freeze is not
    /// held through the wait.
    private func timedShot(of result: OverlayResult, freeze: Freeze) -> (() async -> Void)? {
        switch result {
        case .window(let id, let shadow):
            return { [self] in
                let picked = await session.window(id, in: freeze, shadow: shadow)
                guard !Task.isCancelled else { return }
                switch picked {
                case .image(let image): await handOff(CapturedShot(image: image, kind: .window))
                case .refused(let reason): toast.showRefusal(reason)
                }
            }
        case .edited(let display, let local, _, _):
            remember(display: display, local: local, in: freeze)
            let uuid = freeze.frames.first(where: { $0.id == display })?.uuid
            return { [self] in
                let began = await session.begin()
                guard !Task.isCancelled else { return }
                switch began {
                case .refused(let reason): toast.showRefusal(reason)
                case .ready(let fresh):
                    let frame = fresh.frames.first { uuid != nil ? $0.uuid == uuid : $0.id == display }
                    if let frame, CGRect(origin: .zero, size: frame.frame.size).contains(local),
                       let image = session.crop(fresh, display: frame.id, local: local) {
                        await handOff(CapturedShot(image: image, kind: .area))
                    } else {
                        toast.showRefusal(.displayGone)
                    }
                }
            }
        case .wholeDisplay, .cancelled:
            return nil
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

    /// The pile's Copy All: every finished shot of the group to the clipboard in one write.
    private func copyAllFromPile() {
        let shots = toast.sources()
        guard !shots.isEmpty else { return }
        copyTask?.cancel()
        copyTask = Task {
            let delivery = await session.copyAll(shots)
            if !Task.isCancelled, let refusal = delivery.refusals.first { toast.showRefusal(refusal) }
        }
    }

    // MARK: - What the person is told

    /// `showing` is nil for a delivery that asks the setting itself, which is the full-screen shortcut's.
    private func present(_ delivery: Delivery, showing: Bool? = nil, sharing: Bool = false) {
        if let refusal = delivery.refusals.first {
            toast.showRefusal(refusal, ofItsWrite: true)
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
