import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

@MainActor final class ShotToast {
    /// Not private: a test wires the close control through it without a panel.
    let model = ShotToastModel()
    var panel: ShotPanel?
    var host: NSView?
    private var dismissal: Task<Void, Never>?
    /// One step of the lifetime's clock. A seam: a test passes a wait it controls, and the running app sleeps.
    private let tick: (Duration) async throws -> Void
    /// Whether to put a panel on the screen; a test builds none.
    private let windowed: Bool
    /// Whether the pointer is over the window's shots, in screen points: inside the anchor view's rect, or anywhere
    /// in the row while it is unfolded. Asked by `advance`: under a hold that only the pointer keeps, to end it when
    /// the pointer is elsewhere; when the time is up, to hold when it is there; and of an unfolded row at every
    /// step, to fold it once the pointer has been away for `ShotShelf.foldDelay`.
    private var pointerIsOver: () -> Bool = { false }
    /// What the capsule's Edit, Copy, Copy All and Pin ask of whoever owns the session and the board.
    var onEdit: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCopyAll: () -> Void = {}
    var onPin: (CGImage, CGRect) -> Void = { _, _ in }
    /// Makes the panel key when the row unfolds, and gives the keys back when it folds.
    ///
    /// Giving back is ordering the panel out and in again: AppKit has no call that only resigns key. That a key
    /// window that leaves the screen hands the keys to the next that can take them, and that the two orders in one
    /// turn of the run loop are not seen as a blink, are not measured.
    private var takeKey: () -> Void = {}
    private var yieldKey: () -> Void = {}

    /// What keeps the lifetime from running: the pointer over the picture or the pile, the Share sheet open, the
    /// editor open on a shot taken from a group. An unfolded row is not a hold: while it is unfolded the lifetime
    /// is not counted at all.
    enum Hold: Hashable { case pointer, sheet, editor }
    var holds: Set<Hold> = []
    /// Seconds of life left, counted only while nothing holds it and the row is folded.
    private(set) var remaining: Double = 0
    /// Seconds the pointer has been away from the unfolded row.
    private(set) var away: Double = 0
    /// Seconds since the row was last scrolled, nil once the scroll has come to rest and its bar is gone.
    private var sinceScroll: Double?
    /// Seconds until the panel takes the folded pile's size: the fold is drawn inside the row's.
    private var shrinkIn: Double?
    /// The shot whose write is not done: its result fills it, and a refusal takes it away.
    private var pending: ShotToastModel.Shot.ID?
    var wantsShare = false
    var picker: NSSharingServicePicker?
    var pickerDelegate: PickerDelegate?

    private static let step = 0.1
    /// Seconds a group lives once its last result is in, and once a refusal over it has gone.
    private static let life: Double = 5
    /// Seconds the picture taken stays while its result is awaited.
    static let workingLife: Double = 6
    /// Seconds a refusal stays, over a pile or alone.
    static let refusalLife: Double = 9

    init(tick: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, windowed: Bool = true) {
        self.tick = tick
        self.windowed = windowed
        let model = self.model
        pointerIsOver = { [weak self, weak model] in
            let mouse = NSEvent.mouseLocation
            if model?.unfolded == true, let panel = self?.panel,
               panel.frame.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom).contains(mouse) { return true }
            guard let anchor = model?.anchor, let window = anchor.window else { return false }
            return window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(mouse)
        }
        takeKey = { [weak self] in self?.panel?.makeKey() }
        yieldKey = { [weak self] in
            guard let panel = self?.panel, panel.isKeyWindow else { return }
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        model.dismiss = { [weak self] in self?.close() }
        model.hoverChanged = { [weak self] over in self?.setHover(over) }
        model.edit = { [weak self] in self?.onEdit() }
        model.copy = { [weak self] in self?.onCopy() }
        model.copyAll = { [weak self] in self?.onCopyAll() }
        model.pin = { [weak self] in self?.pin() }
        model.unfold = { [weak self] in self?.unfold() }
        model.showOldest = { [weak self] in self?.showOldest() }
        model.scroll = { [weak self] delta, precise in self?.scroll(by: delta, precise: precise) }
        model.anchorAttached = { [weak self] in self?.attemptShare() }
    }

    /// The picture at once, before the write has finished: encoding a
    /// full-resolution frame is not instant, and the person is waiting to see that
    /// something happened. The caption arrives with the result. It is a new shot on the list, the newest; one whose
    /// result never came is not left beside it.
    func showWorking(_ image: CGImage) {
        show(lasting: Self.workingLife) {
            let reduced = Self.thumbnail(of: image)
            model.say(nil)
            if let pending, model.update(pending, { $0.image = reduced }) { return }
            pending = model.add(reduced, caption: nil, file: nil)
        }
    }

    /// The result of the shot `showWorking` showed, or a new shot when nothing was shown before it. `share` also
    /// opens the system's Share sheet at the thumbnail once it is up. `reading` is what the writer read of `file`
    /// as it wrote it, which is what makes the shot one «Edit» can open.
    func showDone(_ image: CGImage, caption: String, file: URL?, share: Bool = false, reading: ShotReading? = nil) {
        show(lasting: Self.life) {
            let reduced = Self.thumbnail(of: image)
            model.say(nil)
            let full = file == nil ? image : nil, reading = file == nil ? nil : reading
            let filled = pending.map { id in
                model.update(id) {
                    $0.image = reduced
                    $0.caption = caption
                    $0.file = file
                    $0.full = full
                    $0.reading = reading
                }
            } ?? false
            if !filled { model.add(reduced, caption: caption, file: file, full: full, reading: reading) }
            pending = nil
        }
        if share { requestShare() }
    }

    /// The plaque, in the shots' place for `refusalLife`. **Only the refusal of the still-writing shot's own write
    /// (`ofItsWrite`) takes that shot away**; a refusal of a Copy, an Edit or a capture the shot has no part in leaves
    /// it, and its result still lands on it. The other shots are kept under the plaque, folded, and are back when it
    /// goes (`advance`, `close`).
    func showRefusal(_ reason: CaptureRefusal, ofItsWrite: Bool = false) {
        show(lasting: Self.refusalLife) {
            if ofItsWrite {
                if let pending { model.remove(pending) }
                pending = nil
            }
            fold()
            model.say(Self.refusalContent(reason))
        }
    }

    /// What a refusal says, and whether it offers «Open Settings» — **only for
    /// the grant**. A button that cannot do what it says is worse than none: a
    /// full disk is not mended in the Privacy pane.
    private static func refusalContent(_ reason: CaptureRefusal) -> ShotToastModel.Content {
        let permission = reason == .noPermission
        let title: String
        switch reason {
        case .noPermission: title = ScStr.noPermissionTitle
        // A shot that was taken and could not be opened or replaced: «not taken» would be untrue of it.
        case .notEditable, .notReplaced, .fileGone, .filesGone: title = ScStr.thumbnailLabel
        case .captureFailed, .displayGone, .windowGone, .write, .pasteboard, .encoding: title = ScStr.failedTitle
        }
        return .refusal(title: title, body: ScStr.refusal(reason), offersSettings: permission)
    }

    /// The whole window goes, with every shot on the list and everything they held.
    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        // A sheet left open under a window that is gone would sit beside the one the next Share opens.
        picker?.close()
        resetHolds()
        model.shown = false
        clear()
    }

    /// The ✕. On a refusal that covers shots it takes the refusal; on a shot of the row, that shot; anywhere else
    /// the whole window: the single shot, the folded pile, a refusal with nothing under it.
    func close() {
        if model.refusal != nil, !model.shots.isEmpty {
            dropRefusal()
        } else if model.unfolded, let shot = model.current {
            remove(shot.id)
        } else {
            dismiss()
        }
    }

    /// One shot leaves the list. The row closes up; with one shot left it is the single shot again, and with none
    /// the window goes.
    func remove(_ id: ShotToastModel.Shot.ID) {
        withAnimation(HelmMotion.interface) { model.remove(id) }
        if pending == id { pending = nil }
        switch model.shots.count {
        case 0: dismiss()
        case 1 where model.unfolded: fold()
        default:
            model.offset = ShotShelf.snapped(model.offset, count: model.shots.count)
            refit()
        }
    }

    private func clear() {
        panel?.orderOut(nil)
        panel = nil
        host = nil
        model.content = nil
        pending = nil
        sinceScroll = nil
        shrinkIn = nil
        away = 0
    }

    // MARK: - The pile and the row

    /// A click on the pile: the row, and the keys with it. The lifetime stops being counted until it folds.
    func unfold() {
        guard model.isPile else { return }
        holds.remove(.pointer)
        model.hovering = false
        away = 0
        shrinkIn = nil
        model.offset = 0
        withAnimation(HelmMotion.interface) { model.unfolded = true }
        refit()
        takeKey()
    }

    /// Esc, the pointer away for `ShotShelf.foldDelay`, a refusal, the editor, one shot left: the row is the pile
    /// again, the keys go back, and the lifetime goes on from what was left of it.
    func fold() {
        guard model.unfolded else { return }
        withAnimation(HelmMotion.interface) {
            model.unfolded = false
            model.offset = 0
        }
        model.focus = nil
        model.barShown = false
        sinceScroll = nil
        away = 0
        shrinkIn = HelmMotion.interfaceDuration
        yieldKey()
    }

    /// A scroll over the row, in points toward the oldest shot, or in a wheel's notches (`precise` false).
    func scroll(by delta: CGFloat, precise: Bool = true) {
        guard model.unfolded else { return }
        let count = model.shots.count
        model.offset = ShotShelf.scrolled(model.offset, by: delta, precise: precise, count: count)
        model.barShown = count > ShotShelf.visible
        sinceScroll = 0
    }

    /// A click on «N more»: the row at its oldest shot.
    func showOldest() {
        guard model.unfolded else { return }
        let count = model.shots.count
        withAnimation(HelmMotion.interface) { model.offset = ShotShelf.farthest(count: count) }
        model.barShown = count > ShotShelf.visible
        sinceScroll = ShotShelf.snapDelay
    }

    /// What the clock does for the row and the panel besides the lifetime. **No end of a scroll is waited for:** a
    /// wheel sends none and a gesture's may not come, so the row comes to rest once no scroll has arrived for
    /// `ShotShelf.snapDelay`, and its bar goes after `ShotShelf.barLinger`.
    private func settle(after passed: Double) {
        if let idle = sinceScroll {
            let now = idle + passed
            if !ShotShelf.isOver(left: ShotShelf.snapDelay - idle), ShotShelf.isOver(left: ShotShelf.snapDelay - now) {
                let rest = ShotShelf.snapped(model.offset, count: model.shots.count)
                withAnimation(HelmMotion.interface) { model.offset = rest }
            }
            if ShotShelf.isOver(left: ShotShelf.barLinger - now) {
                model.barShown = false
                sinceScroll = nil
            } else {
                sinceScroll = now
            }
        }
        if let left = shrinkIn {
            shrinkIn = ShotShelf.isOver(left: left - passed) ? nil : left - passed
            if shrinkIn == nil { refit() }
        }
    }

    // MARK: - How long it lives

    /// The pointer came onto the picture or left it. The lifetime that was running goes on from what was left.
    func setHover(_ over: Bool) {
        model.hovering = over
        if over { holds.insert(.pointer) } else { holds.remove(.pointer) }
    }

    /// The editor opened on this shot: the picture is in the editor now, and its thumbnail leaves the window, alone
    /// or out of its group. What is left of a group lies under the overlay, folded, and spends none of its life
    /// there: the hold ends with the editor (`editorClosed`), and with the window (`dismiss`).
    func takeForEditing(_ id: ShotToastModel.Shot.ID) {
        fold()
        remove(id)
        if !model.shots.isEmpty { holds.insert(.editor) }
    }

    func editorClosed() {
        holds.remove(.editor)
    }

    /// One step of the clock: true when the window's time is up. **The pointer's events are not trusted either way.** A
    /// pointer that is over the picture when the time runs out holds it, though no enter was sent; and a hold that only
    /// the pointer keeps ends at the first step that finds the pointer elsewhere, though no exit was sent. Whether
    /// AppKit sends an exit when the panel moves from under a still pointer or the view is removed is not measured;
    /// `pointerIsOver` is asked instead of relying on it.
    ///
    /// **An unfolded row spends no life.** Its steps count how long the pointer has been away instead, asked the
    /// same way, and fold it at `ShotShelf.foldDelay`. A refusal whose time is up over shots that are still on the
    /// list gives the window back to them, with a group's life.
    func advance(by seconds: Double = ShotToast.step) -> Bool {
        // A step is time that passed: one that is not a number passed none, a negative one gave nothing back, and an
        // endless one ends the life.
        let passed = seconds.clamped(to: 0...Double.infinity, whenNotANumber: 0)
        settle(after: passed)
        if model.unfolded {
            if pointerIsOver() {
                away = 0
            } else {
                away += passed
                if ShotShelf.isOver(left: ShotShelf.foldDelay - away) { fold() }
            }
            return false
        }
        if holds == [.pointer], !pointerIsOver() { setHover(false) }
        guard holds.isEmpty else { return false }
        remaining -= passed
        guard ShotShelf.isOver(left: remaining) else { return false }
        if pointerIsOver() { setHover(true); return false }
        if model.refusal != nil, !model.shots.isEmpty { dropRefusal(); return false }
        return true
    }

    /// The plaque goes and the shots it covered are the window again.
    private func dropRefusal() {
        model.say(nil)
        resetHolds(keepingSheet: true)
        remaining = Self.life
        if let panel { place(panel) }
    }

    /// A sheet that is open stays open across a new shot or a refusal: it is still on the screen at this very view,
    /// and only `dismiss` takes it, and closes it. The editor's hold is kept with it, and ends with the editor.
    private func resetHolds(keepingSheet: Bool = false) {
        holds = keepingSheet ? holds.intersection([.sheet, .editor]) : []
        model.hovering = false
        wantsShare = false
        if !holds.contains(.sheet) {
            picker = nil
            pickerDelegate = nil
        }
    }

    // MARK: -

    /// Puts what `change` made of the model on the screen, for `seconds`. The clock starts over with every new shot.
    private func show(lasting seconds: Double, _ change: () -> Void) {
        dismissal?.cancel()
        // The pointer stays held across a picture that follows a picture, the write's result over its working
        // thumbnail above all: the view is the same one. Whether AppKit sends a new enter for a pointer that never
        // left is not measured, and a hold dropped here would not come back.
        let wasShots = model.showsShots
        withAnimation(HelmMotion.interface) { change() }
        let stillOver = model.hovering && wasShots && model.showsShots
        resetHolds(keepingSheet: true)
        if stillOver { setHover(true) }
        remaining = seconds
        // A shot that arrives while the row is open stands in the corner, and the row is shown from there.
        if model.unfolded { model.offset = 0 }
        if windowed {
            let panel = self.panel ?? makePanel()
            self.panel = panel
            place(panel)
            panel.orderFrontRegardless()
        }
        model.shown = true
        dismissal = Task { [weak self] in
            while true {
                do { try await self?.tick(.milliseconds(Int(Self.step * 1000))) } catch { return }
                guard !Task.isCancelled, let self else { return }
                if self.advance() { break }
            }
            self?.model.shown = false
            // After the fade, not at the same moment.
            try? await self?.tick(.milliseconds(Int(HelmMotion.interfaceDuration * 1000)))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }
}
