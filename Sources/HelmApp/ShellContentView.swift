import AppKit
import HelmRuntime

/// **The shell's content view: glass at the bottom, the sidebar on it, and the
/// opaque card inset from the window's edge, with the pane clipped inside the
/// card to the card's corners.** Every frame comes from `ShellGeometry`; the
/// view holds no radius of its own, it cuts the card from the corner
/// `WindowCorner` read and applies it to the card and to the clip in one place,
/// `apply(_:)`.
///
/// Subviews, bottom to top: the glass (regular, full bleed, no content view);
/// on macOS 27 a full-bleed probe whose only job is to report the window's
/// corner; the sidebar, as wide as the card's x so the two cannot part; the card,
/// and inside it the clip, and inside that the pane. The card carries the fill
/// and the shadow and never masks, so the shadow is not cut; the clip masks, so
/// the pane's band does not run square to the window's corner. The sidebar and
/// the pane are handed in, and so is `cardMoved`, told where the card went each
/// time it moves; this view names no page and builds no toolbar; of the window's
/// toolbar it asks only whether there is one.
///
/// **One reader.** `layout()` reads the corner, whoever asked for the layout:
/// AppKit on a resize, the probe on macOS 27 when its radii change,
/// `viewDidMoveToWindow`, `sidebarWidth`'s setter and `barWasAttached()`. Events
/// only ask (`needsLayout = true`).
///
/// **Not-a-number.** A sidebar width that is not a number is `ShellGeometry`'s
/// business (`cardFrame` reads it as 0), and the sidebar's frame is cut from the
/// card's x, so it is finite whenever the card's is. A radius the probe or the
/// window answers as not-a-number is a rung that did not answer
/// (`WindowCorner.read`), never a radius.
@MainActor
final class ShellContentView: NSView {

    /// The sidebar's width; the view does not clamp it (`ShellGeometry.railWidth` is
    /// outside `ShellGeometry.sidebarRange`). Setting it asks for a layout.
    var sidebarWidth: CGFloat = ShellGeometry.defaultSidebarWidth {
        didSet { needsLayout = true }
    }

    /// Carries the fill, the radius and the shadow; never masks.
    let card = NSView()

    /// Masks at the card's radius; holds the pane.
    let clip = NSView()

    private let sidebar: NSView
    private let pane: NSView
    private let glass = NSGlassEffectView()
    private let cardMoved: (CGRect) -> Void
    private var lastTold: CGRect?
    private var applied: WindowCorner?
    private var journal = WindowCorner.Journal()

    /// The window the journal was started for. Weak, so a freed window cannot be
    /// mistaken for a new one that reuses its address: a view taken out and put
    /// back into the same window keeps its journal and its bound, and only a
    /// different window starts a new one.
    private weak var journalWindow: NSWindow?
    private let system = ProcessInfo.processInfo.operatingSystemVersion

    /// Nil below macOS 27, where there is no public reading.
    private var probe: NSView?

    override var isFlipped: Bool { true }

    /// The closure and the two views are held for as long as this view lives: a
    /// receiver that owns this view captures itself weakly. `cardMoved` is called
    /// before the corner of that layout is applied.
    init(sidebar: NSView, pane: NSView, cardMoved: @escaping (CGRect) -> Void) {
        self.sidebar = sidebar
        self.pane = pane
        self.cardMoved = cardMoved
        super.init(frame: .zero)

        glass.style = .regular
        addSubview(glass)
        if #available(macOS 27.0, *) {
            let probe = CornerProbe()
            self.probe = probe
            addSubview(probe)
        }
        addSubview(sidebar)

        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = false
        // NSView.shadow, not the layer's shadow properties: on 27.2, off screen, the
        // layer's shadowOpacity read 0 after the fill was set again on an appearance
        // change. 0.12, 6 and -1 are tuned by eye, not measured; they are on no ladder
        // and a ladder is not where they are meant to go.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        card.shadow = shadow
        addSubview(card)

        clip.wantsLayer = true
        clip.layer?.cornerCurve = .continuous
        // Said outright: on 27.2 AppKit turned masking on by itself once a radius
        // above 0 was set on this layer, and a clip that masks only then is square
        // until the first corner.
        clip.layer?.masksToBounds = true
        card.addSubview(clip)
        clip.addSubview(pane)

        resolveFill()
    }

    required init?(coder: NSCoder) { fatalError("ShellContentView is built in code") }

    // MARK: - fill

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveFill()
    }

    /// The fill is a colour of one appearance, so it is resolved here and again
    /// when the appearance changes, not in `layout()`.
    private func resolveFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    // MARK: - the corner

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window !== journalWindow {
            journal = WindowCorner.Journal()
            journalWindow = window
        }
        needsLayout = true
    }

    /// Asks for a layout, so the corner is read again. For whoever gives the
    /// window a toolbar: on 27.2 the assignment left this view's `needsLayout`
    /// false (measured, a window never ordered in), and below macOS 27 there is
    /// no probe to notice the corner moved.
    func barWasAttached() {
        needsLayout = true
    }

    /// Sets the card's and the clip's radius from the window's corner, only when
    /// the corner differs from the one applied. It writes no line: the journal is
    /// written in `layout()`, after this, and only for a view that has a window,
    /// so a corner handed in directly with no window writes nothing, and a layout
    /// in a window writes once per change, up to `WindowCorner.Journal.cap` lines.
    func apply(_ corner: WindowCorner) {
        guard corner != applied else { return }
        applied = corner
        let radius = ShellGeometry.cardRadius(windowRadius: corner.radius)
        card.layer?.cornerRadius = radius
        clip.layer?.cornerRadius = radius
    }

    /// The probe's largest corner, nil where there is no probe, no window or no
    /// answer. Outside a window the probe answers 0.0, measured on 27.2, which
    /// is not a corner: it must not reach `read` as one. Not-a-number is read as
    /// "did not answer" by `read`.
    private var publicReading: CGFloat? {
        guard window != nil else { return nil }
        if #available(macOS 27.0, *), let probe, let radii = probe.effectiveCornerRadii {
            return max(radii.topLeft, radii.topRight, radii.bottomLeft, radii.bottomRight)
        }
        return nil
    }

    // MARK: - layout

    override func layout() {
        super.layout()

        glass.frame = bounds
        probe?.frame = bounds

        let frame = ShellGeometry.cardFrame(in: bounds.size, sidebarWidth: sidebarWidth)
        card.frame = frame
        clip.frame = card.bounds
        pane.frame = clip.bounds
        sidebar.frame = CGRect(x: 0, y: 0, width: max(frame.minX, 0), height: bounds.height)
        if frame != lastTold {
            lastTold = frame
            cardMoved(frame)
        }

        let reading = publicReading
        let chrome = WindowCorner.Chrome(hasToolbar: window?.toolbar != nil, systemMajor: system.majorVersion)
        let corner = WindowCorner.read(publicReading: reading, from: window, chrome: chrome)
        apply(corner)
        writeLine(corner, publicReading: reading, chrome: chrome)
    }

    private func writeLine(_ corner: WindowCorner, publicReading: CGFloat?, chrome: WindowCorner.Chrome) {
        guard let window else { return }
        let system = system
        guard let line = journal.line(for: corner, {
            WindowCorner.logLine(corner, publicReading: publicReading, chrome: chrome, window: window,
                                 override: UserDefaults.standard.object(forKey: WindowCorner.overrideKey),
                                 system: system)
        }) else { return }
        switch corner.rung {
        case .publicAPI, .windowSelector: HelmLog.shared.info(WindowCorner.logCategory, line)
        case .guess, .none: HelmLog.shared.warn(WindowCorner.logCategory, line)
        }
    }
}

/// Reports the window's corner: a view with a concentric corner, full bleed,
/// that answers no click. When its radii change it asks the shell for a layout.
@available(macOS 27.0, *)
private final class CornerProbe: NSView {
    override var cornerConfiguration: NSViewCornerConfiguration? { .corners(radius: .containerConcentric) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        superview?.needsLayout = true
    }
}
