import AppKit
import HelmRuntime
import HelmUI

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
/// and inside it the clip, and inside that the pane; last, the window buttons' capsule
/// (`ShellWindowButtons`), above everything and hit by nothing.
/// The card carries the fill and the shadow and never masks, so the shadow is
/// not cut; the clip masks, so the pane's band does not run square to the
/// window's corner. The sidebar and the pane are handed in, and so is `cardMoved`, called each time the card moves or the buttons change between the rail's
/// placement and the other (`buttonsStandInRail`); this view names no page and builds no toolbar; of the
/// window's toolbar it asks only whether there is one.
///
/// **The clip holds the pane alone, and the pane starts where AppKit's strip ends:** this view adds nothing
/// to the pane's top safe-area inset, which stays AppKit's under the window's toolbar. It neither writes the
/// window buttons' frames nor reads them; `ShellWindowButtons` does.
///
/// **One reader.** `layout()` reads the corner, whoever asked for the layout:
/// AppKit on a resize, the probe on macOS 27 when its radii change,
/// `viewDidMoveToWindow`, the window's occlusion notification,
/// `sidebarWidth`'s setter (every write), `barWasAttached()` and `ShellWindowButtons` (full screen, a button's frame). Events only ask (`needsLayout = true`).
///
/// **The fold is the width travelling.** `fold(to:animated:)` starts a travel and writes no frame: it keeps
/// the fold it was asked for, asks for a layout, starts `foldLink` and then tells `onFold`. The first call of the
/// link with a finite timestamp only records it; each other one writes `sidebarWidth`, from the time since that
/// first, or the target itself when the timestamp is not finite, is below the last or reaches the end, and does
/// nothing else, every write asks for a layout, and `layout()` places the card and the pane from the
/// width standing then. The rail's placement of the buttons is asked for
/// from the turn of the flip and given up when the target width is written, which ends the travel and the link.
///
/// **Not-a-number.** A sidebar width that is not a number is `ShellGeometry`'s
/// business (`cardFrame` reads it as 0), and the sidebar's frame is cut from the
/// card's x, so it is finite whenever the card's is. A radius the probe or the
/// window answers as not-a-number is a rung that did not answer
/// (`WindowCorner.read`), never a radius.
@MainActor
final class ShellContentView: NSView {

    /// The sidebar's width; the view does not clamp it (`ShellGeometry.railWidth` is
    /// outside `ShellGeometry.sidebarRange`). Setting it asks for a layout, and writing the
    /// width a fold is travelling to ends that fold's claim on the buttons (`foldTarget`).
    ///
    /// `@objc dynamic` so that a key-value observer sees every write, which is how a row counts the writes of a
    /// travel: one for each call of the link that moves the width, none for the call that only records the start.
    /// `layout()` places everything from the value standing. Every write other than the link's moves the width at
    /// once and ends the travel only when it writes the target or comes through `fold(to:animated:)` as a cut.
    @objc dynamic var sidebarWidth: CGFloat = ShellGeometry.defaultSidebarWidth {
        didSet {
            if sidebarWidth == foldTarget { endTravel() }
            needsLayout = true
        }
    }

    /// What a fold asked for: the width it starts from, the width it ends at and for how long.
    struct Fold: Equatable {
        let from: CGFloat
        let to: CGFloat
        let duration: TimeInterval
    }

    /// Whether the system's Reduce Motion is on, asked when a fold would travel.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }

    /// The fold's source of frames: the display's own (`DisplayFoldLink`).
    var foldLink: any FoldLink = DisplayFoldLink()

    /// Told each fold the view starts a travel for, never a cut, after the link is started: a listener that cuts
    /// inside its call stops the link it finds running.
    var onFold: (Fold) -> Void = { _ in }

    /// A fold in flight: what it was asked for and the link's timestamps. `start` is the timestamp of the first
    /// call of the link after the flip and `last` the latest one that moved the width; both are nil until that
    /// first call, which only records them.
    private struct Travel {
        let fold: Fold
        var start: CFTimeInterval?
        var last: CFTimeInterval?
    }

    private var travel: Travel?

    /// The width a fold in flight is travelling to, nil when none is. While it is set the buttons keep
    /// the rail's placement (`layout()`). It is cleared by the write of the target itself (`sidebarWidth`),
    /// by a cut (`fold(to:animated:)`), and by the view's move to another window (`viewDidMoveToWindow`),
    /// which finishes the fold; each of them ends the travel and stops the link.
    /// If none of them came, the buttons would stay in the rail's placement at an expanded width.
    var foldTarget: CGFloat? { travel?.fold.to }

    /// Whether `layout()` gives the window's buttons the rail's placement: a fold is travelling (`foldTarget`) or
    /// the width standing is the rail's (`ShellGeometry.isRail(sidebarWidth:)`). The one expression `layout()`
    /// places the buttons by and tells `cardMoved` by.
    var buttonsStandInRail: Bool { foldTarget != nil || ShellGeometry.isRail(sidebarWidth: sidebarWidth) }

    /// Carries the fill, the radius and the shadow; never masks.
    let card = NSView()

    /// Masks at the card's radius; holds the pane.
    let clip = NSView()

    private let sidebar: NSView
    private let pane: NSView
    private let cardMoved: (CGRect) -> Void

    /// What `cardMoved` was last called for: the card's frame and the placement of the buttons then.
    private struct Told: Equatable {
        let card: CGRect
        let rail: Bool
    }

    private var lastTold: Told?
    private let glass = NSGlassEffectView()
    private let buttons = ShellWindowButtons()
    private var applied: WindowCorner?
    private var journal = WindowCorner.Journal()

    /// The window the journal was started for. Weak, so a freed window cannot be
    /// mistaken for a new one that reuses its address: a view taken out and put
    /// back into the same window keeps its journal and its bound, and only a
    /// different window starts a new one.
    private weak var journalWindow: NSWindow?
    /// Asks for a layout when the window's occlusion state changes; removed
    /// whenever the view leaves a window, and in `deinit`. Read in `deinit`,
    /// which Swift 6 treats as nonisolated even on a `@MainActor` class.
    nonisolated(unsafe) private var shownObserver: NSObjectProtocol?
    private let system = ProcessInfo.processInfo.operatingSystemVersion

    /// Nil below macOS 27, where there is no public reading.
    private var probe: NSView?

    override var isFlipped: Bool { true }

    /// The views and the closure are held for as long as this view lives: a receiver that owns this
    /// view captures itself weakly. `cardMoved` is called from `layout()` itself, in the turn that moved the card or
    /// changed `buttonsStandInRail`, after the card is placed and before the buttons are, so a receiver that
    /// reads `buttonsStandInRail` reads the placement this layout gives them; what it does must not assign
    /// `window.toolbar`. A layout in which both stand as they did calls nothing.
    init(sidebar: NSView, pane: NSView, cardMoved: @escaping (CGRect) -> Void = { _ in }) {
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
        addSubview(buttons.capsule)

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

    deinit {
        if let shownObserver { NotificationCenter.default.removeObserver(shownObserver) }
    }

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
        buttons.attach(to: window)
        if let foldTarget { fold(to: foldTarget, animated: false) }
        if let shownObserver { NotificationCenter.default.removeObserver(shownObserver) }
        shownObserver = nil
        if let window {
            // Assumed, not measured: that ordering a window in posts this
            // notification. It is listened for because a borderless window's
            // corner is 0 before and after it is shown, so the probe's radii do
            // not change and nothing else would ask for the layout that takes
            // its zero.
            shownObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsLayout = true }
            }
        }
        if let window, window !== journalWindow {
            journal = WindowCorner.Journal()
            journalWindow = window
        }
        needsLayout = true
    }

    /// How many times the window has told this view it took a bar (`barWasAttached()`). `needsLayout` cannot
    /// tell that call from the other causes that set it, so the count is what shows the call was made.
    private(set) var barAttachments = 0

    /// Asks for a layout, so the corner is read again and the buttons are placed again. For whoever gives the
    /// window a toolbar. Whether the request is needed is not measured: in a window never ordered in, on
    /// macOS 27.2, this view's `needsLayout` was true right after an assignment with this call left out, and
    /// what set it is not found. Assumed, not measured: that an assignment moves the window buttons. Below
    /// macOS 27 there is no probe to notice the corner moved. The calls taken are counted in `barAttachments`.
    func barWasAttached() {
        barAttachments += 1
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
    /// is not a corner: it must not reach `read` as one. A window built and laid
    /// out and not shown answered 0.0 too, so a zero from it is dropped
    /// (`WindowCorner.publicAnswer`) and a lower rung answers while it is not
    /// shown. The window's occlusion notification asks for a layout, which reads
    /// again; that showing the window posts one is assumed, not measured.
    /// Not-a-number is read as "did not answer" by `read`.
    private var publicReading: CGFloat? {
        guard let window else { return nil }
        if #available(macOS 27.0, *), let probe, let radii = probe.effectiveCornerRadii {
            return WindowCorner.publicAnswer(max(radii.topLeft, radii.topRight, radii.bottomLeft, radii.bottomRight),
                                             windowIsShown: window.isVisible || window.isMiniaturized)
        }
        return nil
    }

    // MARK: - the fold

    /// **Brings the sidebar to `width`: one travel of the width along `HelmMotion.interfaceCurve` for
    /// `HelmMotion.sidebarFoldDuration` when `animated`, the width standing is finite and differs from `width`, and
    /// Reduce Motion is off; a cut otherwise, except a `width` that is not finite, which is refused (below).** Returns whether a travel was started. It writes no frame:
    /// `layout()` places the card, the sidebar and the buttons from the width standing, so there
    /// is one writer of frames. A cut is a plain write, ends a travel in flight and stops its link, so a call
    /// of the link that is already on its way finds nothing to move. A `width` that is not finite (not-a-number or an infinity) is a caller's
    /// defect and is refused whole (nothing written, nothing heard, false): the stored width never gets
    /// here unclamped. The fold itself and the lights giving way to the capsule are not seen on a screen.
    @discardableResult
    func fold(to width: CGFloat, animated: Bool) -> Bool {
        guard width.isFinite else { return false }
        guard animated, sidebarWidth.isFinite, sidebarWidth != width,
              HelmMotion.travels(reduceMotion: reducesMotion()) else {
            endTravel()
            sidebarWidth = width
            return false
        }
        let fold = Fold(from: sidebarWidth, to: width, duration: HelmMotion.sidebarFoldDuration)
        travel = Travel(fold: fold)
        needsLayout = true
        foldLink.start(on: self) { [weak self] timestamp in self?.tick(timestamp) }
        onFold(fold)
        return true
    }

    /// Clears the travel in flight, if any, and stops the link. A second fold in flight replaces the travel in
    /// `fold(to:animated:)`, and the link's `start` stops the earlier calls.
    private func endTravel() {
        travel = nil
        foldLink.stop()
    }

    /// One call of the link: a plain write of `sidebarWidth` and nothing else. The first call only records
    /// where the clock stands, so the progress is measured from the link's own first timestamp and never from
    /// a time read before the link ran. A timestamp that is not finite, one below the last, and one that
    /// carries the time to the end of the fold land on the target by one write, which ends the travel.
    private func tick(_ timestamp: CFTimeInterval) {
        guard let travel else { return }
        let fold = travel.fold
        guard timestamp.isFinite else { sidebarWidth = fold.to; return }
        guard let start = travel.start, let last = travel.last else {
            self.travel?.start = timestamp
            self.travel?.last = timestamp
            return
        }
        let fraction = (timestamp - start) / fold.duration
        guard timestamp >= last, fraction < 1 else { sidebarWidth = fold.to; return }
        self.travel?.last = timestamp
        sidebarWidth = fold.from + (fold.to - fold.from) * CGFloat(HelmMotion.interfaceProgress(at: fraction))
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
        let rail = buttonsStandInRail
        let told = Told(card: frame, rail: rail)
        if told != lastTold {
            lastTold = told
            cardMoved(frame)
        }
        buttons.place(rail: rail)

        let reading = publicReading
        let chrome = WindowCorner.Chrome(hasToolbar: window?.toolbar != nil, systemMajor: system.majorVersion)
        let corner = WindowCorner.read(publicReading: reading, from: window, chrome: chrome)
        apply(corner)
        writeLine(corner, publicReading: reading, chrome: chrome)
    }

    /// Hands the window's activity to the buttons' capsule, whose dots are coloured only while it is active
    /// and the system's tint is not Graphite.
    func setWindowAppearsActive(_ active: Bool) {
        buttons.setWindowAppearsActive(active)
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
