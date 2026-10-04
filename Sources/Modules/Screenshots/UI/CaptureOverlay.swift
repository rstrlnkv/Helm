import AppKit
import QuartzCore
import SwiftUI
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
/// plate stays over the area's top-left corner, with a loupe on the pixel while an area handle is held, and the keys mean tools, undo and the exits. The picture under the
/// layers is never touched, so every layer is a value that can be undone.
///
/// **Nothing is dimmed until there is a selection** (a drag that has moved, an edit, a remembered area), and a
/// window pick is never dimmed: the window under the pointer is filled with the accent instead. The lines across
/// the screen are drawn only while ⌥ is held. A shot that is taken ends in a flash and the overlay closes after it,
/// unless Reduce Motion is on, when it closes at once (`close(after:)`).
@MainActor final class CaptureOverlay {
    /// What the overlay opens in: the area crosshair, or the camera over windows.
    enum Mode { case area, window }

    private let freeze: Freeze
    private var onFinish: ((OverlayResult) -> Void)?
    private var panels: [DisplayID: (panel: OverlayPanel, view: OverlayView)] = [:]
    private var screenObserver: NSObjectProtocol?

    private var mode: Mode { didSet { render() } }
    private var drag: (display: DisplayID, drag: SelectionDrag)?
    /// The remembered area the panel's Area mode opens on, drawn as a selection
    /// that Return confirms and any new drag replaces. A reading, already cut to
    /// the display as it is now by `RememberedSelection.landing`.
    private var preselected: (display: DisplayID, rect: CGRect)?
    /// The panel's overlay: the area that was drawn when a new drag began, and comes back if that drag is not usable.
    private var replacedByDrag: (display: DisplayID, rect: CGRect)?
    /// A finished picture the overlay was opened on (`PictureOnScreen`): the editor is up at once on its rectangle,
    /// and that rectangle is the bounds of the area, so the area is never more than the picture.
    private let picture: (display: DisplayID, rect: CGRect)?
    private var spaceHeld = false
    /// ⌥ is down, as the last `flagsChanged` said: the lines across the screen are drawn only then.
    private var optionHeld = false
    /// The flash is on and the overlay is waiting to close: no input reaches it (`OverlayView` is deaf), and it
    /// finds nobody to deliver to, since `finish` has already run.
    private(set) var leaving = false
    /// What was lit by the flash, by display, in that display's top-left points; empty with no flash. Only a test
    /// reads it, and `close()` leaves it as it was.
    private(set) var flashed: [DisplayID: CGRect] = [:]
    /// Whether Reduce Motion is on, read at the moment of the shot. A test sets it: the setting is the machine's.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }
    /// The panels are up: false before `build` and after `close`.
    var isOpen: Bool { !panels.isEmpty }
    /// The area being edited, set once a selection is released; nil while selecting.
    private var edit: (display: DisplayID, rect: CGRect, layers: AnnotationEditing, tool: AnnotationTool?)?
    /// The eraser is on: a drag takes away the layers it meets (`AnnotationEditing.beginErase`) and `edit.tool` stays what it
    /// was under it. A mode of this overlay and no `AnnotationTool`, so `EditorMemory` is never asked to keep it.
    private var erasing = false
    /// The radius of the eraser's circle, in points of the display: what a drag meets and what the cursor draws.
    static let eraserRadius: CGFloat = 9
    /// The ruler is on the picture, a switch of this overlay (`EditorAction.toggleRuler`) over whatever tool is chosen: not a layer, so
    /// no undo step and no export sees it, and nothing of it is remembered. It lives while the overlay does.
    private var ruler: Ruler?
    /// A press on the ruler's strip that is still down: the display, and whether the drag takes the strip along or turns it. A move keeps
    /// where the strip's centre was from the pointer; a turn keeps the angle the strip had and the direction the pointer pressed in.
    private var rulerDrag: (display: DisplayID, kind: RulerDrag)?
    private enum RulerDrag { case move(offset: CGPoint), turn(base: CGFloat, from: CGFloat) }
    /// A rotate gesture of the trackpad in progress: the angle the strip had when it began and how far the fingers have turned,
    /// clockwise; the strip's own angle sticks to 0°, 45° and 90° and so cannot be the sum.
    private var rulerTurn: (base: CGFloat, sum: CGFloat)?
    /// An area handle under the pointer: which one, the area as the press took it and where the
    /// press landed. Not an edit of the layers, so no undo step: the area is not a layer.
    private var reshaping: (display: DisplayID, handle: AreaHandle, base: CGRect, press: CGPoint)?
    /// Crop is on: the area as it stood when the mode began, the base area. A mode of this overlay, like the eraser, and no `AnnotationTool`. The
    /// area is reshaped live by its handles, as `reshaping` does, and Return takes what it has become, which is no undo step; Esc, Crop
    /// asked again, a tool, the eraser and Select put this one back. Nothing of it is remembered.
    private var crop: CGRect?
    /// The pointer on the display it is over, in that display's top-left points.
    private var pointer: (display: DisplayID, point: CGPoint)?
    private var hovered: FrozenWindow?
    /// What the next object is drawn with; picked on the palette, read from the store when
    /// the first area is released, and kept across the areas of one capture.
    private var style = AnnotationStyle.standard
    /// The tool whose own step and opacity `style` carries: the last one picked, and the pen before any.
    private var styleTool = AnnotationTool.pen
    /// What the store holds, kept beside it so that a tool's own step and opacity come back
    /// when the tool does, in a test with no store as well.
    private var memory = EditorMemory()
    /// Where the editor's last tool, colour, thickness and fill are kept. Nil in a test that
    /// remembers nothing.
    private let store: NamespacedStore?
    /// The pop-over that is open, one at a time: the thickness and opacity one, open only while a tool is chosen, or the
    /// colours one, and the centre of the cell that opened it, in the palette's own points. Closed by everything that
    /// puts the tool down, and by the exits.
    private var popover: (kind: PopoverKind, anchorX: CGFloat)?
    enum PopoverKind { case thickness, colours }
    /// Whether either pop-over is open: read by a test only. `thicknessIsOpen` and `coloursAreOpen` say which, and the
    /// overlay itself reads them to place, draw and close it.
    var popoverIsOpen: Bool { popover != nil }
    var thicknessIsOpen: Bool { popover?.kind == .thickness }
    /// The layers the editor holds now, in the list's order, for a test that holds the screen against the file made from them.
    var editedLayers: [Annotation] { edit?.layers.layers ?? [] }
    /// The area the editor holds now, a crop still pending included, for a test that reads it without leaving.
    var editedArea: CGRect? { edit?.rect }
    var coloursAreOpen: Bool { popover?.kind == .colours }
    /// The text being typed: the display whose field it is in and where the line starts, in that display's top-left
    /// points. The field itself is the view's (`OverlayView.textField`); this is the overlay's one record that an input
    /// is open; the ways out of it go through `endTyping`, and `close` drops the record itself. Nil when none is.
    private var typing: (display: DisplayID, at: CGPoint)?
    var isTyping: Bool { typing != nil }
    /// The emoji the Emoji tool places on the next click on the picture, picked in the grid; nil until one is. Nothing of it is remembered.
    private var emoji: String?
    /// What the emoji grid shows; its cells come back through `perform` as `.pickEmoji`.
    let emojiGrid = EmojiGridModel()
    /// What the palette shows; its cells come back through `perform`.
    let palette = EditorBarModel()
    /// The ⋯ menu: one object, filled again from `palette` at every opening.
    private lazy var moreMenu = EditorMenu.make(for: palette)
    /// The menu while `popUp` has not returned, so that `close` can end its tracking without making a menu never opened.
    private var openedMenu: NSMenu?

    /// What the overlay opened on, for a test that must know the capture panel's Area mode
    /// handed it the remembered selection and no other press did.
    var preselection: (display: DisplayID, rect: CGRect)? { preselected }

    /// What each view is drawing as its picture, for a test that must know it is
    /// the frame without the pointer: the live crosshair is drawn over it, and a
    /// pointer baked into it would be a second one.
    var drawnPictures: [DisplayID: CGImage] {
        panels.compactMapValues { $0.view.drawnPicture }
    }

    /// Whether another pin may open: asked at the ⋯ menu's Pin item (`.exit(.pin)`) and nowhere else, so the
    /// other exits leave at the limit as ever. The item is built only while `PinEntry.isOffered`.
    private let pinRoom: () -> Bool
    /// The Pin item was refused for want of room, and the plate says so until the next input. Every input sets it false, so
    /// it also takes away the plate of a finished reading (`textPlate`), which stands until the same next input.
    private var pinRefused = false { didSet { if !pinRefused { textPlate = nil } } }
    private let textTools: EditorTextTools
    /// A reading of the area's text that has not answered: what was asked of it, the task that waits, and the display and area it was
    /// asked for. One at a time. It ends with its answer, with the editor's close, and with any change of the area under it
    /// (`render`): its boxes were for the old area, so an answer for it is dropped. `serial` tells it from a later one.
    private var reading: (serial: Int, ask: TextAsk, task: Task<Void, Never>, display: DisplayID, rect: CGRect)?
    private var readingsBegun = 0
    private enum TextAsk { case copy, blur }
    /// What the last finished reading says, on the plate by the palette; until the next input. The plates' order, first that applies: the
    /// refused pin, the Esc question that is still asked, this. An answer that comes while the pin's refusal is up takes the refusal down (it is
    /// the later thing to say, and Pin can be pressed again); one that comes while the question is asked waits behind it.
    private var textPlate: String?
    /// A nudge let go of the selected object and the arrow key that did it is still down: its repeats
    /// move nothing. Any key or palette click that reaches `perform` while no drag or reshape is under way
    /// clears it, a fresh arrow press (not `isARepeat`) included, so a key-up the overlay never sees cannot
    /// leave the arrows dead; only a repeat can find it set. Mouse input, a modifier change, Esc and
    /// a right click do not go through `perform` and leave it as it was.
    private var arrowReleasedObject = false

    /// The capture panel's overlay: the person only picks here — a window under the pointer, or an area that stays as
    /// drawn until a new drag replaces it — and the panel's Capture (or Return) takes it. **The palette never appears and
    /// `startEditing` is never called**, so there is no editor and no layer, and an area leaves as a plain crop.
    let selectionOnly: Bool
    /// Whether there is something for Capture to take (`hasTarget`), told at every change; the panel shows its button by it.
    var targetChanged: (Bool) -> Void = { _ in }
    private var reportedTarget = false

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
        flashed = shot.rects
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

    // MARK: - Events, reported by the views

    func mouseMoved(on display: DisplayID, at local: CGPoint) {
        pointer = (display, local)
        if mode == .window { hovered = windowUnder(display: display, local: local) }
        if let entry = panels[display], !entry.panel.isKeyWindow {
            entry.panel.makeKey()
            entry.panel.makeFirstResponder(entry.view)
        }
        render()
    }

    func mouseDown(on display: DisplayID, at local: CGPoint, flags: NSEvent.ModifierFlags) {
        pointer = (display, local)
        pinRefused = false
        // No release is guaranteed: a press that finds a reshape open ends it where it was.
        reshaping = nil
        // A press on the palette is the palette's: never a draft, never a new area. Its background is an
        // input like any other, so it withdraws Esc's question as a button does; and the reshape it ended
        // never having been released, it judges the selection as that release would.
        if chrome(on: display)?.covers(local) == true || panels[display]?.view.emojiGridCovers(local) == true {
            if var current = edit, drag == nil { current.layers.disarm(); current.layers.releaseIfOutside(); edit = current; render() }
            return
        }
        // A press anywhere else ends an open input first, as a click out of a text box does, and then means what it means.
        endTyping()
        // An open pop-over is closed by a press outside the chrome, and that press is no other: it draws nothing and
        // moves nothing, so the person who opened the pop-over by mistake is not left with a stroke.
        if popover != nil {
            popover = nil
            if var current = edit { current.layers.disarm(); edit = current }
            render()
            return
        }
        if var current = edit, drag == nil {
            current.layers.disarm()
            // The editor reads the press on the edited display only: a handle of the area reshapes it, where the area offers
            // them (with no layers, or with Crop on; an object's own handle, where the two meet, is taken first), then, with the eraser on, the erase,
            // then the ruler's strip where the area shows it, and then a tool draws, a handle
            // resizes, an object is taken to be moved, and a click selects or lets go. What is
            // left is no tool and no layers, the old gesture, a new drag, which replaces the
            // area only when it turns out to be one; on another display, with a tool or with
            // layers, a press does nothing. The disarm is the click's own effect, kept either way.
            if display == current.display,
               let handle = AreaFrame.handle(of: current.rect, at: local, yieldingTo: current.layers.selected,
                                             layersExist: !current.layers.layers.isEmpty, cropping: crop != nil) {
                current.layers.end()
                reshaping = (display, handle, current.rect, local)
                edit = current
                render()
                return
            }
            // The eraser takes the press before any tool or selection does, even over a handle of the selected object: only
            // a handle of the area, above, is before it.
            if display == current.display, erasing {
                current.layers.beginErase(at: local, radius: Self.eraserRadius)
                edit = current
                render()
                return
            }
            // The ruler's strip takes the press with any tool, on the part of it the area shows: the strip is drawn above
            // the layers, so what is under it is not what the pointer is over. With the eraser on, above, the strip is not taken: the eraser takes layers and the ruler is none.
            if display == current.display, let strip = ruler, current.rect.contains(local), strip.contains(local) {
                current.layers.end()
                rulerDrag = (display, flags.contains(.option)
                             ? .turn(base: strip.angle, from: strip.degrees(toward: local))
                             : .move(offset: CGPoint(x: strip.center.x - local.x, y: strip.center.y - local.y)))
                edit = current
                render()
                return
            }
            // The text tool on bare picture inside the area starts a field there; on a layer or a handle the press is the
            // editor's own, and selects.
            if display == current.display, current.tool == .text, current.rect.contains(local), !current.layers.takes(at: local),
               panels[display]?.view.beginText(at: local, style: style, within: current.rect) == true {
                current.layers.deselect()
                typing = (display, local)
                edit = current
                render()
                return
            }
            // The Emoji tool on bare picture inside the area puts the picked emoji there, its middle at the press; with none picked the press only
            // lets go of the selection. On a layer or a handle the press is the editor's own, as the text tool's is.
            if display == current.display, current.tool == .emoji, current.rect.contains(local), !current.layers.takes(at: local) {
                if let emoji { current.layers.place(emoji: emoji, at: local, style: style) } else { current.layers.deselect() }
                edit = current
                render()
                return
            }
            if display == current.display,
               current.layers.press(at: local, tool: current.tool, style: style, ruler: ruler) {
                edit = current
                render()
                return
            }
            guard current.tool == nil, !erasing, current.layers.layers.isEmpty else { edit = current; render(); return }
            edit = current
        }
        switch mode {
        case .window:
            // The default is the shadow, as macOS's; an option-click asks for the window alone.
            if let hovered { finish(.window(hovered.id, shadow: !flags.contains(.option))) }
        case .area:
            guard picture == nil || picture?.display == display, let bounds = displayBounds(display) else { return }
            // The panel's overlay keeps the area that was drawn until a drag that is usable replaces it (`mouseUp`).
            replacedByDrag = selectionOnly ? (preselected ?? replacedByDrag) : nil
            preselected = nil
            drag = (display, SelectionDrag(start: local, bounds: bounds))
            render()
        }
    }

    func mouseDragged(on display: DisplayID, at local: CGPoint, flags: NSEvent.ModifierFlags) {
        pointer = (display, local)
        if let held = reshaping, var current = edit {
            // A result with nothing to draw is not taken: the area keeps the last one that had.
            if held.display == display, let bounds = displayBounds(display),
               let rect = AreaFrame.resized(held.base, held.handle, from: held.press, to: local, within: bounds) {
                current.rect = rect
                current.layers.reshape(bounds: rect)
                // While Crop is on the strip is kept inside at Return, so that Esc gives it back where it was.
                if crop == nil { ruler?.keep(within: rect) }
                edit = current
            }
            render()
            return
        }
        if let held = rulerDrag, held.display == display, var strip = ruler, let current = edit {
            switch held.kind {
            case .move(let offset): strip.move(to: CGPoint(x: local.x + offset.x, y: local.y + offset.y), within: current.rect)
            case .turn(let base, let from): strip.rotate(to: base + strip.degrees(toward: local) - from)
            }
            ruler = strip
            render()
            return
        }
        if var current = edit, drag == nil {
            current.layers.drag(to: local, shift: flags.contains(.shift))
            edit = current
            render()
            return
        }
        guard var current = drag, current.display == display else { return }
        current.drag.move(to: local, shift: flags.contains(.shift), option: flags.contains(.option),
                          space: spaceHeld)
        drag = current
        render()
    }

    /// A right click leaves. Esc is the documented way out and it depends on the
    /// panel being key; a full-screen overlay with no way out that needs no key
    /// is the one failure here that strands a person.
    func rightMouseDown() { escapeAsked() }

    /// Esc and the right click are one door with one rule, `AnnotationEditing.escape`, and it is asked last. Before it, in this order, each press does
    /// only its own thing and arms nothing: an open text input is ended, an open pop-over is closed, a held area handle puts the area back as the press
    /// took it, and with Crop on the area goes back as the mode found it (a selected object stays selected). Then the rule: at once with nothing to
    /// lose, and with layers a second press, whenever it comes; a selected object is let go of first, and that press asks nothing. A drag in
    /// progress is not an edit and leaves at once.
    private func escapeAsked() {
        pinRefused = false
        // An open input takes this press and nothing else: it places a non-empty text and drops an empty one, and the
        // rule below starts with the next press.
        if typing != nil { endTyping(); return }
        // An open pop-over takes this press and nothing else: Esc's own rule below starts with the next one.
        if popover != nil { popover = nil; render(); return }
        // A reshape under the pointer is cancelled, the area back as the press took it: Esc is the
        // way out of what is being done, and that press does only that.
        if let held = reshaping, var current = edit {
            reshaping = nil
            current.rect = held.base
            current.layers.reshape(bounds: held.base)
            edit = current
            render()
            return
        }
        // Crop on: the area goes back as the mode found it. That press does only that and does not arm the rule below, which
        // starts with the next press.
        if var current = edit, drag == nil, dropCrop(&current) {
            edit = current
            render()
            return
        }
        guard var current = edit, drag == nil else { finish(.cancelled); return }
        let outcome = current.layers.escape()
        edit = current
        switch outcome {
        case .close: finish(.cancelled)
        case .armed, .deselected, .dropped: render()
        }
    }

    /// The view for a display, so a test can send it a real event.
    func view(for display: DisplayID) -> OverlayView? { panels[display]?.view }

    func mouseUp(on display: DisplayID) {
        if reshaping != nil {
            // Judged at the release and not along the drag: a drag back brings the object in again, and Esc
            // gives the area back whole, so nothing is let go of that the person has not settled.
            reshaping = nil
            if var current = edit { current.layers.releaseIfOutside(); edit = current }
            render()
            return
        }
        if rulerDrag != nil { rulerDrag = nil; render(); return }
        if var current = edit, drag == nil {
            current.layers.end()
            edit = current
            render()
            return
        }
        guard let current = drag, current.display == display else { return }
        // A click that never moved is not a selection: the drag ends and the
        // overlay waits for a real one — or goes on editing the one it had.
        guard current.drag.isUsable else { drag = nil; preselected = replacedByDrag; replacedByDrag = nil; render(); return }
        replacedByDrag = nil
        if selectionOnly {
            drag = nil
            spaceHeld = false
            preselected = (display, current.drag.rect)
            render()
            return
        }
        startEditing(display: display, rect: current.drag.rect)
    }

    // MARK: - The panel's overlay

    /// What Capture would take now: the window last under the pointer, or the area as drawn (or remembered).
    var hasTarget: Bool { selectionOnly && (mode == .window ? hovered != nil : preselected != nil) }

    /// The panel's Capture and Return: the target leaves as the click or the exit of the editor would have sent it.
    /// False, and nothing sent, where there is none.
    @discardableResult func takeTarget() -> Bool {
        guard hasTarget else { return false }
        if mode == .window, let hovered {
            finish(.window(hovered.id, shadow: true))
        } else if let preselected {
            finish(.edited(display: preselected.display, local: preselected.rect, layers: [], exit: .confirm))
        }
        return true
    }

    /// The panel's mode cell was pressed on an overlay that is already open: the same frozen screen picks again, and what
    /// the other mode had chosen is dropped.
    func select(_ next: Mode) {
        guard selectionOnly, next != mode else { return }
        drag = nil
        replacedByDrag = nil
        hovered = nil
        preselected = nil
        mode = next
    }

    /// The released area becomes the editor's: a new area starts a fresh set of
    /// layers, and the tool picked so far stays picked.
    private func startEditing(display: DisplayID, rect: CGRect) {
        drag = nil
        preselected = nil
        spaceHeld = false
        // The first area of a capture opens on what was used last; the next ones keep what was picked since.
        var tool = edit?.tool
        if edit == nil, let store {
            memory = EditorMemory.read(store)
            palette.hide(Set(PaletteItem.allCases).subtracting(PaletteItems.visible(store)))
            tool = memory.tool
            styleTool = tool ?? styleTool
            style = memory.style(for: styleTool)
        }
        edit = (display, rect, AnnotationEditing(bounds: rect), tool)
        crop = nil
        // A strip on the picture goes with the area to the middle of the new one.
        if ruler != nil { ruler = .centred(in: rect) }
        rulerDrag = nil
        render()
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        optionHeld = flags.contains(.option)
        render()
        // Shift and option change the selection without the pointer moving, and ⇧
        // reshapes the stroke under the pointer the same way.
        if var current = edit, drag == nil {
            current.layers.modifiersChanged(shift: flags.contains(.shift))
            edit = current
            render()
            return
        }
        guard var current = drag, let pointer, pointer.display == current.display else { return }
        current.drag.move(to: pointer.point, shift: flags.contains(.shift),
                          option: flags.contains(.option), space: false)
        drag = current
        render()
    }

    func keyDown(_ event: NSEvent) {
        // A held Esc repeats, and a repeat is not the second press the question waits for.
        if event.keyCode == 53 { if !event.isARepeat { escapeAsked() }; return }
        // The field has the keys while a text is typed: a key it did not take (it hands on what it has no use for) is not the editor's.
        if typing != nil { return }
        if edit != nil, drag == nil { editorKey(event); return }
        switch event.keyCode {
        case 36, 76: // return, enter
            // A held Return repeats, and a repeat is not a press that asked for anything.
            guard !event.isARepeat else { return }
            if selectionOnly { takeTarget(); return }
            // The remembered selection stands for a selection made: Return takes it
            // into the editor, where the next Return takes the picture.
            if drag == nil, mode == .area, let preselected {
                startEditing(display: preselected.display, rect: preselected.rect)
                return
            }
            // Nothing selected: the whole display the pointer is on, as macOS does.
            guard drag == nil, let display = pointer?.display ?? freeze.frames.first?.id else { return }
            finish(.wholeDisplay(display))
        case 49: // space
            guard !event.isARepeat else { return }
            if drag != nil {
                spaceHeld = true
            } else if !selectionOnly {
                mode = mode == .area ? .window : .area
                if mode == .window, let pointer {
                    hovered = windowUnder(display: pointer.display, local: pointer.point)
                } else {
                    hovered = nil
                }
                render()
            }
        default:
            break
        }
    }

    /// A key while an area is being edited, read by its physical code: Space and
    /// every key the editor has no use for only withdraw a question asked by Esc and end a run of arrows.
    private func editorKey(_ event: NSEvent) {
        perform(EditorKeys.action(keyCode: event.keyCode, flags: event.modifierFlags), isRepeat: event.isARepeat)
    }

    /// The one door of the editor: a key and a click on the palette both come here, so a tool has
    /// one meaning however it was asked for. Nil is an input with no action, which only
    /// withdraws Esc's question and ends a run of arrows (`AnnotationEditing.disarm`).
    func perform(_ action: EditorAction?, isRepeat: Bool = false) {
        // An open input ends first, its text placed, so that the action meets the picture as it is; a colour, a step or
        // an opacity is the field's own pick and restyles it (below), and the text is placed in that style.
        switch action {
        case .color?, .thickness?, .opacity?: break
        default: endTyping()
        }
        guard var current = edit, drag == nil, reshaping == nil else { return }
        pinRefused = false
        if case .nudge? = action {
            // A repeat after the object was let go of is the held key going on, not a new input.
            if isRepeat && arrowReleasedObject { return }
        }
        arrowReleasedObject = false
        // An arrow press moves the selected object, or the area when none is selected, by pixels of
        // this display. It is not routed through the `disarm` below: that is what ends a run of
        // presses, and a run of arrows is one undo step. A held key repeats on purpose.
        if case .nudge(let dx, let dy, let pixels)? = action {
            guard !current.layers.isBusy, let frame = freeze.frames.first(where: { $0.id == current.display }) else { return }
            let delta = AreaFrame.step(CGPoint(x: dx, y: dy), pixels: pixels, scale: frame.scale)
            let hadSelection = current.layers.selected != nil
            if !current.layers.nudgeSelected(by: delta) {
                current.rect = AreaFrame.nudged(current.rect, by: delta, within: displayBounds(current.display) ?? current.rect)
                current.layers.reshape(bounds: current.rect)
                if crop == nil { ruler?.keep(within: current.rect) }
            } else if hadSelection, current.layers.selected == nil {
                arrowReleasedObject = true
            }
            edit = current
            render()
            return
        }
        // Close is Esc's own door and carries Esc's question with it: disarming first would ask again for ever.
        if action == .close { escapeAsked(); return }
        current.layers.disarm()
        defer {
            edit = current
            if let typing { panels[typing.display]?.view.restyleText(style) }
            render()
        }
        switch action {
        case .tool(let tool)?:
            // The same key again puts the tool down, which is how a drag selects again;
            // a held key's repeats are not that second press.
            guard !isRepeat else { return }
            dropCrop(&current)
            // Under the eraser a tool's key picks that tool, even the one chosen under it: the eraser is what puts down.
            current.tool = current.tool == tool && !erasing ? nil : tool
            erasing = false
            popover = nil
            if let store { EditorMemory.remember(tool: current.tool, in: store) }
            // Each tool is drawn with its own step and opacity, and every tool with the one colour and fill.
            if let picked = current.tool { styleTool = picked; style = memory.style(for: picked) }
        case .erase?:
            // The key again puts the eraser down, as a tool's does; the tool chosen under it is as it was, and the store is not asked.
            guard !isRepeat else { return }
            dropCrop(&current)
            erasing.toggle()
            popover = nil
        case .toggleRuler?:
            // A switch: the key again lowers it, and a click on the raised object does. The tool chosen and the eraser stay as they were.
            guard !isRepeat else { return }
            ruler = ruler == nil ? .centred(in: current.rect) : nil
            rulerDrag = nil
            rulerTurn = nil
            popover = nil
        case .crop?:
            // Crop is a mode: it puts the eraser and the chosen tool down (the store is not asked, so the next capture opens on the tool
            // it did), and the pop-over of a tool with them. Choosing it again is Esc's: the area back.
            guard !isRepeat else { return }
            if !dropCrop(&current) {
                crop = current.rect
                current.tool = nil
                erasing = false
                popover = nil
            }
        case .pickEmoji(let picked)?:
            if current.tool == .emoji, EmojiSet.isOne(picked) { emoji = picked }
        case .select?:
            dropCrop(&current)
            current.tool = nil
            erasing = false
            popover = nil
            if let store { EditorMemory.remember(tool: nil, in: store) }
        // A pick is the next object's and, with one selected, that object's too.
        case .color(let color)?:
            if coloursAreOpen { popover = nil }
            style.color = color
            current.layers.recolor(color)
            remember()
        case .thickness(let step)?:
            style.thickness = step
            // Q6, parked for the owner: with an object selected while the pop-over edits, a thickness pick also
            // re-weights that object, as it always has. Whether the pop-over should edit the next stroke only is
            // this one line; the opacity below already is the next stroke's alone.
            current.layers.setThickness(step)
            remember()
        case .opacity(let value)?:
            // A value that is no number is full ink, as the reader of the store reads it (`EditorMemory.read`).
            style.opacity = value.clamped(to: 0.1...1, whenNotANumber: 1)
            remember()
        case .thicknessAndOpacity(let anchorX)?:
            // A second request closes it; with no tool chosen, the spotlight, which has no steps, or the eraser on, there is nothing whose steps it could set.
            popover = current.tool != nil && current.tool != .spotlight && !erasing && !thicknessIsOpen ? (.thickness, anchorX) : nil
        case .colours(let anchorX)?:
            // Opened with no tool chosen too: the colour is every tool's. The other pop-over gives way to it.
            popover = coloursAreOpen ? nil : (.colours, anchorX)
        case .toggleFill?:
            // With a box selected the fill is flipped from that box's own state, and the pick follows it.
            if let box = current.layers.selected, box.tool == .rectangle || box.tool == .ellipse {
                style.filled = !box.style.filled
                current.layers.setFilled(style.filled)
            } else {
                style.filled.toggle()
            }
            remember()
        case .copyText?, .blurPersonalText?:
            // One reading at a time; the menu has both items disabled meanwhile, and a second ask that gets here anyway starts nothing.
            guard !isRepeat, reading == nil else { return }
            popover = nil
            beginReading(action == .copyText ? .copy : .blur, display: current.display, rect: current.rect)
        case .delete?: current.layers.deleteSelected()
        case .undo?: current.layers.undo()
        case .redo?: current.layers.redo()
        case .exit(.confirm)? where crop != nil:
            // Return (and Done, which sends the same) takes the crop and leaves the editor open on the new area: the strip is
            // brought inside it, and no step is recorded, as for any reshape of the area.
            guard !isRepeat else { return }
            crop = nil
            ruler?.keep(within: current.rect)
        case .exit(let how)?:
            guard !isRepeat else { return }
            popover = nil
            // No room for a pin: the editor stays, with the picture in it, a pending crop still pending, and says why on the plate
            // (the toast lies below the overlay and could not be seen).
            if how == .pin, !pinRoom() { pinRefused = true; return }
            // An exit that is no Return delivers the area as the screen shows it, a pending crop included.
            crop = nil
            // What the screen shows is what is delivered: a stroke still under the
            // pointer becomes a layer now, and an unusable one is dropped by `end`.
            current.layers.end()
            finish(.edited(display: current.display, local: current.rect, layers: current.layers.layers, exit: how))
        case .nudge?, .close?, nil: break
        }
    }

    /// Crop is put down with the area as the mode found it: true when it was on. Not a step, and the layers are told the bounds as a
    /// reshape tells them.
    @discardableResult
    private func dropCrop(_ current: inout (display: DisplayID, rect: CGRect, layers: AnnotationEditing, tool: AnnotationTool?)) -> Bool {
        guard let base = crop else { return false }
        crop = nil
        current.rect = base
        current.layers.reshape(bounds: base)
        return true
    }

    /// Whether Crop is on, for a test and for nobody else.
    var isCropping: Bool { crop != nil }

    /// Whether the eraser is on, for a test and for nobody else.
    var isErasing: Bool { erasing }

    /// The ruler on the picture, for a test and for nobody else.
    var rulerOnThePicture: Ruler? { ruler }

    /// A turn of the trackpad's rotate gesture, in degrees, counter-clockwise as AppKit reports it, while the ruler is on the picture. Whether the
    /// non-activating panel is sent the gesture at all is not known; the ⌥-drag turns the strip without it.
    func rotateRuler(by degrees: CGFloat, phase: NSEvent.Phase) {
        guard var strip = ruler, edit != nil else { return }
        if phase.contains(.ended) || phase.contains(.cancelled) { rulerTurn = nil; return }
        // A gesture whose end never came leaves its base and sum: a new one starts from the angle the strip has now.
        if phase.contains(.began) || phase.contains(.mayBegin) { rulerTurn = nil }
        let turn = rulerTurn ?? (strip.angle, 0)
        guard degrees.isFinite else { return }
        let sum = turn.sum - degrees
        rulerTurn = (turn.base, sum)
        strip.rotate(to: turn.base + sum)
        ruler = strip
        render()
    }

    /// A reading of the area as the screen shows it (a pending crop's area, the picture without the layers), held by this overlay: the task is
    /// cancelled by `close` and an answer that finds the editor closed, the area changed or another reading begun is dropped.
    private func beginReading(_ ask: TextAsk, display: DisplayID, rect: CGRect) {
        readingsBegun += 1
        let serial = readingsBegun
        let read = textTools.read
        let task = Task { [weak self] in
            let answer = await read(display, rect)
            self?.answered(answer, serial: serial)
        }
        reading = (serial, ask, task, display, rect)
        render()
    }

    private func answered(_ answer: CaptureSession.AreaReading, serial: Int) {
        guard let held = reading, held.serial == serial, !held.task.isCancelled, var current = edit,
              current.display == held.display, current.rect == held.rect else { return }
        reading = nil
        // The answer is the later thing to say: a refused pin's plate gives way to it.
        if case .cancelled = answer {} else { pinRefused = false }
        switch answer {
        case .cancelled: break
        case .failed: textPlate = ScStr.textUnreadable
        case .read(let lines, let source):
            switch held.ask {
            case .copy:
                switch textTools.copy(CopiedText.lines(lines, source: source, notUnder: current.layers.layers)) {
                case .copied: textPlate = ScStr.textCopied
                case .noText: textPlate = ScStr.noTextFound
                // The clipboard said no: the text was read and nobody has it, and the one sentence for a text that did not arrive is this.
                case .refused: textPlate = ScStr.textUnreadable
                }
            case .blur:
                let finds = PersonalFinds.finds(in: lines, source: source, under: current.layers.layers)
                let added = current.layers.insert(blurs: finds)
                edit = current
                textPlate = added == 0 ? ScStr.nothingBlurred : ScStr.blurred(added)
            }
        }
        render()
    }

    /// The input ends: the field goes, and its text is placed where the line began in the style picked now (`AnnotationEditing.place`:
    /// one undo step, and none for an empty or blank text). Return, Esc, a press elsewhere, a palette action but a colour, a step or an opacity, an exit and
    /// the panel losing key all come here; `close` drops the record without placing the text.
    func endTyping() {
        guard let held = typing else { return }
        typing = nil
        let text = panels[held.display]?.view.endText() ?? ""
        guard var current = edit else { return }
        current.layers.place(text: text, at: held.at, style: style)
        edit = current
        render()
    }

    /// What ⋯ asks for: the menu, under the ⋯ circle on the display whose palette is up. `popUp` returns only when the
    /// menu has closed, which the palette's pressed look counts on.
    private func openMoreMenu() {
        guard let view = panels.values.first(where: { $0.view.paletteIsShown })?.view else { return }
        openedMenu = moreMenu
        defer { openedMenu = nil }
        view.popUp(moreMenu, below: EditorPalette.moreCircleBottomLeft(palette.moreFrame))
    }

    func keyUp(_ event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    // MARK: - Reading and drawing

    private func windowUnder(display: DisplayID, local: CGPoint) -> FrozenWindow? {
        guard let frame = freeze.frames.first(where: { $0.id == display }) else { return nil }
        return WindowPick.window(at: ScreenSpace.global(CGRect(origin: local, size: .zero), in: frame.frame).origin,
                                 in: freeze.windows)
    }

    private func local(_ mouse: NSPoint, in panel: NSPanel, frame height: CGFloat) -> CGPoint {
        CGPoint(x: mouse.x - panel.frame.minX, y: height - (mouse.y - panel.frame.minY))
    }

    /// What an area on `display` stays inside: the display, or the picture the overlay was opened on.
    private func displayBounds(_ display: DisplayID) -> CGRect? {
        if let picture, picture.display == display { return picture.rect }
        return freeze.frames.first { $0.id == display }.map { CGRect(origin: .zero, size: $0.frame.size) }
    }

    /// Where the palette stands on `display`, under the area (under the base area while Crop is on): nil when it is not the edited one, and nil while an
    /// object is being drawn, moved or resized — a palette under the pointer would be drawn into — or
    /// the area is being reshaped or a new one dragged. It is back on the release, and on the
    /// Esc that drops a drawing or cancels a move, a resize or a reshape.
    func chrome(on display: DisplayID) -> EditorChrome? {
        guard let edit, drag == nil, reshaping == nil, !edit.layers.isBusy, edit.display == display,
              let view = panels[display]?.view else { return nil }
        let screen = view.frozen.frame.size
        // With Crop on the palette stands under the area as the mode found it, so it never covers the strip a handle is
        // dragged back into; after Return it stands under the new one.
        let area = crop ?? edit.rect
        let bare = EditorChrome.place(selection: area, in: screen, palette: view.paletteSize)
        guard let open = popover else { return bare }
        // The pop-over's cell is in the palette's own points; the palette does not move for it.
        return EditorChrome.place(selection: area, in: screen, palette: view.paletteSize,
                                  popover: open.kind == .colours ? view.coloursSize : view.popoverSize,
                                  anchorX: bare.palette.minX + open.anchorX)
    }

    /// `style` is the pick of `styleTool`: kept beside the store and written to it.
    private func remember() {
        memory.note(style: style, for: styleTool)
        if let store { EditorMemory.remember(style: style, for: styleTool, in: store) }
    }

    private func render() {
        // The area moved or was replaced under a reading: its boxes were for the old one.
        if let held = reading, edit?.display != held.display || edit?.rect != held.rect {
            held.task.cancel()
            reading = nil
        }
        if let edit {
            let held = edit.layers.selected
            emojiGrid.show(chosen: emoji)
            palette.show(tool: edit.tool, erasing: erasing, ruler: ruler != nil, cropping: crop != nil, style: held?.style ?? style, picked: style, selectedTool: held?.tool,
                      popoverOpen: thicknessIsOpen, coloursOpen: coloursAreOpen, canUndo: edit.layers.canUndo, canRedo: edit.layers.canRedo,
                      reading: reading != nil)
        }
        for (id, entry) in panels {
            var scene = OverlayScene()
            scene.windowMode = mode == .window
            scene.linesAcross = optionHeld
            if let pointer, pointer.display == id, edit == nil || drag != nil { scene.pointer = pointer.point }
            if let drag, drag.display == id {
                // A press that has not moved is not a new area yet: the area being edited is still the selection.
                let old = edit.flatMap { $0.display == id ? $0.rect : nil }
                scene.selection = drag.drag.hasMoved ? drag.drag.rect : old ?? drag.drag.rect
                scene.dimsWhenEmpty = drag.drag.hasMoved
            }
            else if let edit, edit.display == id {
                scene.selection = edit.rect
                scene.editing = drag == nil
                if let reshaping, reshaping.display == id, let pointer, pointer.display == id {
                    scene.loupeAt = pointer.point
                }
                scene.chrome = chrome(on: id)
                scene.layers = edit.layers.layers + (edit.layers.draft.map { [$0] } ?? [])
                scene.draftID = edit.layers.draft?.id
                scene.erasing = erasing
                scene.emojiGrid = edit.tool == .emoji && !erasing && crop == nil
                scene.handlesOffered = AreaFrame.offersHandles(layersExist: !edit.layers.layers.isEmpty, cropping: crop != nil)
                scene.ruler = ruler
                scene.fading = edit.layers.erased
                scene.selected = edit.layers.draft == nil ? edit.layers.selected : nil
                if pinRefused {
                    // By the palette, which the menu was opened from, so that the plate does not lie under the glass.
                    scene.plate = ScStr.pinLimit
                    scene.plateByActions = true
                } else if edit.layers.isArmed {
                    scene.plate = ScStr.confirmClose
                    if let pointer, pointer.display == id { scene.plateAt = pointer.point }
                } else if let textPlate {
                    scene.plate = textPlate
                    scene.plateByActions = true
                }
            } else if mode == .area, let preselected, preselected.display == id { scene.selection = preselected.rect }
            if mode == .window, let hovered { scene.highlight = windowPart(hovered, on: id) }
            entry.view.apply(scene)
        }
        if hasTarget != reportedTarget { reportedTarget = hasTarget; targetChanged(reportedTarget) }
    }

    /// The part of `window` that lies on `display`, in that display's top-left points; nil where it has none.
    private func windowPart(_ window: FrozenWindow, on display: DisplayID) -> CGRect? {
        guard let frame = freeze.frames.first(where: { $0.id == display }) else { return nil }
        let part = ScreenSpace.local(window.frame, in: frame.frame)
            .intersection(CGRect(origin: .zero, size: frame.frame.size))
        return !part.isNull && part.width > 0 && part.height > 0 ? part : nil
    }
}

/// Everything one panel draws, decided by the overlay.
struct OverlayScene {
    var windowMode = false
    var pointer: CGPoint?
    var selection: CGRect?
    var highlight: CGRect?
    /// The area is being edited: no lines across the screen; the size plate over the area's top-left corner all the
    /// while, Crop's included (`LabelLayer.cornerPlace`), and the loupe only while an area handle is held (`loupeAt`).
    var editing = false
    /// Layers over the selection, the one being drawn last.
    var layers: [Annotation] = []
    /// Which of `layers` is still being drawn, if one is.
    var draftID: Annotation.ID?
    /// The eraser is on: the cursor is its circle.
    var erasing = false
    /// The Emoji tool is chosen: its grid stands by the palette, where the palette is shown.
    var emojiGrid = false
    /// The area's handles are drawn: no layer on the picture, or Crop on (`AreaFrame.offersHandles`).
    var handlesOffered = true
    /// The layers the eraser's drag has met: drawn at `OverlayView.fadedOpacity` until the release takes them.
    var fading: Set<Annotation.ID> = []
    /// The ruler on the picture: drawn above the layers, clipped to the selection, and in no file.
    var ruler: Ruler?
    /// The selected layer, held by its handles; nil while one is being drawn.
    var selected: Annotation?
    /// Where the palette stands; nil is none on this display, or none while drawing, moving, resizing, reshaping or erasing.
    var chrome: EditorChrome?
    /// What Esc asked, while it is waiting for its second press.
    var plate: String?
    /// Where the pointer is while the plate is up, in display-top-left points; the
    /// crosshair stays off while editing, so this is not `pointer`.
    var plateAt: CGPoint?
    /// The plate is the Pin refusal: it stands over the palette, or under it with no room above (`plateByActions`).
    var plateByActions = false
    /// The area is being reshaped and the pointer is here, in display-top-left points: the loupe reads the pixel under it.
    var loupeAt: CGPoint?
    /// ⌥ is held: the lines run across the screen through the pointer.
    var linesAcross = false
    /// The selection is dimmed around even with no width and no height: a drag that has moved and come back to its press.
    var dimsWhenEmpty = false
}

// MARK: - The panel

/// The capture overlay's panel: borderless, non-activating, at the screen-saver level.
///
/// What was measured of a menu and tooltips over it (2026-10-02/03, Helm inactive, real keyboard): an `NSMenu`
/// popped up from the editor's bar (the two bars, before 43704363, which replaced them with the palette) works: an item click and a submenu item click both land, and the
/// checkmark is drawn. With the menu closed, `EditorKeys` selects tools by key code, in the US and the Russian layout alike (the two measured);
/// with it open, a `keyEquivalent` "a" fired in the US layout and not in the Russian one. Tooltips (`.help`) were not
/// shown on the cells of those two bars, and the overlay forces the crosshair on every move (its cursor sets climbed by hundreds per
/// open). Not yet measured: whether that forced crosshair is what hides the tooltips, and whether a menu
/// item's SF Symbol image is drawn on its own (it was not, beside `state = .on`). The palette is hosted by `EditorBarHostingView`.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Above the menu bar and the Dock, over full-screen apps, in every Space.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Called when this panel stops being key: the pointer went to another display, whose panel the overlay makes key.
    var onResignKey: (() -> Void)?
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

// MARK: - The view

/// One display's frozen frame, and the selection drawn over it.
///
/// Layers and not `draw(_:)`: the pointer moves many times a frame and a 5K
/// panel redrawn in full for each is the cost this avoids. The view is **not**
/// flipped — a flipped layer-backed view turns an image layer upside down — so
/// it converts to the engine's top-left points at the edge, in `local(_:)` and
/// `layerRect(_:)`, and nowhere else.
final class OverlayView: NSView {
    let frozen: FrozenDisplay
    private weak var overlay: CaptureOverlay?

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    /// The spotlights' one dim (`Spotlights`): under every annotation's layer and over the picture, a layer of its own and
    /// not one per spotlight, so the dim does not add up where two spotlights meet.
    private let spotlightLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    /// The selected object's box and handles: over the dim, since a handle on the selection's
    /// edge is half outside its hole. The box is a layer of its own with no fill: one path holding the
    /// box and the handles under a white fill painted the box white, over the very object it frames.
    private let frameLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    /// The area's own handles, eight or four on a small area (`AreaFrame.offered`): round and white on a dark edge, where an object's are squares
    /// on the accent colour, so the two are not taken for each other.
    private let areaHandleLayer = CAShapeLayer()
    private let crosshairLayer = CAShapeLayer()
    /// The ruler, over the layers and the dim's hole and under the palette's host, which is a subview.
    let rulerLayer = RulerLayer()
    /// The lines' dark edge, under them and a half point wider each side, so they read on a white page as on a black one.
    private let crosshairEdgeLayer = CAShapeLayer()
    private let coordinateLabel = LabelLayer()
    private let sizeLabel = LabelLayer()
    /// The area's size over its top-left corner while it is edited: a plate of its own, since `sizeLabel` is the
    /// one by the pointer that the Esc question uses; the Pin refusal stands over the palette.
    private let cornerLabel = LabelLayer()
    private let loupeLayer = LoupeLayer()
    private let flashLayer = FlashLayer()
    /// The editor's palette, made when this display first has an area to edit and never
    /// on another: a display with nothing selected builds no SwiftUI at all.
    private lazy var paletteHost = EditorBarHostingView(rootView: EditorPalette(model: overlay!.palette))
    private var paletteMade = false
    private lazy var measuredPalette: CGSize = {
        paletteMade = true
        addSubview(paletteHost)
        paletteHost.isHidden = true
        return paletteHost.fittingSize
    }()

    /// What the palette measures in the language the overlay opened in; measured once, since the
    /// language cannot change under a capture that is up.
    var paletteSize: CGSize { measuredPalette }

    /// The thickness and opacity pop-over's host, made and hidden at the first need. Its card is given the height measured below, so
    /// that the reveal has a number to grow to before any layout has run.
    private lazy var popoverHost: EditorBarHostingView<EditorPopover> = {
        popoverMade = true
        let host = EditorBarHostingView(rootView: EditorPopover(model: overlay!.palette, height: popoverSize.height))
        host.isHidden = true
        addSubview(host)
        return host
    }()
    private var popoverMade = false
    /// The thickness and opacity pop-over's card laid out whole, measured once like the palette.
    private lazy var measuredPopover = NSHostingView(rootView: EditorPopover(model: overlay!.palette, height: nil)).fittingSize
    var popoverSize: CGSize { measuredPopover }

    /// The colours pop-over's host and size, made and measured the same way, at the first need.
    private lazy var coloursHost: EditorBarHostingView<EditorColoursPopover> = {
        coloursMade = true
        let host = EditorBarHostingView(rootView: EditorColoursPopover(model: overlay!.palette, height: coloursSize.height))
        host.isHidden = true
        addSubview(host)
        return host
    }()
    private var coloursMade = false
    private lazy var measuredColours = NSHostingView(rootView: EditorColoursPopover(model: overlay!.palette)).fittingSize
    var coloursSize: CGSize { measuredColours }

    /// The emoji grid's host and size, made and measured the same way, at the first need.
    private lazy var emojiHost: EditorBarHostingView<EmojiGrid> = {
        emojiMade = true
        let host = EditorBarHostingView(rootView: EmojiGrid(model: overlay!.emojiGrid))
        host.isHidden = true
        addSubview(host)
        return host
    }()
    private var emojiMade = false
    private lazy var measuredEmoji = NSHostingView(rootView: EmojiGrid(model: overlay!.emojiGrid)).fittingSize
    /// Where the grid stands in this display's top-left points while it is shown.
    private var emojiFrame: CGRect?

    /// Whether the grid is shown over `local`, a display-local point: a press there is the grid's.
    func emojiGridCovers(_ local: CGPoint) -> Bool { emojiFrame?.contains(local) == true }

    /// The grid above the palette, `EditorChrome.popoverGap` from it, centred on it and held on the screen; below the palette where a pop-over
    /// (thickness or colours) is above the palette or there is no room above. Hidden where there is no palette or the Emoji tool is not chosen.
    private func placeEmojiGrid(_ scene: OverlayScene) {
        guard scene.emojiGrid, let chrome = scene.chrome else {
            emojiFrame = nil
            if emojiMade { emojiHost.isHidden = true }
            return
        }
        let size = measuredEmoji, palette = chrome.palette, margin = EditorChrome.margin
        let above = palette.minY - EditorChrome.popoverGap - size.height
        let popoverIsAbove = chrome.popover.map { $0.minY < palette.minY } ?? false
        let y = !popoverIsAbove && above >= margin ? above : palette.maxY + EditorChrome.popoverGap
        let x = min(max(palette.midX - size.width / 2, margin), max(margin, bounds.width - size.width - margin))
        let frame = CGRect(x: x, y: min(max(y, margin), max(margin, bounds.height - size.height - margin)), width: size.width, height: size.height)
        emojiFrame = frame
        emojiHost.frame = layerRect(frame)
        emojiHost.isHidden = false
    }

    /// Pops `menu` up under the ⋯ circle, its left edge at the circle's, so that the circle and its badge stay in
    /// view; where there is no room below, AppKit flips it. The circle's place is the palette's own reading,
    /// converted from the host's top-left points to this view's. The menu's window rises `menuLift` above the
    /// point it is given (4.5 pt measured in-process on a real popUp: window top 512.0 with the ring's bottom at
    /// 511.5 at a lift of 4); where the body sits inside its window has no public reader. The point therefore lies
    /// that far plus the badge's reach below the circle.
    func popUp(_ menu: NSMenu, below circle: CGPoint) {
        let menuLift: CGFloat = 4.5
        let at = paletteHost.convert(CGPoint(x: circle.x, y: circle.y + EditorPalette.moreBadgeReach + menuLift), to: self)
        menu.popUp(positioning: nil, at: at, in: self)
    }

    /// Whether the palette is on screen; `openMoreMenu` asks it, and so do the tests.
    var paletteIsShown: Bool { paletteMade && !paletteHost.isHidden }
    /// The view a click at a display-local point would reach, for a test that asks whether it is the palette.
    func clickTarget(at local: CGPoint) -> NSView? { hitTest(CGPoint(x: local.x, y: bounds.height - local.y)) }
    /// Whether a view is the palette or inside it.
    func isPalette(_ view: NSView?) -> Bool {
        guard paletteMade, let view else { return false }
        return view.isDescendant(of: paletteHost)
    }

    var drawnPicture: CGImage? {
        guard let contents = imageLayer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID
        else { return nil }
        return (contents as! CGImage)
    }

    init(frozen: FrozenDisplay, overlay: CaptureOverlay) {
        self.frozen = frozen
        self.overlay = overlay
        super.init(frame: CGRect(origin: .zero, size: frozen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageLayer.contents = frozen.image
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = frozen.scale

        dimLayer.fillRule = .evenOdd
        spotlightLayer.fillRule = .evenOdd
        spotlightLayer.fillColor = Spotlights.color
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor

        // The window under the pointer is only filled, 28 % of the accent, and has no outline.
        highlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        highlightLayer.strokeColor = nil

        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = NSColor.white.cgColor
        selectionLayer.lineWidth = 1

        frameLayer.fillColor = nil
        frameLayer.strokeColor = NSColor.controlAccentColor.cgColor
        frameLayer.lineWidth = 1.5

        handleLayer.fillColor = NSColor.white.cgColor
        handleLayer.strokeColor = NSColor.controlAccentColor.cgColor
        handleLayer.lineWidth = 1.5

        areaHandleLayer.fillColor = NSColor.white.cgColor
        areaHandleLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        areaHandleLayer.lineWidth = 1

        crosshairLayer.fillColor = nil
        crosshairLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        crosshairLayer.lineWidth = 1
        crosshairEdgeLayer.fillColor = nil
        crosshairEdgeLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        crosshairEdgeLayer.lineWidth = 2

        rulerLayer.isHidden = true
        for sublayer in [imageLayer, spotlightLayer, dimLayer, highlightLayer, selectionLayer, frameLayer, areaHandleLayer, handleLayer, rulerLayer,
                         crosshairEdgeLayer, crosshairLayer, flashLayer,
                         coordinateLabel, sizeLabel, cornerLabel, loupeLayer] as [CALayer] {
            layer?.addSublayer(sublayer)
        }
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        spotlightLayer.frame = bounds
        flashLayer.frame = bounds
        for label in [coordinateLabel, sizeLabel, cornerLabel] { label.isHidden = true }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: The text field

    /// The field of the text being typed, one at a time; nil when no input is open.
    private(set) var textField: OverlayTextField?

    /// Puts a field at `point` (display-local, top-left) in `style` and makes it the first responder; false when AppKit
    /// refuses the responder, and then no field is left.
    func beginText(at point: CGPoint, style: AnnotationStyle, within area: CGRect) -> Bool {
        textField?.removeFromSuperview()
        let field = OverlayTextField()
        field.onEnd = { [weak overlay] in overlay?.endTyping() }
        field.restyle(style)
        field.clip = layerRect(area)
        field.start(at: CGPoint(x: point.x, y: bounds.height - point.y))
        addSubview(field)
        guard window?.makeFirstResponder(field) == true else {
            field.removeFromSuperview()
            return false
        }
        textField = field
        return true
    }

    func restyleText(_ style: AnnotationStyle) { textField?.restyle(style) }

    /// The field goes and the keys are the editor's again; what was typed is returned.
    func endText() -> String {
        guard let field = textField else { return "" }
        textField = nil
        let text = field.string
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        return text
    }

    // MARK: Space

    /// A point of this view in the engine's display-local points: top-left origin.
    private func local(_ point: NSPoint) -> CGPoint { CGPoint(x: point.x, y: bounds.height - point.y) }

    /// A display-local rectangle as a rectangle of this view's layers.
    private func layerRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Events

    /// The overlay while it takes input: nil during the flash that closes it, when every event is dropped.
    private var live: CaptureOverlay? { overlay?.leaving == true ? nil : overlay }

    override func mouseMoved(with event: NSEvent) {
        setCursor()
        live?.mouseMoved(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)))
    }
    override func mouseEntered(with event: NSEvent) { setCursor() }
    override func cursorUpdate(with event: NSEvent) { setCursor() }

    override func mouseDown(with event: NSEvent) {
        live?.mouseDown(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)),
                           flags: event.modifierFlags)
    }
    override func mouseDragged(with event: NSEvent) {
        live?.mouseDragged(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)),
                              flags: event.modifierFlags)
    }
    override func mouseUp(with event: NSEvent) { live?.mouseUp(on: frozen.id) }
    /// The trackpad's rotate gesture: forwarded to `rotateRuler`, which turns the ruler when one is on the picture. Whether the
    /// non-activating panel is sent the gesture was not tried.
    override func rotate(with event: NSEvent) { live?.rotateRuler(by: CGFloat(event.rotation), phase: event.phase) }
    override func rightMouseDown(with event: NSEvent) { live?.rightMouseDown() }
    override func flagsChanged(with event: NSEvent) { live?.flagsChanged(event.modifierFlags) }
    override func keyDown(with event: NSEvent) { live?.keyDown(event) }
    override func keyUp(with event: NSEvent) { live?.keyUp(event) }

    /// Set on every move as well as in `cursorUpdate`: Helm is not the active
    /// application, and the system is free to put the arrow back under a
    /// non-activating panel between one update and the next.
    private var windowMode = false
    /// The eraser is on (`OverlayScene.erasing`): the cursor is its circle.
    private var erasing = false
    private func setCursor() {
        (windowMode ? Self.cameraCursor : erasing ? Self.eraserCursor : NSCursor.crosshair).set()
    }

    /// The opacity of a layer the eraser's drag has met, until the release takes it.
    static let fadedOpacity: Float = 0.3

    /// A circle of the eraser's radius, a white fill at 55 % and a 1 pt black edge at 55 %, the hot spot at its centre.
    static let eraserCursor: NSCursor = {
        let radius = CaptureOverlay.eraserRadius
        let size = NSSize(width: radius * 2 + 2, height: radius * 2 + 2)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor.white.withAlphaComponent(0.55).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    private static let cameraCursor: NSCursor = {
        let size = NSSize(width: 28, height: 24)
        let base = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let base else { return false }
            let glyph = NSRect(x: (rect.width - base.size.width) / 2, y: (rect.height - base.size.height) / 2,
                               width: base.size.width, height: base.size.height)
            // White halo, then black: legible over a dark window and a light one.
            for offset in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] {
                base.withSymbolConfiguration(.init(paletteColors: [.white]))?
                    .draw(in: glyph.offsetBy(dx: offset.0, dy: offset.1))
            }
            base.withSymbolConfiguration(.init(paletteColors: [.black]))?.draw(in: glyph)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    // MARK: Drawing

    func apply(_ scene: OverlayScene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        windowMode = scene.windowMode
        if erasing != scene.erasing {
            erasing = scene.erasing
            setCursor()
        }
        // The dim goes on with the first point a drag has moved over and stays until the shot or Esc, so a selection with
        // any size dims, and an empty one only when its drag has moved (`dimsWhenEmpty`); never over a window pick.
        if let selection = scene.selection, !scene.windowMode,
           selection.width > 0 || selection.height > 0 || scene.dimsWhenEmpty {
            let dim = CGMutablePath()
            dim.addRect(bounds)
            dim.addRect(layerRect(selection))
            dimLayer.path = dim
        } else {
            dimLayer.path = nil
        }

        highlightLayer.path = scene.highlight.map { WindowShape.path(for: layerRect($0)) }
        selectionLayer.path = scene.selection.map { CGPath(rect: layerRect($0), transform: nil) }

        drawLayers(scene)
        rulerLayer.frame = bounds
        rulerLayer.show(scene.editing ? scene.ruler : nil, in: scene.selection ?? .zero, height: bounds.height, scale: frozen.scale)
        drawAreaHandles(scene.editing && scene.handlesOffered ? scene.selection : nil)
        if let chrome = scene.chrome {
            _ = measuredPalette
            paletteHost.frame = layerRect(chrome.palette)
            paletteHost.isHidden = false
            let colours = overlay?.coloursAreOpen == true
            if let popover = chrome.popover {
                let host: NSView = colours ? coloursHost : popoverHost
                host.frame = layerRect(popover)
                host.isHidden = false
                if colours, popoverMade { popoverHost.isHidden = true }
                if !colours, coloursMade { coloursHost.isHidden = true }
            } else {
                if popoverMade { popoverHost.isHidden = true }
                if coloursMade { coloursHost.isHidden = true }
            }
        } else if paletteMade {
            paletteHost.isHidden = true
            if popoverMade { popoverHost.isHidden = true }
            if coloursMade { coloursHost.isHidden = true }
        }

        // The loupe, only while a handle is held: the pixels of the frame without the pointer, round the pointer.
        if let held = scene.loupeAt, let reading = PixelLoupe.around(held, in: frozen) {
            loupeLayer.show(reading, at: CGPoint(x: held.x, y: bounds.height - held.y), within: bounds)
        } else {
            loupeLayer.isHidden = true
        }
        placeEmojiGrid(scene)

        let at = scene.pointer.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        if let at, !scene.windowMode, scene.linesAcross {
            let lines = CGMutablePath()
            lines.move(to: CGPoint(x: 0, y: at.y)); lines.addLine(to: CGPoint(x: bounds.width, y: at.y))
            lines.move(to: CGPoint(x: at.x, y: 0)); lines.addLine(to: CGPoint(x: at.x, y: bounds.height))
            crosshairLayer.path = lines
            crosshairEdgeLayer.path = lines
        } else {
            crosshairLayer.path = nil
            crosshairEdgeLayer.path = nil
        }

        // **One plate by the pointer while selecting.** Before a drag it says where the pointer
        // is; while one is open it says how large the selection is, in the same
        // place — the size *replaces* the coordinates, as macOS's own ⌘⇧4 does.
        // Two plates at the pointer's offset lay one over the other. Once the area is edited the plate
        // stands over its corner instead.
        if !scene.editing { cornerLabel.isHidden = true }
        if scene.editing {
            // Editing has no lines across the screen and no plate by the pointer but the Esc question and, while a
            // handle is held, the loupe's; the area's size stands over its top-left corner, at the place
            // `cornerPlace` picks, with Crop on as with it off.
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
            if let selection = scene.selection {
                let pixels = Selection.pixelSize(of: selection, scale: frozen.scale)
                let text = "\(pixels.width) × \(pixels.height)"
                let at = LabelLayer.cornerPlace(of: LabelLayer.size(of: text), over: selection, within: bounds,
                                                clearOf: scene.chrome.map { [$0.palette] } ?? [])
                cornerLabel.show(text, near: CGPoint(x: at.x, y: bounds.height - at.y - LabelLayer.size(of: text).height),
                                 within: bounds)
            } else {
                cornerLabel.isHidden = true
            }
            if let plate = scene.plate, let selection = scene.selection {
                let box = layerRect(selection)
                // The pointer's offset, as the other plates; the selection's corner
                // is the fallback for a scene with no pointer.
                if scene.plateByActions, let palette = scene.chrome.map({ layerRect($0.palette) }) {
                    let height = LabelLayer.size(of: plate).height
                    let above = palette.maxY + HelmSpace.s2
                    let y = above + height + 4 <= bounds.maxY ? above : palette.minY - HelmSpace.s2 - height
                    sizeLabel.show(plate, near: CGPoint(x: palette.minX, y: y), within: bounds)
                } else {
                    let anchor = scene.plateAt.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
                        ?? CGPoint(x: box.maxX, y: box.minY + 26)
                    sizeLabel.show(plate, near: CGPoint(x: anchor.x + 14, y: anchor.y - 26), within: bounds)
                }
            }
        } else if let selection = scene.selection {
            let pixels = Selection.pixelSize(of: selection, scale: frozen.scale)
            let box = layerRect(selection)
            // The pointer is where the eye is; the corner is the fallback for a
            // scene that has a selection and no pointer.
            let anchor = at ?? CGPoint(x: box.maxX, y: box.minY + 26)
            sizeLabel.show("\(pixels.width) × \(pixels.height)",
                           near: CGPoint(x: anchor.x + 14, y: anchor.y - 26), within: bounds)
            coordinateLabel.isHidden = true
        } else if let pointer = scene.pointer, let at, !scene.windowMode {
            coordinateLabel.show("\(Int(pointer.x.rounded())), \(Int(pointer.y.rounded()))",
                                 near: CGPoint(x: at.x + 14, y: at.y - 26), within: bounds)
            sizeLabel.isHidden = true
        } else {
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
        }
    }

    /// One shape layer per annotation, each a **direct child of the view's layer**, between the picture
    /// and the dim, in the annotations' own order. Not inside a clipping parent: a layer's
    /// `compositingFilter` blends with what is beneath it in the same parent only, so a marker nested in
    /// a clip came out olive over black text where the export multiplies to black. The selection is the
    /// clip all the same, by geometry — the outline of the stroke, intersected with the selection's
    /// rectangle, filled — and the dim's hole is what leaves it undimmed.
    ///
    /// **A layer is built once and kept while its annotation is equal to the one it was built from.**
    /// Stroking and intersecting an `Annotation.maxPoints` path is expected to cost milliseconds (an estimate, not a
    /// measurement) and the scene is applied on every pointer event, so only what changed is rebuilt: the draft, the object being moved or resized, the
    /// one recoloured. The cache is by `Annotation.id` and is dropped with the selection's rectangle.
    private func drawLayers(_ scene: OverlayScene) {
        guard scene.editing, let selection = scene.selection else {
            for shape in drawnShapes { shape.removeFromSuperlayer() }
            drawnShapes = []
            shapeCache = [:]
            draftGrain = nil
            spotlightLayer.path = nil
            drawHandles(nil)
            return
        }
        let box = layerRect(selection)
        if cachedBox != box {
            for entry in shapeCache.values { entry.shape.removeFromSuperlayer() }
            shapeCache = [:]
            cachedBox = box
        }
        // The spotlights are one layer, laid here and not by `makeShape`: a layer of each would dim twice where two meet.
        var turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        spotlightLayer.path = Spotlights.dim(of: scene.layers, within: selection)?.copy(using: &turn)
        var kept: [Annotation.ID: (annotation: Annotation, shape: CALayer, draft: Bool, number: Int?)] = [:]
        for (annotation, number) in zip(scene.layers, AnnotationStep.numbers(in: scene.layers)) where annotation.tool != .spotlight {
            let draft = annotation.id == scene.draftID
            // A step's picture holds its number, which another step's removal changes without touching the layer.
            if let entry = shapeCache[annotation.id], entry.annotation == annotation, entry.number == number {
                // The draft's grain covers the display; once it is released it is cut to the stroke's own box.
                if entry.draft && !draft && annotation.tool.isGrainy { entry.shape.mask = grainMask(annotation, draft: false) }
                kept[annotation.id] = (entry.annotation, entry.shape, draft, number)
            } else {
                shapeCache[annotation.id]?.shape.removeFromSuperlayer()
                kept[annotation.id] = (annotation, makeShape(annotation, number: number, clippedTo: box, draft: draft), draft, number)
            }
        }
        for (id, entry) in shapeCache where kept[id]?.shape !== entry.shape { entry.shape.removeFromSuperlayer() }
        shapeCache = kept
        for annotation in scene.layers {
            kept[annotation.id]?.shape.opacity = scene.fading.contains(annotation.id) ? Self.fadedOpacity : 1
        }
        // The draft's whole-display grain lives as long as the draft: a release has just cut it, a drop (Esc, right
        // click) leaves no draft among the layers, and either event ends here.
        if !kept.values.contains(where: \.draft) { draftGrain = nil }
        let ordered = scene.layers.compactMap { kept[$0.id]?.shape }
        // Re-inserting each below the dim in turn is what puts the sequence in order.
        if ordered.count != drawnShapes.count || !zip(ordered, drawnShapes).allSatisfy({ $0 === $1 }) {
            for shape in ordered { layer?.insertSublayer(shape, below: dimLayer) }
        }
        drawnShapes = ordered
        drawHandles(scene.selected)
    }

    /// The blur's layer: the export's own mosaic (`Pixelate.tile` over the same picture the file is cut from) as the
    /// layer's contents, one image pixel to a screen pixel, the selection's rectangle its mask. A layer of its own
    /// and not a path: the mosaic has no outline to fill.
    private func makeMosaic(_ annotation: Annotation, clippedTo box: CGRect) -> CALayer {
        makeTiled(Pixelate.tile(of: frozen.shot, rect: annotation.frame, blockPoints: annotation.blockPoints, scale: frozen.scale),
                  clippedTo: box)
    }

    /// A picture of whole display pixels as a layer, one image pixel to a screen pixel, the selection's rectangle its mask:
    /// the mosaic of a blur, and a text's line (`AnnotationText.tile`, the export's own `draw` into a bitmap).
    private func makeTiled(_ tile: Pixelate.Tile?, clippedTo box: CGRect) -> CALayer {
        let layer = CALayer()
        guard let tile else { return layer }
        let scale = frozen.scale
        layer.frame = CGRect(x: tile.pixels.minX / scale, y: bounds.height - tile.pixels.maxY / scale,
                             width: tile.pixels.width / scale, height: tile.pixels.height / scale)
        layer.contents = tile.image
        layer.contentsScale = scale
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        mask.frame = box.offsetBy(dx: -layer.frame.minX, dy: -layer.frame.minY)
        layer.mask = mask
        return layer
    }

    private func makeShape(_ annotation: Annotation, number: Int?, clippedTo box: CGRect, draft: Bool) -> CALayer {
        shapeBuilds += 1
        if annotation.tool == .blur { return makeMosaic(annotation, clippedTo: box) }
        if annotation.tool == .text || annotation.tool == .emoji { return makeTiled(AnnotationText.tile(of: annotation, scale: frozen.scale), clippedTo: box) }
        if annotation.tool == .magnifier {
            return makeTiled(Magnifier.tile(of: annotation, over: frozen.shot, scale: frozen.scale), clippedTo: box)
        }
        if let number { return makeTiled(AnnotationStep.tile(of: annotation, number: number, scale: frozen.scale), clippedTo: box) }
        let clip = CGPath(rect: box, transform: nil)
        var turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        let shape = CAShapeLayer()
        shape.contentsScale = frozen.scale
        shape.frame = bounds
        let path = annotation.outline.copy(using: &turn)
        if let stroke = annotation.stroke, let path {
            let line = path.copy(strokingWithWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join,
                                 miterLimit: 10)
            shape.path = line.intersection(clip)
            shape.fillColor = stroke.color
            // The export's `.multiply` blend; a layer composites with the picture
            // beneath it by this filter name.
            if stroke.multiplies { shape.compositingFilter = "multiplyBlendMode" }
            shape.mask = grainMask(annotation, draft: draft)
        } else {
            shape.path = path?.intersection(clip)
            shape.fillColor = annotation.fillColor
        }
        shape.strokeColor = nil
        return shape
    }

    /// The pencil's grain, the file's one: the same function over the display's own pixels, laid on the layer at one
    /// pixel to a pixel. A finished stroke's is cut to its own box. A draft's covers the display and is kept for as
    /// long as its anchor stands, since the grain does not follow the path and the shape's path clips it: a drag
    /// pays the build once and not per pointer event.
    /// Nil for every tool but the pencil: `AnnotationTool.isGrainy` decides it, here and in the export, so no caller can give the Pen or the Marker a grain.
    private func grainMask(_ annotation: Annotation, draft: Bool) -> CALayer? {
        guard annotation.tool.isGrainy, let stroke = annotation.stroke else { return nil }
        let display = CGRect(x: 0, y: 0, width: bounds.width * frozen.scale, height: bounds.height * frozen.scale)
        let pixels: CGRect, alpha: CGImage
        if draft, let anchor = annotation.points.first {
            let key = DraftGrain(anchor: anchor, scale: frozen.scale, size: display.size)
            if draftGrain?.key != key {
                draftGrain = PencilGrain.mask(anchoredAt: anchor, scale: frozen.scale, pixels: display)
                    .flatMap { grain in grain.alpha.map { (key, grain, $0) } }
            }
            guard let kept = draftGrain else { return nil }
            (pixels, alpha) = (kept.mask.pixels, kept.alpha)
        } else {
            // Released: the draft's own grain, cut to the stroke's box, and no longer kept whole.
            let box = PencilGrain.box(for: annotation.points, width: stroke.width, scale: frozen.scale, pixels: display)
            let grain = box.flatMap { draftGrain?.mask.cut(to: $0) }
                ?? PencilGrain.mask(for: annotation.points, width: stroke.width, scale: frozen.scale, pixels: display)
            draftGrain = nil
            guard let grain, let cut = grain.alpha else { return nil }
            (pixels, alpha) = (grain.pixels, cut)
        }
        let mask = CALayer()
        mask.contents = alpha
        mask.contentsScale = frozen.scale
        mask.magnificationFilter = .nearest
        mask.frame = CGRect(x: pixels.minX / frozen.scale, y: bounds.height - pixels.maxY / frozen.scale,
                            width: pixels.width / frozen.scale, height: pixels.height / frozen.scale)
        return mask
    }

    private struct DraftGrain: Equatable { let anchor: CGPoint, scale: CGFloat, size: CGSize }
    private var draftGrain: (key: DraftGrain, mask: PencilGrain.Mask, alpha: CGImage)?

    /// The box round the selected object and a square at each of its handles; none for none.
    private func drawHandles(_ annotation: Annotation?) {
        guard let annotation else {
            frameLayer.path = nil
            handleLayer.path = nil
            drawnHandles = []
            return
        }
        let path = CGMutablePath()
        frameLayer.path = CGPath(rect: layerRect(annotation.frame), transform: nil)
        drawnHandles = annotation.handles.map(\.point)
        for point in drawnHandles {
            path.addRect(layerRect(CGRect(x: point.x - Self.handleSide / 2, y: point.y - Self.handleSide / 2,
                                          width: Self.handleSide, height: Self.handleSide)))
        }
        handleLayer.path = path
    }

    private static let handleSide: CGFloat = 8

    /// A dot at each of the area's handles; none for none. A dot is never wider than the reach that
    /// takes it, so an area too small for eight reaches is not drawn eight dots wide.
    private func drawAreaHandles(_ area: CGRect?) {
        guard let area else { areaHandleLayer.path = nil; drawnAreaHandles = []; return }
        let radius = min(AreaFrame.dotRadius, AreaFrame.reach(on: area))
        guard radius >= 1 else { areaHandleLayer.path = nil; drawnAreaHandles = []; return }
        drawnAreaHandles = AreaFrame.offered(on: area).map(\.point)
        let path = CGMutablePath()
        for point in drawnAreaHandles {
            path.addEllipse(in: layerRect(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)))
        }
        areaHandleLayer.path = path
    }

    /// Where the area's handles are drawn, in display-local points; none for none, and none while the
    /// reach is under a point and no dot is drawn.
    private(set) var drawnAreaHandles: [CGPoint] = []

    /// The layers on screen: `drawLayers` keeps what it has put in the view here to compare the next
    /// scene's against, and a test reads it to see the editor drew what it holds and what a layer is made of.
    private(set) var drawnShapes: [CALayer] = []

    /// The one layer the spotlights' dim is, which a test lays over the picture to see what the screen shows of them: it is none of
    /// `drawnShapes`, and it stands under them.
    var drawnSpotlightDim: CAShapeLayer { spotlightLayer }

    /// How many shape layers were built since the view was made, for a test that counts the
    /// rebuilds a pointer event costs.
    private(set) var shapeBuilds = 0
    private var shapeCache: [Annotation.ID: (annotation: Annotation, shape: CALayer, draft: Bool, number: Int?)] = [:]
    private var cachedBox: CGRect?

    /// Where the selected object's handles are drawn, in display-local points; none for none.
    private(set) var drawnHandles: [CGPoint] = []

    /// The plates on screen apart from the area's size over its corner (`areaSizePlate`), so a test can ask how many
    /// there are and where: the coordinates, the size of a drag, the Esc question, and the Pin refusal, which
    /// stands over the palette and not by the pointer.
    var visiblePlates: [LabelLayer] { [coordinateLabel, sizeLabel].filter { !$0.isHidden } }

    /// The size plate over the edited area's top-left corner; nil while none is shown.
    var areaSizePlate: LabelLayer? { cornerLabel.isHidden ? nil : cornerLabel }

    /// The loupe's plate text, and where its window stands; both nil while the loupe is hidden.
    var loupeReading: String? { loupeLayer.reading }
    var loupeDisc: CGRect? { loupeLayer.isHidden ? nil : loupeLayer.disc }

    /// Whether the lines across the screen are drawn.
    var linesAreDrawn: Bool { crosshairLayer.path != nil }
    /// Whether the dim over the picture is drawn, and whether the window fill is, and over what.
    var dimIsDrawn: Bool { dimLayer.path != nil }
    var windowFill: CGRect? { highlightLayer.path?.boundingBoxOfPath }
    /// What the flash lit, in display-local top-left points; nil when it has not flashed.
    var flashedRect: CGRect? { flashLayer.lit.map { CGRect(x: $0.minX, y: bounds.height - $0.maxY, width: $0.width, height: $0.height) } }

    /// Lights `rect` (display-local, top-left points) white and fades it, in a window's outline for a window; the palette
    /// goes, since it is not part of the shot, and the overlay is deaf until it closes.
    func flash(over rect: CGRect, window: Bool) {
        if paletteMade { paletteHost.isHidden = true }
        if popoverMade { popoverHost.isHidden = true }
        if coloursMade { coloursHost.isHidden = true }
        let box = layerRect(rect)
        flashLayer.play(over: box, shape: window ? WindowShape.path(for: box) : CGPath(rect: box, transform: nil))
    }
}

/// A small text plate: white digits on a dark rounded ground, sized to its text.
///
/// **A plate and a text layer inside it, not one text layer.** A `CATextLayer`
/// draws its line from the top of its frame, and a digit has no descender: a
/// plate as tall as the line plus a margin left the digits three points from the
/// top edge and seven and a half from the bottom. The plate is sized to the
/// digits' own height and the line is placed so that they sit in the middle.
final class LabelLayer: CALayer {
    private let text = CATextLayer()

    /// The type ladder's own small size, with digits that keep their width so the
    /// plate does not shimmer while a number changes under the pointer.
    private static var plateFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: HelmText.rowDetailNSFont.pointSize, weight: .medium)
    }

    override init() {
        super.init()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        cornerRadius = 4
        contentsScale = scale
        text.font = Self.plateFont
        text.fontSize = Self.plateFont.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = scale
        addSublayer(text)
    }
    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    var string: String? { text.string as? String }

    /// The plate's size for a string: what `show` lays out, for a caller that places it by its height.
    static func size(of string: String) -> CGSize {
        let font = plateFont
        let measured = (string as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(measured.width) + 14, height: ceil(font.capHeight + 10))
    }

    /// Where the area's size plate stands, as a top-left origin in display points: 14 right of the area's top-left
    /// corner and 12 above it. Where that is not clear of every handle target of `area` once the display's edge has
    /// pushed it in (an area against the top wall, or too narrow to leave the top handle alone), or overlaps one of
    /// `clearOf` (the palette, in the same points), the first of under the area, inside its corner, right of it and
    /// left of it that is clear. With none clear the first place is kept: a plate is never left out.
    static func cornerPlace(of size: CGSize, over area: CGRect, within bounds: CGRect,
                            clearOf others: [CGRect] = []) -> CGPoint {
        let margin: CGFloat = 4
        let candidates = [CGPoint(x: area.minX + 14, y: area.minY - 12 - size.height),
                          CGPoint(x: area.minX + 14, y: area.maxY + 12),
                          CGPoint(x: area.minX + 14, y: area.minY + 14),
                          CGPoint(x: area.maxX + 14, y: area.minY),
                          CGPoint(x: area.minX - 14 - size.width, y: area.minY)].map { origin in
            CGPoint(x: min(max(origin.x, bounds.minX + margin), bounds.maxX - size.width - margin),
                    y: min(max(origin.y, bounds.minY + margin), bounds.maxY - size.height - margin))
        }
        let reach = AreaFrame.reach(on: area)
        return candidates.first { origin in
            let plate = CGRect(origin: origin, size: size)
            return !others.contains { $0.intersects(plate) } && AreaFrame.offered(on: area).allSatisfy { handle in
                hypot(handle.point.x - min(max(handle.point.x, plate.minX), plate.maxX),
                      handle.point.y - min(max(handle.point.y, plate.minY), plate.maxY)) > reach
            }
        } ?? candidates[0]
    }

    func show(_ string: String, near point: CGPoint, within bounds: CGRect) {
        text.string = string
        let font = Self.plateFont
        let line = ceil((string as NSString).size(withAttributes: [.font: font]).height)
        let size = Self.size(of: string)
        // The digits' top edge is `ascender - capHeight` under the line's top
        // and their foot is the baseline, `ascender` under it; the gap above
        // them and below them is the same `(height - capHeight) / 2`.
        let margin = (size.height - font.capHeight) / 2
        text.frame = CGRect(x: 7, y: size.height - margin + (font.ascender - font.capHeight) - line,
                            width: size.width - 14, height: line)
        var origin = point
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)
        frame = CGRect(origin: origin, size: size)
        isHidden = false
    }
}
