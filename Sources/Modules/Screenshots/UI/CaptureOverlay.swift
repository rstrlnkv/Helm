import AppKit
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the person decided on the overlay.
enum OverlayResult {
    /// An area on one display, in that display's own top-left points, with the
    /// layers drawn over it and the way the person left. Every area arrives this
    /// way — with no layers, as a plain crop.
    case edited(display: DisplayID, local: CGRect, layers: [Annotation], exit: EditorExit)
    /// A window, by id, and whether its shadow is in the picture: it is, unless the click was an option-click.
    case window(UInt32, shadow: Bool)
    case wholeDisplay(DisplayID)
    case cancelled
}

/// What the editor asks of the capture's session for the text of an area: the overlay holds the freeze, so a call names the display and the
/// area only. A closure pair and not the session, as `pinRoom` is a closure: the overlay never owns what it asks.
struct EditorTextTools {
    var read: (DisplayID, CGRect) async -> CaptureSession.AreaReading
    var copy: ([RecognizedLine]) -> CaptureSession.TextCopy
    /// No session behind it: every reading fails, which is the one answer that cannot be mistaken for a reading.
    static var none: EditorTextTools { EditorTextTools(read: { _, _ in .failed }, copy: { _ in .refused }) }
}

/// The freeze-frame overlay: one panel per display, all of them one selection
/// machine.
///
/// **A non-activating key panel and no event tap.** The panel becomes key
/// without making Helm the active application, so it reads the keyboard and the
/// pointer itself and needs no Accessibility — the grant a tap would have cost.
/// It draws over the menu bar and the Dock and over full-screen apps, in every
/// Space, and it has no `FrontmostApp` to hand focus back to because it never
/// took any.
///
/// **The state lives here and not in a view.** A drag starts on one display and
/// a key is pressed on whichever panel is key, so the pieces that decide what
/// the selection is — mode, drag, space — cannot belong to one panel's view.
/// Views report what happened to them and draw what this says.
///
/// **Two phases, one panel.** Selecting is the drag; once an area is released the
/// overlay stays and edits it: `edit` is non-nil, the crosshair is gone and the size
/// plate stays over the area's top-left corner, with a loupe on the pixel while an area handle is held or the eyedropper is on, and the keys mean tools, undo and the exits. The picture under the
/// layers is never touched, so every layer is a value that can be undone.
///
/// **Nothing is dimmed until there is a selection** (a drag that has moved, an edit, a remembered area), and a
/// window pick is never dimmed: the window under the pointer is filled with the accent instead. The lines across
/// the screen are drawn only while ⌥ is held. A shot that is taken ends in a flash and the overlay closes after it,
/// unless Reduce Motion is on, when it closes at once (`close(after:)`).
@MainActor final class CaptureOverlay {
    /// What the overlay opens in: the area crosshair, or the camera over windows.
    enum Mode { case area, window }

    let freeze: Freeze
    private var onFinish: ((OverlayResult) -> Void)?
    var panels: [DisplayID: (panel: OverlayPanel, view: OverlayView)] = [:]
    private var screenObserver: NSObjectProtocol?

    var mode: Mode { didSet { render() } }
    var drag: (display: DisplayID, drag: SelectionDrag)?
    /// The remembered area the panel's Area mode opens on, drawn as a selection
    /// that Return confirms and any new drag replaces. A reading, already cut to
    /// the display as it is now by `RememberedSelection.landing`.
    var preselected: (display: DisplayID, rect: CGRect)?
    /// The panel's overlay: the area that was drawn when a new drag began, and comes back if that drag is not usable.
    var replacedByDrag: (display: DisplayID, rect: CGRect)?
    /// A finished picture the overlay was opened on (`PictureOnScreen`): the editor is up at once on its rectangle,
    /// and that rectangle is the bounds of the area, so the area is never more than the picture.
    let picture: (display: DisplayID, rect: CGRect)?
    var spaceHeld = false
    /// ⌥ is down, as the last `flagsChanged` said: the lines across the screen are drawn only then.
    var optionHeld = false
    /// The flash is on and the overlay is waiting to close: no input reaches it (`OverlayView` is deaf), and it
    /// finds nobody to deliver to, since `finish` has already run.
    private(set) var leaving = false
    /// Whether Reduce Motion is on, read at the moment of the shot. A test sets it: the setting is the machine's.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }
    /// Whether Increase Contrast is on, read when a display's view is built. A closure so that a stand can set it, since the setting is the machine's; no test does.
    var increasesContrast: () -> Bool = { HelmAccessibility.system.increasedContrast }
    /// The panels are up: false before `build` and after `close`.
    var isOpen: Bool { !panels.isEmpty }
    /// The area being edited, set once a selection is released; nil while selecting.
    var edit: (display: DisplayID, rect: CGRect, layers: AnnotationEditing, tool: AnnotationTool?)?
    /// The eraser is on: a drag takes away the layers it meets (`AnnotationEditing.beginErase`) and `edit.tool` stays what it
    /// was under it. A mode of this overlay and no `AnnotationTool`, so `EditorMemory` is never asked to keep it.
    var erasing = false
    /// The eyedropper is on (`EditorAction.eyedropper`): the loupe follows the pointer over the area, and the next click on the area picks the
    /// pixel of the frozen picture under it as the colour (`PixelLoupe`, read from the frame and never from a layer). A mode of this overlay like
    /// the eraser and Crop, nothing of it remembered; any other action, Esc, a right click on the picture (or on any display when the overlay has no picture), a press on the picture and `close` put it down.
    /// A press on the palette is the palette's: its actions end the mode, its bare background does not.
    var sampling = false
    /// The radius of the eraser's circle, in points of the display: what a drag meets and what the cursor draws.
    static let eraserRadius: CGFloat = 9
    /// The ruler is on the picture, a switch of this overlay (`EditorAction.toggleRuler`) over whatever tool is chosen: not a layer, so
    /// no undo step and no export sees it, and nothing of it is remembered. It lives while the overlay does.
    var ruler: Ruler?
    /// A press on the ruler's strip that is still down: the display, and whether the drag takes the strip along or turns it. A move keeps
    /// where the strip's centre was from the pointer; a turn keeps the angle the strip had and the direction the pointer pressed in.
    var rulerDrag: (display: DisplayID, kind: RulerDrag)?
    enum RulerDrag { case move(offset: CGPoint), turn(base: CGFloat, from: CGFloat) }
    /// A rotate gesture of the trackpad in progress: the angle the strip had when it began and how far the fingers have turned,
    /// clockwise; the strip's own angle sticks to 0°, 45° and 90° and so cannot be the sum.
    var rulerTurn: (base: CGFloat, sum: CGFloat)?
    /// An area handle under the pointer: which one, the area as the press took it and where the
    /// press landed. Not an edit of the layers, so no undo step: the area is not a layer.
    var reshaping: (display: DisplayID, handle: AreaHandle, base: CGRect, press: CGPoint)?
    /// Crop is on: the area as it stood when the mode began, the base area. A mode of this overlay, like the eraser, and no `AnnotationTool`. The
    /// area is reshaped live by its handles, as `reshaping` does, and Return takes what it has become, which is no undo step; Esc, Crop
    /// asked again, a tool, the eraser and Select put this one back. Nothing of it is remembered.
    var crop: CGRect?
    /// The pointer on the display it is over, in that display's top-left points.
    var pointer: (display: DisplayID, point: CGPoint)?
    var hovered: FrozenWindow?
    /// What the next object is drawn with; picked on the palette, read from the store when
    /// the first area is released, and kept across the areas of one capture.
    var style = AnnotationStyle.standard
    /// The tool whose own colour, step and opacity `style` carries: the last one picked, and the pen before any.
    var styleTool = AnnotationTool.pen
    /// What the store holds, kept beside it so that a tool's own colour, step and opacity come back
    /// when the tool does, in a test with no store as well.
    var memory = EditorMemory()
    /// Where the editor's last tool, colour, thickness and fill are kept. Nil in a test that
    /// remembers nothing.
    let store: NamespacedStore?
    /// What opens the system's colour panel (`.allColours`).
    let colourPanel = EditorColourPanel()
    /// The pop-over that is open, one at a time: the thickness and opacity one, open only while a tool is chosen, or the
    /// colours one, and the centre of the cell that opened it, in the palette's own points. Closed by everything that
    /// puts the tool down, and by the exits.
    var popover: (kind: PopoverKind, anchorX: CGFloat)?
    enum PopoverKind { case thickness, colours }
    /// Which pop-over is open: `thicknessIsOpen` and `coloursAreOpen`, which the overlay reads to place, draw and close it.
    var thicknessIsOpen: Bool { popover?.kind == .thickness }
    /// The layers the editor holds now, in the list's order, for a test that holds the screen against the file made from them.
    var editedLayers: [Annotation] { edit?.layers.layers ?? [] }
    /// The area the editor holds now, a crop still pending included, for a test that reads it without leaving.
    var editedArea: CGRect? { edit?.rect }
    var coloursAreOpen: Bool { popover?.kind == .colours }
    /// The text being typed: the display whose field it is in and where the line starts, in that display's top-left
    /// points. The field itself is the view's (`OverlayView.textField`); this is the overlay's one record that an input
    /// is open; the ways out of it go through `endTyping`, and `close` drops the record itself. Nil when none is.
    var typing: (display: DisplayID, at: CGPoint)?
    /// The emoji the Emoji tool places on the next click on the picture, picked in the grid; nil until one is. Nothing of it is remembered.
    var emoji: String?
    /// What the emoji grid shows; its cells come back through `perform` as `.pickEmoji`.
    let emojiGrid = EmojiGridModel()
    /// What the palette shows; its cells come back through `perform`.
    let palette = EditorBarModel()
    /// The ⋯ menu: one object, filled again from `palette` at every opening.
    lazy var moreMenu = EditorMenu.make(for: palette)
    /// The menu while `popUp` has not returned, so that `close` can end its tracking without making a menu never opened.
    var openedMenu: NSMenu?

    /// Whether another pin may open: asked at the ⋯ menu's Pin item (`.exit(.pin)`) and nowhere else, so the
    /// other exits leave at the limit as ever. The item is built only while `PinEntry.isOffered`.
    let pinRoom: () -> Bool
    /// The Pin item was refused for want of room, and the plate says so until the next input. Every input sets it false, so
    /// it also takes away the plate of a finished reading (`textPlate`), which stands until the same next input.
    var pinRefused = false { didSet { if !pinRefused { textPlate = nil } } }
    let textTools: EditorTextTools
    /// A reading of the area's text that has not answered: what was asked of it, the task that waits, and the display and area it was
    /// asked for. One at a time. It ends with its answer, with the editor's close, and with any change of the area under it
    /// (`render`): its boxes were for the old area, so an answer for it is dropped. `serial` tells it from a later one.
    var reading: (serial: Int, ask: TextAsk, task: Task<Void, Never>, display: DisplayID, rect: CGRect)?
    var readingsBegun = 0
    enum TextAsk { case copy, blur }
    /// What the last finished reading says, on the plate by the palette; until the next input. The plates' order, first that applies: the
    /// refused pin, the Esc question that is still asked, this. An answer that comes while the pin's refusal is up takes the refusal down (it is
    /// the later thing to say, and Pin can be pressed again); one that comes while the question is asked waits behind it.
    var textPlate: String?
    /// A nudge let go of the selected object and the arrow key that did it is still down: its repeats
    /// move nothing. Any key or palette click that reaches `perform` while no drag or reshape is under way
    /// clears it, a fresh arrow press (not `isARepeat`) included, so a key-up the overlay never sees cannot
    /// leave the arrows dead; only a repeat can find it set. Mouse input, a modifier change, Esc and
    /// a right click do not go through `perform` and leave it as it was.
    var arrowReleasedObject = false

    /// The capture panel's overlay: the person only picks here — a window under the pointer, or an area that stays as
    /// drawn until a new drag replaces it — and the panel's Capture (or Return) takes it. **The palette never appears and
    /// `startEditing` is never called**, so there is no editor and no layer, and an area leaves as a plain crop.
    let selectionOnly: Bool
    /// Whether there is something for Capture to take (`hasTarget`), told at every change; the panel shows its button by it.
    var targetChanged: (Bool) -> Void = { _ in }
    var reportedTarget = false

    init(freeze: Freeze, mode: Mode = .area, preselection: (display: DisplayID, rect: CGRect)? = nil,
         picture: (display: DisplayID, rect: CGRect)? = nil, store: NamespacedStore? = nil, pinRoom: @escaping () -> Bool = { true },
         textTools: EditorTextTools = .none, selectionOnly: Bool = false,
         onFinish: @escaping (OverlayResult) -> Void) {
        self.freeze = freeze
        self.selectionOnly = selectionOnly
        self.pinRoom = pinRoom
        self.textTools = textTools
        self.store = store
        self.mode = mode
        self.preselected = mode == .area ? preselection : nil
        self.picture = picture
        self.onFinish = onFinish
        palette.perform = { [weak self] in self?.perform($0) }
        palette.openMenu = { [weak self] in self?.openMoreMenu() }
        emojiGrid.pick = { [weak self] in self?.perform(.pickEmoji($0)) }
    }

    // MARK: - Lifecycle

    /// False when the freeze and the screens are not the same set, in either
    /// direction: the overlay would cover part of the desk and leave the rest
    /// live, so there is none.
    func present() -> Bool {
        guard build() else { return false }
        show()
        return true
    }

    /// The panels and the observer, built and **not** ordered in: a test drives
    /// the events by hand and must not put a window on the screen of whoever runs
    /// it.
    func build() -> Bool {
        var screens: [DisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
                screens[DisplayID(number)] = screen
            }
        }
        for frame in freeze.frames {
            guard let screen = screens[frame.id] else { close(); return false }
            let view = OverlayView(frozen: frame, overlay: self)
            let panel = OverlayPanel(screen: screen, view: view)
            // Another display's panel made key (the pointer went there) ends an input that was open in this one.
            let id = frame.id
            panel.onResignKey = { [weak self] in
                MainActor.assumeIsolated { if self?.typing?.display == id { self?.endTyping() } }
            }
            panels[frame.id] = (panel, view)
        }
        // The other direction of the same rule: a screen the freeze has no frame
        // for — one plugged in during the freeze, or one the freeze filed as gone
        // while it is still there — would stay live under a capture.
        guard !panels.isEmpty, panels.count == NSScreen.screens.count else { close(); return false }

        // A display added or taken away while the overlay is open: the frames
        // are of a desk that no longer exists, so the capture ends.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.cancelled) }
        }

        // The pointer where it already is, so the coordinates plate is there at once.
        let mouse = NSEvent.mouseLocation
        for (id, entry) in panels where entry.panel.frame.contains(mouse) {
            pointer = (id, local(mouse, in: entry.panel, frame: entry.view.frozen.frame.height))
        }
        // Opened in window mode, the window under the pointer is lit at once; not for the panel's overlay, where the
        // pointer is over the panel that was pressed and the window beneath it is no choice.
        if mode == .window, !selectionOnly, let pointer { hovered = windowUnder(display: pointer.display, local: pointer.point) }
        if let picture { startEditing(display: picture.display, rect: picture.rect) }
        render()
        return true
    }

    func show() {
        let keyed = pointer.flatMap { panels[$0.display] } ?? panels.values.first
        for entry in panels.values { entry.panel.orderFrontRegardless() }
        keyed?.panel.makeKey()
        if let keyed { keyed.panel.makeFirstResponder(keyed.view) }
    }

    /// Closing is the event that ends delivery: it clears `onFinish` and `edit` (so an item chosen afterwards finds no
    /// editor to act on and no owner to call, and remembers no tool) and ends the tracking of an open ⋯ menu.
    func close() {
        openedMenu?.cancelTrackingWithoutAnimation()
        openedMenu = nil
        reading?.task.cancel()
        reading = nil
        onFinish = nil
        edit = nil
        popover = nil
        sampling = false
        colourPanel.close()
        typing = nil
        leaving = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for entry in panels.values {
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
        }
        panels.removeAll()
        NSCursor.arrow.set()
    }

    /// Closes as `close` does, after the flash of a shot that was taken: the selection's or the window's shape
    /// goes white and fades for `HelmMotion.interfaceDuration`, and the panels leave when it has. Under Reduce
    /// Motion, with nothing to flash (a cancel, a whole display, a pin) or with no display to flash on, it is
    /// `close()` at once. The picture is already taken from the freeze (the window's own comes from the system,
    /// of that window alone), so nothing the overlay draws in the meantime is in it.
    func close(after result: OverlayResult) {
        guard isOpen, let shot = flashShapes(of: result), !shot.rects.isEmpty,
              HelmMotion.flashes(reduceMotion: reducesMotion()) else { close(); return }
        for (display, rect) in shot.rects { panels[display]?.view.flash(over: rect, window: shot.window) }
        leaving = true
        // Held by the timer on purpose: the panels must outlive the flash whoever else lets go of the overlay. A
        // `close` that came first has cleared `leaving`, and there is nothing left to do.
        DispatchQueue.main.asyncAfter(deadline: .now() + HelmMotion.interfaceDuration) { [self] in
            MainActor.assumeIsolated { if leaving { close() } }
        }
    }

    /// What `result` is a shot of, by display: an area's rectangle and a window's parts. Nil where there is no flash.
    private func flashShapes(of result: OverlayResult) -> (rects: [DisplayID: CGRect], window: Bool)? {
        switch result {
        case .edited(let display, let local, _, let exit):
            return exit == .pin ? nil : ([display: local], false)
        case .window(let id, _):
            guard let hovered, hovered.id == id else { return nil }
            var parts: [DisplayID: CGRect] = [:]
            for frame in freeze.frames { if let part = windowPart(hovered, on: frame.id) { parts[frame.id] = part } }
            return (parts, true)
        case .wholeDisplay, .cancelled:
            return nil
        }
    }

    /// Once. Every route out lands here, and the second arrival — a click and a
    /// key in the same run-loop turn — finds nothing to call.
    func finish(_ result: OverlayResult) {
        guard let done = onFinish else { return }
        onFinish = nil
        done(result)
    }

    /// The view for a display, so a test can send it a real event.
    func view(for display: DisplayID) -> OverlayView? { panels[display]?.view }
}
