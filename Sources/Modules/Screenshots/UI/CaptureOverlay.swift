import AppKit
import QuartzCore
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the person decided on the overlay.
enum OverlayResult {
    /// An area on one display, in that display's own top-left points, with the
    /// layers drawn over it and the way the person left. Every area arrives this
    /// way — with no layers, as a plain crop.
    case edited(display: DisplayID, local: CGRect, layers: [Annotation], exit: EditorExit)
    case window(UInt32)
    case wholeDisplay(DisplayID)
    case cancelled
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
/// plate shows only while an area handle is held, and the keys mean tools, undo and the exits. The picture under the
/// layers is never touched, so every layer is a value that can be undone.
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
    private var spaceHeld = false
    /// The area being edited, set once a selection is released; nil while selecting.
    private var edit: (display: DisplayID, rect: CGRect, layers: AnnotationEditing, tool: AnnotationTool?)?
    /// An area handle under the pointer: which one, the area as the press took it and where the
    /// press landed. Not an edit of the layers, so no undo step: the area is not a layer.
    private var reshaping: (display: DisplayID, handle: AreaHandle, base: CGRect, press: CGPoint)?
    /// The pointer on the display it is over, in that display's top-left points.
    private var pointer: (display: DisplayID, point: CGPoint)?
    private var hovered: FrozenWindow?
    /// What the next object is drawn with; picked on the palette, read from the store when
    /// the first area is released, and kept across the areas of one capture.
    private var style = AnnotationStyle.standard
    /// Where the editor's last tool, colour, thickness and fill are kept. Nil in a test that
    /// remembers nothing.
    private let store: NamespacedStore?
    /// What the palette shows; its cells come back through `perform`.
    let bars = EditorBarModel()
    /// The ⋯ menu: one object, filled again from `bars` at every opening.
    private lazy var moreMenu = EditorMenu.make(for: bars)
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
    /// The Pin item was refused for want of room, and the plate says so until the next input.
    private var pinRefused = false
    /// A nudge let go of the selected object and the arrow key that did it is still down: its repeats
    /// move nothing. Any key or palette click that reaches `perform` while no drag or reshape is under way
    /// clears it, a fresh arrow press (not `isARepeat`) included, so a key-up the overlay never sees cannot
    /// leave the arrows dead; only a repeat can find it set. Mouse input, a modifier change, Esc and
    /// a right click do not go through `perform` and leave it as it was.
    private var arrowReleasedObject = false

    init(freeze: Freeze, mode: Mode = .area, preselection: (display: DisplayID, rect: CGRect)? = nil,
         store: NamespacedStore? = nil, pinRoom: @escaping () -> Bool = { true },
         onFinish: @escaping (OverlayResult) -> Void) {
        self.freeze = freeze
        self.pinRoom = pinRoom
        self.store = store
        self.mode = mode
        self.preselected = mode == .area ? preselection : nil
        self.onFinish = onFinish
        bars.perform = { [weak self] in self?.perform($0) }
        bars.openMenu = { [weak self] in self?.openMoreMenu() }
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

        // The pointer where it already is, so the crosshair is there at once.
        let mouse = NSEvent.mouseLocation
        for (id, entry) in panels where entry.panel.frame.contains(mouse) {
            pointer = (id, local(mouse, in: entry.panel, frame: entry.view.frozen.frame.height))
        }
        // Opened in window mode, the window under the pointer is lit at once.
        if mode == .window, let pointer { hovered = windowUnder(display: pointer.display, local: pointer.point) }
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
        onFinish = nil
        edit = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for entry in panels.values {
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
        }
        panels.removeAll()
        NSCursor.arrow.set()
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
        if chrome(on: display)?.covers(local) == true {
            if var current = edit, drag == nil { current.layers.disarm(); current.layers.releaseIfOutside(); edit = current; render() }
            return
        }
        if var current = edit, drag == nil {
            current.layers.disarm()
            // The editor reads the press on the edited display only: a handle of the area reshapes it
            // (an object's own handle, where the two meet, is taken first), a tool draws, a handle
            // resizes, an object is taken to be moved, and a click selects or lets go. What is
            // left is no tool and no layers, the old gesture, a new drag, which replaces the
            // area only when it turns out to be one; on another display, with a tool or with
            // layers, a press does nothing. The disarm is the click's own effect, kept either way.
            if display == current.display,
               let handle = AreaFrame.handle(of: current.rect, at: local, yieldingTo: current.layers.selected) {
                current.layers.end()
                reshaping = (display, handle, current.rect, local)
                edit = current
                render()
                return
            }
            if display == current.display,
               current.layers.press(at: local, tool: current.tool, style: style) {
                edit = current
                render()
                return
            }
            guard current.tool == nil, current.layers.layers.isEmpty else { edit = current; render(); return }
            edit = current
        }
        switch mode {
        case .window:
            if let hovered { finish(.window(hovered.id)) }
        case .area:
            guard let frame = freeze.frames.first(where: { $0.id == display }) else { return }
            let bounds = CGRect(origin: .zero, size: frame.frame.size)
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
                edit = current
            }
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

    /// Esc and the right click are one door with one rule, `AnnotationEditing.escape`; a press while an area handle is held only puts the area back and does nothing else:
    /// at once with nothing to lose, and with layers a second press, whenever
    /// it comes; a selected object is let go of first, and that press asks nothing. A drag in progress is not an edit and leaves at once.
    private func escapeAsked() {
        pinRefused = false
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
        if var current = edit, drag == nil {
            current.layers.end()
            edit = current
            render()
            return
        }
        guard let current = drag, current.display == display else { return }
        // A click that never moved is not a selection: the drag ends and the
        // overlay waits for a real one — or goes on editing the one it had.
        guard current.drag.isUsable else { drag = nil; render(); return }
        startEditing(display: display, rect: current.drag.rect)
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
            let remembered = EditorMemory.read(store)
            tool = remembered.tool
            style = remembered.style
        }
        edit = (display, rect, AnnotationEditing(bounds: rect), tool)
        render()
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
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
        if edit != nil, drag == nil { editorKey(event); return }
        switch event.keyCode {
        case 36, 76: // return, enter
            // A held Return repeats, and a repeat is not a press that asked for anything.
            guard !event.isARepeat else { return }
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
            } else {
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
                current.rect = AreaFrame.nudged(current.rect, by: delta, within: CGRect(origin: .zero, size: frame.frame.size))
                current.layers.reshape(bounds: current.rect)
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
        defer { edit = current; render() }
        switch action {
        case .tool(let tool)?:
            // The same key again puts the tool down, which is how a drag selects again;
            // a held key's repeats are not that second press.
            guard !isRepeat else { return }
            current.tool = current.tool == tool ? nil : tool
            if let store { EditorMemory.remember(tool: current.tool, in: store) }
        case .select?:
            current.tool = nil
            if let store { EditorMemory.remember(tool: nil, in: store) }
        // A pick is the next object's and, with one selected, that object's too.
        case .color(let color)?:
            style.color = color
            current.layers.recolor(color)
            if let store { EditorMemory.remember(style: style, in: store) }
        case .thickness(let step)?:
            style.thickness = step
            current.layers.setThickness(step)
            if let store { EditorMemory.remember(style: style, in: store) }
        case .toggleFill?:
            // With a box selected the fill is flipped from that box's own state, and the pick follows it.
            if let box = current.layers.selected, box.tool == .rectangle || box.tool == .ellipse {
                style.filled = !box.style.filled
                current.layers.setFilled(style.filled)
            } else {
                style.filled.toggle()
            }
            if let store { EditorMemory.remember(style: style, in: store) }
        case .delete?: current.layers.deleteSelected()
        case .undo?: current.layers.undo()
        case .redo?: current.layers.redo()
        case .exit(let how)?:
            guard !isRepeat else { return }
            // No room for a pin: the editor stays, with the picture in it, and says why on the plate
            // (the toast lies below the overlay and could not be seen).
            if how == .pin, !pinRoom() { pinRefused = true; return }
            // What the screen shows is what is delivered: a stroke still under the
            // pointer becomes a layer now, and an unusable one is dropped by `end`.
            current.layers.end()
            finish(.edited(display: current.display, local: current.rect, layers: current.layers.layers, exit: how))
        case .nudge?, .close?, nil: break
        }
    }

    /// What ⋯ asks for: the menu, under the ⋯ circle on the display whose palette is up. `popUp` returns only when the
    /// menu has closed, which the palette's pressed look counts on.
    private func openMoreMenu() {
        guard let view = panels.values.first(where: { $0.view.barsAreShown })?.view else { return }
        openedMenu = moreMenu
        defer { openedMenu = nil }
        view.popUp(moreMenu, below: EditorPalette.moreCircleBottomLeft(bars.moreFrame))
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

    private func displayBounds(_ display: DisplayID) -> CGRect? {
        freeze.frames.first { $0.id == display }.map { CGRect(origin: .zero, size: $0.frame.size) }
    }

    /// Where the palette stands on `display`: nil when it is not the edited one, and nil while an
    /// object is being drawn, moved or resized — a palette under the pointer would be drawn into — or
    /// the area is being reshaped or a new one dragged. It is back on the release, and on the
    /// Esc that drops a drawing or cancels a move, a resize or a reshape.
    func chrome(on display: DisplayID) -> EditorChrome? {
        guard let edit, drag == nil, reshaping == nil, !edit.layers.isBusy, edit.display == display,
              let view = panels[display]?.view else { return nil }
        return EditorChrome.place(selection: edit.rect, in: view.frozen.frame.size, palette: view.paletteSize)
    }

    private func render() {
        if let edit {
            let held = edit.layers.selected
            bars.show(tool: edit.tool, style: held?.style ?? style, selectedTool: held?.tool,
                      canUndo: edit.layers.canUndo, canRedo: edit.layers.canRedo)
        }
        for (id, entry) in panels {
            var scene = OverlayScene()
            scene.windowMode = mode == .window
            if let pointer, pointer.display == id, edit == nil || drag != nil { scene.pointer = pointer.point }
            if let drag, drag.display == id { scene.selection = drag.drag.rect }
            else if let edit, edit.display == id {
                scene.selection = edit.rect
                scene.editing = drag == nil
                if let reshaping, reshaping.display == id, let pointer, pointer.display == id {
                    scene.sizingAt = pointer.point
                }
                scene.chrome = chrome(on: id)
                scene.layers = edit.layers.layers + (edit.layers.draft.map { [$0] } ?? [])
                scene.selected = edit.layers.draft == nil ? edit.layers.selected : nil
                if pinRefused {
                    // By the palette, which the menu was opened from, so that the plate does not lie under the glass.
                    scene.plate = ScStr.pinLimit
                    scene.plateByActions = true
                } else if edit.layers.isArmed {
                    scene.plate = ScStr.confirmClose
                    if let pointer, pointer.display == id { scene.plateAt = pointer.point }
                }
            } else if mode == .area, let preselected, preselected.display == id { scene.selection = preselected.rect }
            if mode == .window, let hovered, let frame = freeze.frames.first(where: { $0.id == id }) {
                let part = ScreenSpace.local(hovered.frame, in: frame.frame)
                    .intersection(CGRect(origin: .zero, size: frame.frame.size))
                if !part.isNull, part.width > 0, part.height > 0 { scene.highlight = part }
            }
            entry.view.apply(scene)
        }
    }
}

/// Everything one panel draws, decided by the overlay.
struct OverlayScene {
    var windowMode = false
    var pointer: CGPoint?
    var selection: CGRect?
    var highlight: CGRect?
    /// The area is being edited: no crosshair; the size plate only while an area handle is held (`sizingAt`).
    var editing = false
    /// Layers over the selection, the one being drawn last.
    var layers: [Annotation] = []
    /// The selected layer, held by its handles; nil while one is being drawn.
    var selected: Annotation?
    /// Where the palette stands; nil is none on this display, or none while drawing, moving, resizing or reshaping.
    var chrome: EditorChrome?
    /// What Esc asked, while it is waiting for its second press.
    var plate: String?
    /// Where the pointer is while the plate is up, in display-top-left points; the
    /// crosshair stays off while editing, so this is not `pointer`.
    var plateAt: CGPoint?
    /// The plate is the Pin refusal: it goes above the palette, or below it with no room above, not by the pointer.
    var plateByActions = false
    /// The area is being reshaped and the pointer is here: its size in pixels is on a plate by it.
    var sizingAt: CGPoint?
}

// MARK: - The panel

/// The capture overlay's panel: borderless, non-activating, at the screen-saver level.
///
/// What was measured of a menu and tooltips over it (2026-10-02/03, Helm inactive, real keyboard): an `NSMenu`
/// popped up from the editor's bar works: an item click and a submenu item click both land, and the
/// checkmark is drawn. With the menu closed, `EditorKeys` selects tools by key code, in the US and the Russian layout alike (the two measured);
/// with it open, a `keyEquivalent` "a" fired in the US layout and not in the Russian one. Tooltips (`.help`) were not
/// shown on the bar cells, and the overlay forces the crosshair on every move (its cursor sets climbed by hundreds per
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
    private let coordinateLabel = LabelLayer()
    private let sizeLabel = LabelLayer()
    /// The editor's palette, made when this display first has an area to edit and never
    /// on another: a display with nothing selected builds no SwiftUI at all.
    private lazy var paletteHost = EditorBarHostingView(rootView: EditorPalette(model: overlay!.bars))
    private var barsMade = false
    private lazy var measuredPalette: CGSize = {
        barsMade = true
        addSubview(paletteHost)
        paletteHost.isHidden = true
        return paletteHost.fittingSize
    }()

    /// What the palette measures in the language the overlay opened in; measured once, since the
    /// language cannot change under a capture that is up.
    var paletteSize: CGSize { measuredPalette }

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

    /// Whether the palette is on screen, for a test.
    var barsAreShown: Bool { barsMade && !paletteHost.isHidden }
    /// The view a click at a display-local point would reach, for a test that asks whether it is the palette.
    func clickTarget(at local: CGPoint) -> NSView? { hitTest(CGPoint(x: local.x, y: bounds.height - local.y)) }
    /// Whether a view is the palette or inside it.
    func isBar(_ view: NSView?) -> Bool {
        guard barsMade, let view else { return false }
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
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor

        highlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        highlightLayer.strokeColor = NSColor.controlAccentColor.cgColor
        highlightLayer.lineWidth = 2

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
        crosshairLayer.shadowColor = NSColor.black.cgColor
        crosshairLayer.shadowOpacity = 0.6
        crosshairLayer.shadowRadius = 0
        crosshairLayer.shadowOffset = .zero

        for sublayer in [imageLayer, dimLayer, highlightLayer, selectionLayer, frameLayer, areaHandleLayer, handleLayer,
                         crosshairLayer,
                         coordinateLabel, sizeLabel] as [CALayer] {
            layer?.addSublayer(sublayer)
        }
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        for label in [coordinateLabel, sizeLabel] { label.isHidden = true }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Space

    /// A point of this view in the engine's display-local points: top-left origin.
    private func local(_ point: NSPoint) -> CGPoint { CGPoint(x: point.x, y: bounds.height - point.y) }

    /// A display-local rectangle as a rectangle of this view's layers.
    private func layerRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        setCursor()
        overlay?.mouseMoved(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)))
    }
    override func mouseEntered(with event: NSEvent) { setCursor() }
    override func cursorUpdate(with event: NSEvent) { setCursor() }

    override func mouseDown(with event: NSEvent) {
        overlay?.mouseDown(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)),
                           flags: event.modifierFlags)
    }
    override func mouseDragged(with event: NSEvent) {
        overlay?.mouseDragged(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)),
                              flags: event.modifierFlags)
    }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(on: frozen.id) }
    override func rightMouseDown(with event: NSEvent) { overlay?.rightMouseDown() }
    override func flagsChanged(with event: NSEvent) { overlay?.flagsChanged(event.modifierFlags) }
    override func keyDown(with event: NSEvent) { overlay?.keyDown(event) }
    override func keyUp(with event: NSEvent) { overlay?.keyUp(event) }

    /// Set on every move as well as in `cursorUpdate`: Helm is not the active
    /// application, and the system is free to put the arrow back under a
    /// non-activating panel between one update and the next.
    private var windowMode = false
    private func setCursor() {
        (windowMode ? Self.cameraCursor : NSCursor.crosshair).set()
    }

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
        let all = bounds
        let hole = scene.selection.map(layerRect) ?? scene.highlight.map(layerRect)
        let dim = CGMutablePath()
        dim.addRect(all)
        if let hole { dim.addRect(hole) }
        dimLayer.path = dim

        highlightLayer.path = scene.highlight.map { CGPath(rect: layerRect($0), transform: nil) }
        selectionLayer.path = scene.selection.map { CGPath(rect: layerRect($0), transform: nil) }

        drawLayers(scene)
        drawAreaHandles(scene.editing ? scene.selection : nil)
        if let chrome = scene.chrome {
            _ = measuredPalette
            paletteHost.frame = layerRect(chrome.palette)
            paletteHost.isHidden = false
        } else if barsMade {
            paletteHost.isHidden = true
        }

        let at = scene.pointer.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        if let at, !scene.windowMode {
            let lines = CGMutablePath()
            lines.move(to: CGPoint(x: 0, y: at.y)); lines.addLine(to: CGPoint(x: bounds.width, y: at.y))
            lines.move(to: CGPoint(x: at.x, y: 0)); lines.addLine(to: CGPoint(x: at.x, y: bounds.height))
            crosshairLayer.path = lines
        } else {
            crosshairLayer.path = nil
        }

        // **One plate, by the pointer.** Before a drag it says where the pointer
        // is; while one is open it says how large the selection is, in the same
        // place — the size *replaces* the coordinates, as macOS's own ⌘⇧4 does.
        // Two plates at the pointer's offset lay one over the other.
        if scene.editing {
            // Editing has no crosshair and no size plate; only the Esc question, and the size of an
            // area being reshaped, which is the drag's own plate.
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
            if let at = scene.sizingAt, let selection = scene.selection {
                let pixels = Selection.pixelSize(of: selection, scale: frozen.scale)
                sizeLabel.show("\(pixels.width) × \(pixels.height)",
                               near: CGPoint(x: at.x + 14, y: bounds.height - at.y - 26), within: bounds)
            } else if let plate = scene.plate, let selection = scene.selection {
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
            drawHandles(nil)
            return
        }
        let box = layerRect(selection)
        if cachedBox != box {
            for entry in shapeCache.values { entry.shape.removeFromSuperlayer() }
            shapeCache = [:]
            cachedBox = box
        }
        var kept: [Annotation.ID: (annotation: Annotation, shape: CAShapeLayer)] = [:]
        for annotation in scene.layers {
            if let entry = shapeCache[annotation.id], entry.annotation == annotation {
                kept[annotation.id] = entry
            } else {
                shapeCache[annotation.id]?.shape.removeFromSuperlayer()
                kept[annotation.id] = (annotation, makeShape(annotation, clippedTo: box))
            }
        }
        for (id, entry) in shapeCache where kept[id]?.shape !== entry.shape { entry.shape.removeFromSuperlayer() }
        shapeCache = kept
        let ordered = scene.layers.compactMap { kept[$0.id]?.shape }
        // Re-inserting each below the dim in turn is what puts the sequence in order.
        if ordered.count != drawnShapes.count || !zip(ordered, drawnShapes).allSatisfy({ $0 === $1 }) {
            for shape in ordered { layer?.insertSublayer(shape, below: dimLayer) }
        }
        drawnShapes = ordered
        drawHandles(scene.selected)
    }

    private func makeShape(_ annotation: Annotation, clippedTo box: CGRect) -> CAShapeLayer {
        shapeBuilds += 1
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
        } else {
            shape.path = path?.intersection(clip)
            shape.fillColor = annotation.fillColor
        }
        shape.strokeColor = nil
        return shape
    }

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
    private(set) var drawnShapes: [CAShapeLayer] = []

    /// How many shape layers were built since the view was made, for a test that counts the
    /// rebuilds a pointer event costs.
    private(set) var shapeBuilds = 0
    private var shapeCache: [Annotation.ID: (annotation: Annotation, shape: CAShapeLayer)] = [:]
    private var cachedBox: CGRect?

    /// Where the selected object's handles are drawn, in display-local points; none for none.
    private(set) var drawnHandles: [CGPoint] = []

    /// The plates on screen, so a test can ask how many there are and where.
    var visiblePlates: [LabelLayer] { [coordinateLabel, sizeLabel].filter { !$0.isHidden } }
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
