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
/// overlay stays and edits it: `edit` is non-nil, the crosshair and the size plate
/// are gone, and the keys mean tools, undo and the exits. The picture under the
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
    /// The pointer on the display it is over, in that display's top-left points.
    private var pointer: (display: DisplayID, point: CGPoint)?
    private var hovered: FrozenWindow?

    /// What the overlay opened on, for a test that must know the bar's Area mode
    /// handed it the remembered selection and no other press did.
    var preselection: (display: DisplayID, rect: CGRect)? { preselected }

    /// What each view is drawing as its picture, for a test that must know it is
    /// the frame without the pointer: the live crosshair is drawn over it, and a
    /// pointer baked into it would be a second one.
    var drawnPictures: [DisplayID: CGImage] {
        panels.compactMapValues { $0.view.drawnPicture }
    }

    init(freeze: Freeze, mode: Mode = .area, preselection: (display: DisplayID, rect: CGRect)? = nil,
         onFinish: @escaping (OverlayResult) -> Void) {
        self.freeze = freeze
        self.mode = mode
        self.preselected = mode == .area ? preselection : nil
        self.onFinish = onFinish
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

    func close() {
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
        if var current = edit, drag == nil {
            current.layers.disarm()
            // A tool draws on the edited display only; no tool and no layers is
            // the old gesture, a new drag, which replaces the area only when it
            // turns out to be one; no tool over layers does nothing yet.
            if let tool = current.tool {
                // The disarm above is the click's own effect, kept whichever display it was on.
                guard display == current.display else { edit = current; render(); return }
                current.layers.begin(tool, at: local)
                edit = current
                render()
                return
            }
            guard current.layers.layers.isEmpty else { edit = current; render(); return }
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
        if var current = edit, drag == nil {
            current.layers.drag(to: local)
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

    /// Esc and the right click are one door with one rule, `AnnotationEditing.escape`:
    /// at once with nothing to lose, and with layers a second press, whenever
    /// it comes. A drag in progress is not an edit and leaves at once.
    private func escapeAsked() {
        guard var current = edit, drag == nil else { finish(.cancelled); return }
        let outcome = current.layers.escape()
        edit = current
        switch outcome {
        case .close: finish(.cancelled)
        case .armed: render()
        }
    }

    /// The view for a display, so a test can send it a real event.
    func view(for display: DisplayID) -> OverlayView? { panels[display]?.view }

    func mouseUp(on display: DisplayID) {
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
        edit = (display, rect, AnnotationEditing(bounds: rect), edit?.tool)
        render()
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        // Shift and option change the selection without the pointer moving.
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
    /// every key the editor has no use for only withdraw a question asked by Esc.
    private func editorKey(_ event: NSEvent) {
        guard var current = edit else { return }
        current.layers.disarm()
        defer { edit = current; render() }
        switch EditorKeys.action(keyCode: event.keyCode, flags: event.modifierFlags) {
        case .tool(let tool)?:
            // The same key again puts the tool down, which is how a drag selects again;
            // a held key's repeats are not that second press.
            guard !event.isARepeat else { return }
            current.tool = current.tool == tool ? nil : tool
        case .undo?: current.layers.undo()
        case .redo?: current.layers.redo()
        case .exit(let how)?:
            guard !event.isARepeat else { return }
            // What the screen shows is what is delivered: a stroke still under the
            // pointer becomes a layer now, and an unusable one is dropped by `end`.
            current.layers.end()
            finish(.edited(display: current.display, local: current.rect, layers: current.layers.layers, exit: how))
        case nil: break
        }
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

    private func render() {
        for (id, entry) in panels {
            var scene = OverlayScene()
            scene.windowMode = mode == .window
            if let pointer, pointer.display == id, edit == nil || drag != nil { scene.pointer = pointer.point }
            if let drag, drag.display == id { scene.selection = drag.drag.rect }
            else if let edit, edit.display == id {
                scene.selection = edit.rect
                scene.editing = drag == nil
                scene.layers = edit.layers.layers + (edit.layers.draft.map { [$0] } ?? [])
                if edit.layers.isArmed {
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
    /// The area is being edited: no crosshair, no size plate.
    var editing = false
    /// Layers over the selection, the one being drawn last.
    var layers: [Annotation] = []
    /// What Esc asked, while it is waiting for its second press.
    var plate: String?
    /// Where the pointer is while the plate is up, in display-top-left points; the
    /// crosshair stays off while editing, so this is not `pointer`.
    var plateAt: CGPoint?
}

// MARK: - The panel

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
    /// The editor's layers, clipped to the selection: one shape layer each, in a
    /// layer that is the selection's own size so that the clip is its bounds.
    private let layersClip = CALayer()
    private let crosshairLayer = CAShapeLayer()
    private let coordinateLabel = LabelLayer()
    private let sizeLabel = LabelLayer()

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

        crosshairLayer.fillColor = nil
        crosshairLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        crosshairLayer.lineWidth = 1
        crosshairLayer.shadowColor = NSColor.black.cgColor
        crosshairLayer.shadowOpacity = 0.6
        crosshairLayer.shadowRadius = 0
        crosshairLayer.shadowOffset = .zero

        for sublayer in [imageLayer, dimLayer, highlightLayer, selectionLayer, layersClip, crosshairLayer,
                         coordinateLabel, sizeLabel] as [CALayer] {
            layer?.addSublayer(sublayer)
        }
        layersClip.masksToBounds = true
        layersClip.isHidden = true
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
            // Editing has no crosshair and no size plate; only the Esc question.
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
            if let plate = scene.plate, let selection = scene.selection {
                let box = layerRect(selection)
                // The pointer's offset, as the other plates; the selection's corner
                // is the fallback for a scene with no pointer.
                let anchor = scene.plateAt.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
                    ?? CGPoint(x: box.maxX, y: box.minY + 26)
                sizeLabel.show(plate, near: CGPoint(x: anchor.x + 14, y: anchor.y - 26), within: bounds)
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

    /// One shape layer per annotation, in the clip's own bottom-left points: the
    /// path is the annotation's top-left one turned over inside the selection.
    private func drawLayers(_ scene: OverlayScene) {
        layersClip.sublayers = nil
        guard scene.editing, let selection = scene.selection else { layersClip.isHidden = true; return }
        layersClip.isHidden = false
        layersClip.frame = layerRect(selection)
        var turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -selection.minX, ty: selection.maxY)
        for annotation in scene.layers {
            let shape = CAShapeLayer()
            shape.contentsScale = frozen.scale
            shape.frame = layersClip.bounds
            shape.path = annotation.outline.copy(using: &turn)
            shape.lineJoin = .miter
            if annotation.isFilled {
                shape.fillColor = Annotation.ink
                shape.strokeColor = nil
            } else {
                shape.fillColor = nil
                shape.strokeColor = Annotation.ink
                shape.lineWidth = Annotation.lineWidth
            }
            layersClip.addSublayer(shape)
        }
    }

    /// The layers on screen, for a test that must see the editor drew what it holds.
    var drawnLayerCount: Int { layersClip.isHidden ? 0 : layersClip.sublayers?.count ?? 0 }

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

    func show(_ string: String, near point: CGPoint, within bounds: CGRect) {
        text.string = string
        let font = Self.plateFont
        let measured = (string as NSString).size(withAttributes: [.font: font])
        let line = ceil(measured.height)
        let size = CGSize(width: ceil(measured.width) + 14, height: ceil(font.capHeight + 10))
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
