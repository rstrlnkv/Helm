import AppKit
import QuartzCore
import SwiftUI
import Module_Screenshots_Engine

// MARK: - The view

/// One display's frozen frame, and the selection drawn over it.
///
/// Layers and not `draw(_:)`: the pointer moves many times a frame and a 5K
/// panel redrawn in full for each is the cost this avoids. The view is **not**
/// flipped — a flipped layer-backed view turns an image layer upside down — so
/// it converts to the engine's top-left points at the edge, in `local(_:)` and
/// `layerRect(_:)`, and where a bare point or the pointer goes to a layer, by the height.
final class OverlayView: NSView {
    let frozen: FrozenDisplay
    /// The overlay's one table of inks, resolved when the view is built.
    let ink: OverlayInk
    weak var overlay: CaptureOverlay?

    private let imageLayer = CALayer()
    let dimLayer = CAShapeLayer()
    /// The card's shadow, over the dim and under the picture's own edge: a black rectangle of the picture's size with a shadow, masked to what is
    /// outside the picture, so it darkens nothing of the picture and clips nothing of it. No border, no rounding: the picture's pixels are drawn
    /// square, and a rounded corner would cut them or the handles.
    let cardLayer = CAShapeLayer()
    let cardMask = CAShapeLayer()
    /// The spotlights' one dim (`Spotlights`): under every annotation's layer and over the picture, a layer of its own and
    /// not one per spotlight, so the dim does not add up where two spotlights meet.
    let spotlightLayer = CAShapeLayer()
    let highlightEdgeLayer = CAShapeLayer()
    let highlightLayer = CAShapeLayer()
    let selectionLayer = CAShapeLayer()
    /// The selected object's box and handles: over the dim, since a handle on the selection's
    /// edge is half outside its hole. The box is a layer of its own with no fill: one path holding the
    /// box and the handles under a white fill painted the box white, over the very object it frames.
    let frameLayer = CAShapeLayer()
    let handleLayer = CAShapeLayer()
    /// The area's own handles, eight or four on a small area (`AreaFrame.offered`): round and white on a dark edge, where an object's are squares
    /// on the accent colour, so the two are not taken for each other.
    let areaHandleLayer = CAShapeLayer()
    let crosshairLayer = CAShapeLayer()
    /// The ruler, over the layers and the dim's hole and under the palette's host, which is a subview.
    let rulerLayer = RulerLayer()
    /// The lines' dark edge, under them and a half point wider each side, so they read on a white page as on a black one.
    let crosshairEdgeLayer = CAShapeLayer()
    let coordinateLabel = LabelLayer()
    let sizeLabel = LabelLayer()
    /// The area's size over its top-left corner while it is edited: a plate of its own, since `sizeLabel` is the
    /// one by the pointer that the Esc question uses; the Pin refusal stands over the palette.
    let cornerLabel = LabelLayer()
    let loupeLayer = LoupeLayer()
    let flashLayer = FlashLayer()
    /// The editor's palette, made when this display first has an area to edit and never
    /// on another: a display with nothing selected builds no SwiftUI at all.
    lazy var paletteHost = EditorBarHostingView(rootView: EditorPalette(model: overlay!.palette))
    var paletteMade = false
    lazy var measuredPalette: CGSize = {
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
    lazy var popoverHost: EditorBarHostingView<EditorPopover> = {
        popoverMade = true
        let host = EditorBarHostingView(rootView: EditorPopover(model: overlay!.palette, height: popoverSize.height))
        host.isHidden = true
        addSubview(host)
        return host
    }()
    var popoverMade = false
    /// The thickness and opacity pop-over's card laid out whole, measured once like the palette.
    private lazy var measuredPopover = NSHostingView(rootView: EditorPopover(model: overlay!.palette, height: nil)).fittingSize
    var popoverSize: CGSize { measuredPopover }

    /// The colours pop-over's host and size, made and measured the same way, at the first need.
    lazy var coloursHost: EditorBarHostingView<EditorColoursPopover> = {
        coloursMade = true
        let host = EditorBarHostingView(rootView: EditorColoursPopover(model: overlay!.palette, height: coloursSize.height))
        host.isHidden = true
        addSubview(host)
        return host
    }()
    var coloursMade = false
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
    func placeEmojiGrid(_ scene: OverlayScene) {
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

    /// Whether the palette is on screen; `openMoreMenu` asks it.
    var paletteIsShown: Bool { paletteMade && !paletteHost.isHidden }

    init(frozen: FrozenDisplay, overlay: CaptureOverlay) {
        self.frozen = frozen
        self.overlay = overlay
        ink = OverlayInk(increased: overlay.increasesContrast(), appearance: NSApplication.shared.effectiveAppearance)
        super.init(frame: CGRect(origin: .zero, size: frozen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageLayer.contents = frozen.image
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = frozen.scale

        dimLayer.fillRule = .evenOdd
        spotlightLayer.fillRule = .evenOdd
        spotlightLayer.fillColor = Spotlights.color
        dimLayer.fillColor = ink.dim
        cardLayer.fillColor = NSColor.black.cgColor
        cardLayer.shadowColor = NSColor.black.cgColor
        cardLayer.shadowOpacity = Float(Self.cardShadowOpacity)
        cardLayer.shadowRadius = Self.cardShadowRadius
        cardLayer.shadowOffset = CGSize(width: 0, height: -Self.cardShadowDrop)
        cardMask.fillRule = .evenOdd
        cardLayer.mask = cardMask

        highlightEdgeLayer.fillColor = nil
        highlightEdgeLayer.strokeColor = ink.contrastEdgeUnder
        highlightEdgeLayer.lineWidth = 3
        highlightLayer.fillColor = ink.wash
        highlightLayer.strokeColor = ink.contrastEdge
        highlightLayer.lineWidth = 1.5

        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = NSColor.white.cgColor
        selectionLayer.lineWidth = 1

        frameLayer.fillColor = nil
        frameLayer.strokeColor = ink.accent
        frameLayer.lineWidth = 1.5

        handleLayer.fillColor = NSColor.white.cgColor
        handleLayer.strokeColor = ink.accent
        handleLayer.lineWidth = 1.5

        areaHandleLayer.fillColor = NSColor.white.cgColor
        areaHandleLayer.strokeColor = ink.handleEdge
        areaHandleLayer.lineWidth = 1

        crosshairLayer.fillColor = nil
        crosshairLayer.strokeColor = ink.line
        crosshairLayer.lineWidth = 1
        crosshairEdgeLayer.fillColor = nil
        crosshairEdgeLayer.strokeColor = ink.lineEdge
        crosshairEdgeLayer.lineWidth = 2

        rulerLayer.paint(ink)
        loupeLayer.paint(ink)
        rulerLayer.isHidden = true
        for sublayer in [imageLayer, spotlightLayer, dimLayer, cardLayer, highlightEdgeLayer, highlightLayer, selectionLayer, frameLayer, areaHandleLayer, handleLayer, rulerLayer,
                         crosshairEdgeLayer, crosshairLayer, flashLayer,
                         coordinateLabel, sizeLabel, cornerLabel, loupeLayer] as [CALayer] {
            layer?.addSublayer(sublayer)
        }
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        cardLayer.frame = bounds
        cardMask.frame = bounds
        spotlightLayer.frame = bounds
        flashLayer.frame = bounds
        for label in [coordinateLabel, sizeLabel, cornerLabel] { label.isHidden = true }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The card's shadow: the design system has no shadow token (`HelmSurfaces.swift`'s is the icon plate's, by its size, and `HelmAppMark.swift` and `HelmBadge.swift` have one of their own each), so these are this
    /// overlay's own, near the loupe's ring (`LoupeLayer` in `OverlayLoupe.swift`: 0.45, radius 9) and wider for a thing the size of a window.
    private static let cardShadowOpacity: CGFloat = 0.5
    private static let cardShadowRadius: CGFloat = 24
    private static let cardShadowDrop: CGFloat = 8

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
        field.outline(ink)
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
    func layerRect(_ rect: CGRect) -> CGRect {
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
    override func rightMouseDown(with event: NSEvent) {
        live?.rightMouseDown(on: frozen.id, at: local(convert(event.locationInWindow, from: nil)))
    }
    override func flagsChanged(with event: NSEvent) { live?.flagsChanged(event.modifierFlags) }
    override func keyDown(with event: NSEvent) { live?.keyDown(event) }
    override func keyUp(with event: NSEvent) { live?.keyUp(event) }

    /// Set on every move as well as in `cursorUpdate`: Helm is not the active
    /// application, and the system is free to put the arrow back under a
    /// non-activating panel between one update and the next.
    var windowMode = false
    /// The eraser is on (`OverlayScene.erasing`): the cursor is its circle.
    var erasing = false
    /// The eyedropper is on (`OverlayScene.sampling`): the cursor is its symbol, before the eraser's circle, as the press goes to the
    /// eyedropper before the eraser.
    var sampling = false
    /// The cursor the view asks for now.
    private var askedCursor: NSCursor {
        windowMode ? Self.cameraCursor : sampling ? Self.eyedropperCursor : erasing ? Self.eraserCursor : NSCursor.crosshair
    }
    func setCursor() { askedCursor.set() }

    struct DraftGrain: Equatable { let anchor: CGPoint, scale: CGFloat, size: CGSize }
    var draftGrain: (key: DraftGrain, mask: PencilGrain.Mask, alpha: CGImage)?

    /// Where the area's handles are drawn, in display-local points; none for none, and none while the
    /// reach is under a point and no dot is drawn.
    var drawnAreaHandles: [CGPoint] = []

    /// The layers on screen: `drawLayers` keeps what it has put in the view here to compare the next
    /// scene's against.
    var drawnShapes: [CALayer] = []

    var shapeCache: [Annotation.ID: (annotation: Annotation, shape: CALayer, draft: Bool, number: Int?)] = [:]
    var cachedBox: CGRect?
}
