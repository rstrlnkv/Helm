import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the after-shot window says. One floating panel for both: the shots that follow captures, and the refusal
/// that follows one that did not happen.
///
/// **A list of shots, bounded by `ShotShelf.limit`.** One shot is the bare picture; more are a pile in the corner,
/// which a click unfolds into a row. The list is kept oldest first and changed through `add`, `update` and `remove`,
/// and emptied whole by the `content` setter; a shot gets onto it only by `add`, so the bound is `ShotShelf.add`'s. A refusal is drawn in the list's place and does
/// not end it: the shots are still what they were when the plaque goes.
@MainActor final class ShotToastModel: ObservableObject {
    enum Content {
        case picture(CGImage, caption: String?, file: URL?)
        case refusal(title: String, body: String, offersSettings: Bool)
    }

    /// One shot in the window.
    struct Shot: Identifiable {
        let id: Int
        /// The reduced copy that is drawn (`ShotToast.thumbnail`).
        var image: CGImage
        /// What a screen reader reads of it; nil while the shot is still being written.
        var caption: String?
        var file: URL?
        /// The full picture of a shot that was only copied: a thumbnail is a reduced copy, and a drag or a share of it
        /// would hand over `ShotThumbnail.longestEdge` pixels. A shot with a file holds none, and is read back from
        /// the file when asked. It leaves memory with the shot: pushed out, closed, or gone with the window.
        var full: CGImage?
        /// What the shot's file was when it was written: what «Edit» and the replacement that follows ask the file
        /// against. Nil for a shot with no file.
        var reading: ShotReading?
    }

    @Published private(set) var shots: [Shot] = []
    /// Only ever a `.refusal`.
    @Published private(set) var refusal: Content?
    @Published var shown = false
    /// The pointer is over the single picture, or over the pile: the capsule is up.
    @Published var hovering = false
    /// The pile is unfolded into a row.
    @Published var unfolded = false
    /// How far the row is scrolled toward its oldest shot (`ShotShelf.scrolled`).
    @Published var offset: CGFloat = 0
    /// The row's scroll bar is up.
    @Published var barShown = false
    /// The shot of the row the pointer is on, whose capsule is up.
    @Published var focus: Shot.ID?
    private var nextID = 0

    /// What the close control does: the toast's own `close`, set by its owner.
    var dismiss: () -> Void = {}
    /// What the capsule's Edit, Copy, Copy All and Pin do, what a click on the pile and on «N more» do, what a scroll
    /// over the row does, and what the pointer's coming and going tells the toast's clock: set by its owner.
    var edit: () -> Void = {}
    var copy: () -> Void = {}
    var copyAll: () -> Void = {}
    var pin: () -> Void = {}
    var unfold: () -> Void = {}
    var showOldest: () -> Void = {}
    var scroll: (CGFloat, Bool) -> Void = { _, _ in }
    var hoverChanged: (Bool) -> Void = { _ in }
    /// The newest shot's own view, which the Share sheet is shown relative to and the pointer is asked against; set
    /// by that view once it is on a window.
    weak var anchor: NSView? { didSet { if anchor != nil { anchorAttached() } } }
    var anchorAttached: () -> Void = {}
    /// The view of the row's shot the pointer came onto last.
    weak var focused: NSView?

    // MARK: - What the window is

    /// The window as one thing: the refusal while there is one, else the shot that an action is about. Setting it
    /// to a picture makes the window that one shot, the list that shot alone; a refusal is drawn over the list and
    /// leaves it; nil empties both.
    var content: Content? {
        get { refusal ?? current.map { .picture($0.image, caption: $0.caption, file: $0.file) } }
        set {
            unfolded = false
            focus = nil
            offset = 0
            barShown = false
            switch newValue {
            case .picture(let image, let caption, let file)?:
                refusal = nil
                shots = []
                add(image, caption: caption, file: file)
            case .refusal?:
                refusal = newValue
            case nil:
                refusal = nil
                shots = []
            }
        }
    }

    /// The shot an action is about: in the row the one the pointer is on, else the newest. None while a refusal
    /// covers the shots: nothing of them can be copied, edited, dragged or pinned from under it.
    var current: Shot? {
        guard refusal == nil else { return nil }
        return (unfolded ? shots.first { $0.id == focus } : nil) ?? shots.last
    }
    /// Shots are what is drawn, and not a refusal over them.
    var showsShots: Bool { refusal == nil && !shots.isEmpty }
    /// More than one shot, folded.
    var isPile: Bool { refusal == nil && shots.count > 1 && !unfolded }

    var full: CGImage? {
        get { current?.full }
        set { if let id = current?.id { update(id) { $0.full = newValue } } }
    }
    var reading: ShotReading? {
        get { current?.reading }
        set { if let id = current?.id { update(id) { $0.reading = newValue } } }
    }

    // MARK: - The list

    /// A new shot, the newest. The one past `ShotShelf.limit` pushes the oldest out, and with it everything that
    /// shot held.
    @discardableResult
    func add(_ image: CGImage, caption: String?, file: URL?, full: CGImage? = nil, reading: ShotReading? = nil) -> Shot.ID {
        nextID += 1
        let out = ShotShelf.add(Shot(id: nextID, image: image, caption: caption, file: file, full: full, reading: reading),
                                to: &shots)
        if out.contains(where: { $0.id == focus }) { focus = nil }
        return nextID
    }

    /// False when no such shot is on the list any more.
    @discardableResult
    func update(_ id: Shot.ID, _ change: (inout Shot) -> Void) -> Bool {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return false }
        change(&shots[index])
        return true
    }

    func remove(_ id: Shot.ID) {
        shots.removeAll { $0.id == id }
        if focus == id { focus = nil }
    }

    func say(_ refusal: Content?) {
        if case .picture? = refusal { return }
        self.refusal = refusal
    }

    // MARK: - What a shot offers

    /// What «Edit» opens on, nil while there is nothing it could: the written file with its reading, or the held
    /// picture of a shot that was only copied. A file with no reading is not offered, since nothing could say
    /// later that it is still that file.
    func editSource(of shot: Shot) -> (shot: WrittenShot?, held: CGImage?)? {
        guard shot.caption != nil else { return nil }
        if let file = shot.file { return shot.reading.map { (WrittenShot(url: file, reading: $0), nil) } }
        return shot.full.map { (nil, $0) }
    }

    var editSource: (shot: WrittenShot?, held: CGImage?)? {
        guard refusal == nil, let current else { return nil }
        return editSource(of: current)
    }

    /// What a drag of one shot carries, nil until the shot is written or copied.
    func drag(of shot: Shot) -> ShotDrag? {
        guard shot.caption != nil else { return nil }
        // A path that is gone is not carried: the drop would receive a name with nothing behind it.
        if let file = shot.file { return FileManager.default.fileExists(atPath: file.path) ? .file(file) : nil }
        return shot.full.map { .picture($0) }
    }

    var dragPayload: ShotDrag? {
        guard refusal == nil, let current else { return nil }
        return drag(of: current)
    }

    /// What a drag that began on this shot carries beside the shot itself: every other shot of a folded pile, which
    /// leaves as one; nothing from the row or from a single shot.
    func othersDragged(with id: Shot.ID) -> [ShotDrag] {
        isPile ? shots.filter { $0.id != id }.compactMap { drag(of: $0) } : []
    }

    // MARK: - From the views

    /// The pointer's coming and going over the single shot or the pile.
    func pointer(over: Bool) {
        hovering = over
        hoverChanged(over)
    }

    /// The pointer's coming and going over one shot's view. In the row it moves the capsule to that shot. Folded, only
    /// the newest shot's view counts: the slivers of the sheets under it would answer an exit after the top
    /// sheet's enter, and take the capsule from under the pointer.
    func pointer(over: Bool, shot id: Shot.ID, view: NSView?) {
        if unfolded {
            if over {
                focus = id
                focused = view
            } else if focus == id {
                focus = nil
            }
        } else if id == shots.last?.id {
            pointer(over: over)
        }
    }

    /// A click on a shot: on the pile it unfolds the row; on a shot of the row, or on the single shot, it is «Edit».
    func clicked(_ id: Shot.ID) {
        if isPile { return unfold() }
        if unfolded { focus = id }
        edit()
    }
}

/// What the capsule over a thumbnail offers, in order; the ✕ stands after a divider. «Edit» only where there is
/// something to open the editor on (`ShotToastModel.editSource`), «Show in Finder» only for a shot that has a
/// file, and Pin only while `PinEntry.isOffered`. A folded pile's capsule acts on the whole group (`pileCells`).
enum ShotCapsule {
    enum Cell: Equatable { case edit, copy, copyAll, reveal, pin, close }

    static func cells(hasFile: Bool, canEdit: Bool = false, pinOffered: Bool = PinEntry.isOffered) -> [Cell] {
        var cells: [Cell] = canEdit ? [.edit, .copy] : [.copy]
        if hasFile { cells.append(.reveal) }
        if pinOffered { cells.append(.pin) }
        return cells + [.close]
    }

    /// The pile's: «Copy All (N) · Show in Finder | ✕». No Edit and no Pin, which are about one picture; «Show in
    /// Finder» while any shot of the group has a file.
    static func pileCells(hasFile: Bool) -> [Cell] {
        hasFile ? [.copyAll, .reveal, .close] : [.copyAll, .close]
    }

    /// Between a cell and the capsule's edge: the mockup's 4 pt, so a 28 pt cell makes a capsule 36 pt high.
    static let inset = HelmSpace.s2
    /// The divider's height and each side's air. The mockup's 22 pt is on no step of `HelmSpace`, whose steps are
    /// 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40.
    static let separatorHeight: CGFloat = 22
    static let separatorGap = HelmSpace.s2
    private static let dividerWidth: CGFloat = 1
    /// Between one cell and the next, the mockup's 2 pt: the divider's air is its own and comes on top of it.
    static let gap = HelmSpace.s1

    /// The capsule's width for a number of cells, the ✕ counted: a gap between each two cells (the divider stands in
    /// the gap before the ✕ and is not a cell). Computed from the numbers the capsule is laid out by.
    static func width(cellCount: Int) -> CGFloat {
        CGFloat(cellCount) * HelmSpace.s7 + CGFloat(max(0, cellCount - 1)) * gap + dividerWidth + 2 * separatorGap + 2 * inset
    }

    /// The widest the capsule can be while the picture is not wider: the room the window keeps for it.
    static var widest: CGFloat { width(cellCount: cells(hasFile: true, canEdit: true).count) }

    /// How far the capsule stands up from the picture's lower edge, and how far its top is from that edge: a cell
    /// with the inset above and below it, on the rise.
    static let rise = HelmSpace.s4
    static var reach: CGFloat { rise + HelmSpace.s7 + 2 * inset }
}

/// A transparent AppKit view behind the capsule's cells that answers a press anywhere in the capsule's shape and
/// does nothing with it. SwiftUI's own hit test leaves the rim and the divider to what lies below.
final class ShotCapsuleView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let radius = bounds.height / 2
        return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

struct ShotCapsuleShield: NSViewRepresentable {
    func makeNSView(context: Context) -> ShotCapsuleView { ShotCapsuleView() }
    func updateNSView(_ view: ShotCapsuleView, context: Context) {}
}

/// The after-shot window's panel. **Key only while the row is unfolded, and only from a click on itself**: that is
/// how Esc reaches the row, and Helm is not activated for it. It is the pin's rule (`PinPanel.takesKey`) with one
/// more condition and one more event: the click that unfolds the pile is over when the row exists, so the panel is
/// made key at the mouse's coming up, not at its going down. Folded or single it never takes key: a click on a
/// thumbnail must not take the person's typing from the app they are in.
///
/// That `makeKey` from a mouse-up on a non-activating panel gives it the keys while another app stays active is
/// not measured; the pin's rule rests on the same call from a mouse-down.
final class ShotPanel: NSPanel {
    var isUnfolded: () -> Bool = { false }
    var onEscape: () -> Void = {}

    override var canBecomeKey: Bool {
        ShotPanel.takesKey(from: NSApp.currentEvent, windowNumber: windowNumber, unfolded: isUnfolded())
    }

    static func takesKey(from event: NSEvent?, windowNumber: Int, unfolded: Bool) -> Bool {
        guard unfolded, let event else { return false }
        return (event.type == .leftMouseDown || event.type == .leftMouseUp) && event.windowNumber == windowNumber
    }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onEscape() }

    override func keyDown(with event: NSEvent) {
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
    }
}

@MainActor final class ShotToast {
    /// Not private: a test wires the close control through it without a panel.
    let model = ShotToastModel()
    private var panel: ShotPanel?
    private var host: NSView?
    private var dismissal: Task<Void, Never>?
    /// One step of the lifetime's clock. A seam: a test passes a wait it controls, and the running app sleeps.
    private let tick: (Duration) async throws -> Void
    /// Whether to put a panel on the screen; a test builds none.
    private let windowed: Bool
    /// Whether the pointer is over the window's shots, in screen points: inside the anchor view's rect, or anywhere
    /// in the row while it is unfolded. Asked by `advance`: under a hold that only the pointer keeps, to end it when
    /// the pointer is elsewhere; when the time is up, to hold when it is there; and of an unfolded row at every
    /// step, to fold it once the pointer has been away for `ShotShelf.foldDelay`. A seam for a test.
    var pointerIsOver: () -> Bool = { false }
    /// What the capsule's Edit, Copy, Copy All and Pin ask of whoever owns the session and the board.
    var onEdit: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCopyAll: () -> Void = {}
    var onPin: (CGImage, CGRect) -> Void = { _, _ in }
    /// Makes the panel key when the row unfolds, and gives the keys back when it folds. Seams: a test has no panel
    /// and counts the calls.
    ///
    /// Giving back is ordering the panel out and in again: AppKit has no call that only resigns key. That a key
    /// window that leaves the screen hands the keys to the next that can take them, and that the two orders in one
    /// turn of the run loop are not seen as a blink, are not measured.
    var takeKey: () -> Void = {}
    var yieldKey: () -> Void = {}
    /// Closes a sheet that is open. A seam: a test reads which sheet was closed, and the running app asks the picker.
    var closePicker: (NSSharingServicePicker) -> Void = { $0.close() }
    /// Shows the sheet relative to the thumbnail's view. A seam: a test must not open a system sheet.
    var presentPicker: (NSSharingServicePicker, NSView) -> Void = { picker, view in
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    /// What keeps the lifetime from running: the pointer over the picture or the pile, the Share sheet open, the
    /// editor open on a shot taken from a group. An unfolded row is not a hold: while it is unfolded the lifetime
    /// is not counted at all.
    enum Hold: Hashable { case pointer, sheet, editor }
    private(set) var holds: Set<Hold> = []
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
    private var wantsShare = false
    private var picker: NSSharingServicePicker?
    private var pickerDelegate: PickerDelegate?

    private static let step = 0.1
    /// Seconds a group lives once its last result is in, and once a refusal over it has gone.
    private static let life: Double = 5

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
        show(lasting: 6) {
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

    /// The plaque, in the shots' place for its nine seconds. **Only the refusal of the still-writing shot's own write
    /// (`ofItsWrite`) takes that shot away**; a refusal of a Copy, an Edit or a capture the shot has no part in leaves
    /// it, and its result still lands on it. The other shots are kept under the plaque, folded, and are back when it
    /// goes (`advance`, `close`).
    func showRefusal(_ reason: CaptureRefusal, ofItsWrite: Bool = false) {
        show(lasting: 9) {
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
    /// full disk is not mended in the Privacy pane. Its own function so the
    /// decision is one a test can ask without a window.
    static func refusalContent(_ reason: CaptureRefusal) -> ShotToastModel.Content {
        let permission = reason == .noPermission
        let title: String
        switch reason {
        case .noPermission: title = ScStr.noPermissionTitle
        // A shot that was taken and could not be opened or replaced: «not taken» would be untrue of it.
        case .notEditable, .notReplaced: title = ScStr.thumbnailLabel
        case .captureFailed, .displayGone, .windowGone, .write, .pasteboard, .encoding: title = ScStr.failedTitle
        }
        return .refusal(title: title, body: ScStr.refusal(reason), offersSettings: permission)
    }

    /// The whole window goes, with every shot on the list and everything they held.
    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        // A sheet left open under a window that is gone would sit beside the one the next Share opens.
        if let picker { closePicker(picker) }
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

    // MARK: - Share

    /// Asks for the system's Share sheet at the newest shot's thumbnail, as soon as the thumbnail's view is on a
    /// window. The toast holds from the sheet's opening to its end: the lifetime would otherwise close the panel
    /// under the sheet. How the pointer's events go while the sheet is up is not measured.
    func requestShare() {
        wantsShare = true
        attemptShare()
    }

    /// What the sheet shares: the newest shot's file when there is one, else its picture.
    func shareItems() -> [Any]? {
        guard model.refusal == nil, let shot = model.shots.last else { return nil }
        if let file = shot.file { return [file] }
        return shot.full.map { [NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))] }
    }

    private func attemptShare() {
        guard wantsShare, let anchor = model.anchor else { return }
        // One sheet at a time; a second request is the first one's.
        guard picker == nil else { wantsShare = false; return }
        // No sheet over a path that is gone.
        if model.refusal == nil, let file = model.shots.last?.file, !FileManager.default.fileExists(atPath: file.path) {
            wantsShare = false
            return
        }
        guard let items = shareItems() else { return }
        wantsShare = false
        let picker = NSSharingServicePicker(items: items)
        let delegate = PickerDelegate()
        // The end of a sheet that was dismissed or replaced is not the end of the one that stands.
        delegate.ended = { [weak self, weak delegate] in
            guard let self, let delegate, self.pickerDelegate === delegate else { return }
            self.sheetEnded()
        }
        picker.delegate = delegate
        self.picker = picker
        pickerDelegate = delegate
        holds.insert(.sheet)
        presentPicker(picker, anchor)
    }

    /// The sheet is over, chosen from or cancelled.
    func sheetEnded() {
        holds.remove(.sheet)
        picker = nil
        pickerDelegate = nil
    }

    private final class PickerDelegate: NSObject, NSSharingServicePickerDelegate {
        var ended: () -> Void = {}
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) { ended() }
    }

    // MARK: - What the capsule does

    /// The full picture of the shot an action is about: held for a shot that was only copied, read back from its
    /// file for a saved one.
    func fullPicture() -> CGImage? {
        guard model.refusal == nil, let shot = model.current else { return nil }
        if let full = shot.full { return full }
        guard let file = shot.file, let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Where every finished shot's full picture is, oldest first: what «Copy All» hands to the session, which reads
    /// the files itself, one at a time.
    func sources() -> [ShotSource] {
        model.shots.compactMap { shot in
            if let full = shot.full { return .picture(full) }
            return shot.file.map { .file($0) }
        }
    }

    /// The picture as a pin, where the thumbnail stands; the shot leaves the window.
    private func pin() {
        guard let image = fullPicture(), let shot = model.current,
              let view = model.unfolded ? model.focused : model.anchor, let window = view.window else { return }
        // The picture's own rect: the view is larger than the picture while the capsule is up over a small shot.
        let rect = (view as? ShotDragView)?.pictureFrame ?? view.bounds
        onPin(image, window.convertToScreen(view.convert(rect, to: nil)))
        if model.unfolded { remove(shot.id) } else { dismiss() }
    }

    // MARK: -

    /// Puts what `change` made of the model on the screen, for `seconds`. The clock starts over, as the mockup's
    /// group does with every new shot.
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

    private func makePanel() -> ShotPanel {
        let panel = ShotPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isUnfolded = { [weak model] in model?.unfolded ?? false }
        panel.onEscape = { [weak self] in self?.fold() }
        // The shots stand against the panel's lower trailing corner whatever its size: a row that folds is drawn
        // inside the row's panel until the fold is over, and must not be centred in it meanwhile.
        let host = NSHostingView(rootView: ShotToastView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        let ground = NSView()
        ground.addSubview(host)
        NSLayoutConstraint.activate([host.trailingAnchor.constraint(equalTo: ground.trailingAnchor),
                                     host.bottomAnchor.constraint(equalTo: ground.bottomAnchor)])
        panel.contentView = ground
        self.host = host
        return panel
    }

    /// Lower right of the screen the pointer is on, inside the visible frame; a picture stands 20 pt from the edges
    /// itself, the room round it that its shadow is drawn in not counted.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        var inset: CGFloat = 20
        if model.showsShots { inset -= Self.shadowRoom }
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset))
    }

    /// The panel takes the size of what it shows now and keeps its lower trailing corner: the row unfolding, a shot
    /// leaving it, the fold once it is drawn. The screen is not chosen again, as `place` would by the pointer.
    private func refit() {
        guard let panel, let host else { return }
        let size = host.fittingSize, frame = panel.frame
        panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: size.height),
                       display: true)
    }

    /// The refusal's width.
    static let width: CGFloat = 252
    /// Clear round the picture for its shadow: the panel's own is off, and the picture's is drawn in this room. The
    /// shadow's blur and its offset down, both of the mockup's, fit in it.
    static let shadowRoom = HelmSpace.s8

    /// Small enough to hold for as long as the window lives without holding
    /// the frame: a 5K picture is tens of megabytes and this is a small fraction of that.
    static func thumbnail(of image: CGImage) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        let target = ShotThumbnail.longestEdge
        guard longest > target else { return image }
        let scale = target / longest
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

struct ShotToastView: View {
    @ObservedObject var model: ShotToastModel

    var body: some View {
        Group {
            if case .refusal(let title, let body, let offersSettings)? = model.refusal {
                refusal(title: title, body: body, offersSettings: offersSettings)
                    .padding(HelmSpace.s5)
                    .frame(width: ShotToast.width)
                    // Glass and no edge of our own: it carries its own.
                    .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
            } else if !model.shots.isEmpty {
                shelf(model.shots)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .opacity(model.shown ? 1 : 0)
        .offset(x: model.shown ? 0 : 24)
        .animation(HelmMotion.interface, value: model.shown)
    }

    // MARK: - The shots

    /// One shot, the pile or the row: the same views in all three, placed by `ShotShelf`, so a shot keeps its view
    /// from the single picture through the pile to the row and travels between them.
    ///
    /// Everything stands against the lower trailing corner, where the newest shot is in every shape. The row is as
    /// wide as `ShotShelf.width`; past `ShotShelf.visible` shots it is cut at its ends (`rowMask`), and only then
    /// is there a mask at all: the single shot and a group that fits are drawn as they always were.
    @ViewBuilder private func shelf(_ shots: [ShotToastModel.Shot]) -> some View {
        if shots.count > ShotShelf.visible {
            sheets(shots).mask { rowMask(count: shots.count, clips: model.unfolded) }
        } else {
            sheets(shots)
        }
    }

    private func sheets(_ shots: [ShotToastModel.Shot]) -> some View {
        let count = shots.count
        let row = model.unfolded && count > 1
        let more = row ? ShotShelf.more(count: count, offset: model.offset) : nil
        return ZStack(alignment: .bottomTrailing) {
            // The row's shadows lie under every picture: a shot's own would fall on the picture of the older shot
            // beside it. In the pile each sheet's shadow is its own, on the sheet under it.
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                ring(of: shot, shadow: row ? Self.shadow : 0)
                    .opacity(row ? 1 : 0)
                    .offset(x: row ? ShotShelf.shift(age: count - 1 - index, offset: model.offset, count: count) : 0)
                    .zIndex(-Double(ShotShelf.limit + 1))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                let age = count - 1 - index
                let sheet = ShotShelf.sheet(age: age)
                picture(shot, age: age, count: count)
                    .overlay(alignment: .topLeading) {
                        if let more, more.on == age { moreLabel(more.count).offset(x: -Self.moreOut, y: -Self.labelOut) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !row, count > 1, age == 0 { counter(count).offset(x: Self.labelOut, y: -Self.labelOut) }
                    }
                    .scaleEffect(row ? 1 : sheet.scale, anchor: .topLeading)
                    .opacity(row ? 1 : sheet.opacity)
                    .offset(x: row ? ShotShelf.shift(age: age, offset: model.offset, count: count) : sheet.offset.width,
                            y: row ? 0 : sheet.offset.height)
                    .zIndex(Double(-age))
                    // A sheet that is not drawn takes no press and is not read.
                    .allowsHitTesting(row || age < ShotShelf.visible)
                    .accessibilityHidden(!row && age > 0)
            }
        }
        // Room for the capsule where the picture is narrower than it; the ring stays round the picture, at the
        // trailing edge, which is the one `ShotToast.place` stands 20 pt from the screen's.
        .frame(minWidth: row ? max(ShotShelf.width(count: count), ShotCapsule.widest) : ShotCapsule.widest,
               alignment: .bottomTrailing)
        .overlay(alignment: .bottomTrailing) {
            if row, model.barShown { scrollBar(count: count) }
        }
        .padding(ShotToast.shadowRoom)
        .animation(HelmMotion.interface, value: model.hovering)
        .animation(HelmMotion.interface, value: model.focus)
    }

    /// How far the counter and «N more» stand out of the picture's corner, the mockup's 10 pt.
    private static let labelOut: CGFloat = 10
    /// How far «N more» stands out of the picture's left edge, not the mockup's 10 pt (`labelOut`, which it keeps
    /// upward): the far shot's ring is 3 pt wider than its slot, and at 10 the capsule's left cap lay 6.5 pt past the
    /// row's cut, `rowOverhang`, and was cut flat; at 3 it lies 0.5 pt inside it.
    private static let moreOut: CGFloat = 3
    /// How far past the row's end it is still drawn: room for «N more», which stands `moreOut` out of the farthest
    /// whole shot, and short of the ring of the hidden shot beyond it, which begins
    /// `ShotShelf.gap` less the ring's extra width, 10 pt, from the shown one: at 12 its last 2 pt were drawn.
    private static let rowOverhang: CGFloat = 9

    /// What of the row is drawn. The end toward the oldest shot is cut while there are shots past it, the end toward
    /// the newest while the row is scrolled off it; between two rests the cut fades over `ShotShelf.edgeFade`. The
    /// pile is not cut: the mask is then far larger than it is, since a row that folds travels through the room
    /// the row had.
    private func rowMask(count: Int, clips: Bool) -> some View {
        let far = ShotShelf.farthest(count: count)
        let between = abs(model.offset - ShotShelf.snapped(model.offset, count: count)) > 0.5
        let fade = between ? ShotShelf.edgeFade : 0
        let margin = ShotToast.shadowRoom - Self.rowOverhang
        return HStack(spacing: 0) {
            if clips, model.offset < far - 0.5 {
                Color.clear.frame(width: margin)
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fade)
            }
            Rectangle()
            if clips, model.offset > 0.5 {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: fade)
                Color.clear.frame(width: margin)
            }
        }
        .padding(clips ? 0 : -Self.unclipped)
    }

    private static let unclipped: CGFloat = 2000

    /// The row's bar: as long as the part of the row that is seen, under the pictures, where the row is scrolled to.
    /// Drawn here and not the system's: the row is not a scroll view, its rests are `ShotShelf`'s.
    private func scrollBar(count: Int) -> some View {
        let row = ShotShelf.width(count: count), far = ShotShelf.farthest(count: count)
        let length = row * CGFloat(ShotShelf.visible) / CGFloat(max(count, ShotShelf.visible))
        let travelled = far > 0 ? model.offset / far : 0
        return Capsule()
            .fill(Color.primary.opacity(0.45))
            .frame(width: length, height: HelmSpace.s2)
            .offset(x: -travelled * (row - length), y: HelmSpace.s5 + HelmSpace.s2)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// The pile's counter: how many shots there are, all of them.
    private func counter(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, HelmSpace.s3)
            .frame(minWidth: Self.labelHeight, minHeight: Self.labelHeight)
            .glassEffect(.regular, in: .capsule)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// «N more» on the farthest shot that is seen whole; a click shows the row from its oldest shot. **One line at its
    /// own width, whatever the shot's:** it stands over the picture's corner and is offered the picture's width, which
    /// a tall narrow window's is too little for «3 weitere» or «還有 3 張».
    private func moreLabel(_ count: Int) -> some View {
        Button { model.showOldest() } label: {
            Text(ScStr.more(count))
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, HelmSpace.s4)
                .frame(minHeight: Self.labelHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity)
    }

    /// The mockup's 22 pt, on no step of `HelmSpace`.
    private static let labelHeight: CGFloat = 22

    /// One shot, in a white frame: the thumbnail macOS shows. The caption is not on the screen; it is the value
    /// a screen reader reads. The capsule comes up from the lower edge while the pointer is over it, and only when
    /// the result is in, since Edit, Copy and Show in Finder need what was written. On the newest sheet of a folded
    /// pile the capsule is the group's, and the sheet is named by the count.
    ///
    /// **While the capsule is up the pointer's zone is the picture and the capsule together.** On a shot narrower
    /// or shorter than the capsule the cells reach outside the picture, and a zone that was the picture alone
    /// would lose the pointer on its way to an outer cell and take the capsule from under it. On a shot narrower
    /// than the capsule both stand against the picture's trailing edge and reach leftward, into the window's own
    /// room: the ring stays where `ShotToast.place` counts on it, by the screen's edge, and the capsule stays on
    /// the screen.
    private func picture(_ shot: ToastShot, age: Int, count: Int) -> some View {
        let image = shot.image
        let pile = count > 1 && !model.unfolded
        let size = ShotThumbnail.fitted(pixels: CGSize(width: image.width, height: image.height))
        let cells = pile ? ShotCapsule.pileCells(hasFile: model.shots.contains { $0.file != nil })
            : ShotCapsule.cells(hasFile: shot.file != nil, canEdit: model.editSource(of: shot) != nil)
        let capsuleWidth = ShotCapsule.width(cellCount: cells.count)
        let pointed = model.unfolded ? model.focus == shot.id : model.hovering && age == 0
        let capsuleUp = pointed && shot.caption != nil
        let narrow = size.width < capsuleWidth
        let zone = capsuleUp
            ? CGSize(width: max(size.width, capsuleWidth), height: max(size.height, ShotCapsule.reach)) : size
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Self.pictureRadius))
            .overlay(alignment: narrow ? .bottomTrailing : .bottom) {
                ShotDragSource(model: model, shot: shot.id, preview: image, picture: size, trailing: narrow, newest: age == 0)
                    .frame(width: zone.width, height: zone.height)
            }
            .overlay(alignment: narrow ? .bottomTrailing : .bottom) {
                if capsuleUp { capsule(cells, of: shot) }
            }
            .padding(Self.frameWidth)
            // The shadow belongs to the ring's own shape: the capsule's glass and glyphs on the picture cast none.
            .background {
                ring(of: shot, shadow: model.unfolded && count > 1 ? 0 : age > 0 ? Self.lowerShadow : Self.shadow,
                     lower: age > 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pile ? ScStr.screenshots(count) : ScStr.thumbnailLabel)
            .accessibilityValue(shot.caption ?? "")
    }

    private typealias ToastShot = ShotToastModel.Shot

    /// The white ring round a shot's picture, with the shadow it casts: the sheets under the top one cast the
    /// mockup's lighter one (`lower`: 0 6 18 at .25), the top sheet's is 0 10 30 at .35.
    private func ring(of shot: ToastShot, shadow: Double, lower: Bool = false) -> some View {
        let size = ShotThumbnail.fitted(pixels: CGSize(width: shot.image.width, height: shot.image.height))
        return RoundedRectangle(cornerRadius: Self.pictureRadius + Self.frameWidth)
            .fill(.white)
            .frame(width: size.width + 2 * Self.frameWidth, height: size.height + 2 * Self.frameWidth)
            .shadow(color: .black.opacity(shadow), radius: lower ? 18 : 30, y: lower ? 6 : 10)
    }

    private static let shadow = 0.35
    private static let lowerShadow = 0.25

    /// The mockup's 3 pt white ring and 5 pt picture corner (the ring's outer corner is 8). `HelmRadius` has
    /// 4 · 6 · 10 · 14 · 26, so neither corner is on the ladder, and the ring has no token.
    private static let frameWidth: CGFloat = 3
    private static let pictureRadius: CGFloat = 5

    /// «Edit · Copy · Show in Finder (· Pin) | ✕», or the pile's «Copy All (N) · Show in Finder | ✕», on glass, 8 pt
    /// up from the picture's lower edge.
    ///
    /// **The whole capsule takes the press** (`ShotCapsuleView`): under it lies the drag view, whose click is «Edit»,
    /// and a press on the rim or the divider that reached it would open the editor and take the thumbnail away.
    private func capsule(_ cells: [ShotCapsule.Cell], of shot: ToastShot) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: ShotCapsule.gap) {
                ForEach(cells.filter { $0 != .close }, id: \.self) { cell in
                    switch cell {
                    case .edit: GlassCell(symbol: "pencil", name: ScStr.edit) { model.edit() }
                    case .copy: GlassCell(symbol: "doc.on.doc", name: ScStr.copy) { model.copy() }
                    case .copyAll:
                        GlassCell(symbol: "doc.on.doc", name: ScStr.copyAll(model.shots.count { $0.caption != nil })) {
                            model.copyAll()
                        }
                    case .reveal: GlassCell(symbol: "folder", name: ScStr.showInFinder) { reveal(shot) }
                    case .pin: GlassCell(symbol: "pin", name: ScStr.pin) { model.pin() }
                    case .close: EmptyView()
                    }
                }
                Divider().frame(height: ShotCapsule.separatorHeight).padding(.horizontal, ShotCapsule.separatorGap)
            }
            closeCell
        }
        .padding(ShotCapsule.inset)
        .background { ShotCapsuleShield() }
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, ShotCapsule.rise)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// This shot's file in Finder; from a folded pile, every file of the group that is still there, selected together.
    private func reveal(_ shot: ToastShot) {
        guard model.isPile else {
            if let file = shot.file { HelmReveal.inFinder(file.path) }
            return
        }
        let files = model.shots.compactMap(\.file).filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.count > 1 {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } else if let file = files.first ?? model.shots.compactMap(\.file).last {
            HelmReveal.inFinder(file.path)
        }
    }

    /// The way off the screen: the capsule's ✕ on a thumbnail whose result is in (in the row it takes that shot
    /// alone, `ShotToast.close`), and the refusal's, which stays up nine seconds in the corner where the next click
    /// goes. A thumbnail still being written has none.
    private var closeCell: some View {
        GlassCell(symbol: "xmark", name: ScStr.dismissToast) { model.dismiss() }
    }

    private func refusal(title: String, body: String, offersSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            // Clear of the close control in the corner.
            Text(title).font(HelmText.rowTitle).padding(.trailing, HelmSpace.s7)
            Text(body)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if offersSettings {
                Button(ScStr.openSettings) { PermissionNeed.screenRecording.openSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { closeCell }
    }
}
