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
/// and inside it the clip, and inside that the pane and, above it, the page bar; last, the window
/// buttons' capsule (`ShellWindowButtons`), above everything and hit by nothing.
/// The card carries the fill and the shadow and never masks, so the shadow is
/// not cut; the clip masks, so the pane's band does not run square to the
/// window's corner. The sidebar, the pane and the bar are handed in; this view
/// names no page and builds no toolbar; of the window's toolbar it asks only
/// whether there is one.
///
/// **The bar stands at the top of the clip, full width, `ShellBarLayout.height`
/// high, and the pane starts under it:** `layout()` adds to the pane's own top
/// safe-area inset what the bar needs beyond it, so the pane's top inset, which
/// SwiftUI reads, is the bar's height. It hands the bar the obstacle `ShellWindowButtons` answers (the closed
/// capsule in the rail, the three buttons otherwise) and its `reach`, both in the bar's coordinates. This
/// view and the bar neither write the window buttons' frames nor read them; that owner does.
///
/// **One reader.** `layout()` reads the corner, whoever asked for the layout:
/// AppKit on a resize, the probe on macOS 27 when its radii change,
/// `viewDidMoveToWindow`, the window's occlusion notification,
/// `sidebarWidth`'s setter (every write) and `ShellWindowButtons` (full screen, a button's frame). Events only ask (`needsLayout = true`).
///
/// **The fold is the width travelling.** `fold(to:animated:)` asks AppKit to run `sidebarWidth` and writes
/// no frame: besides the width it sets only `foldTarget` and its run counter (`foldRun`), and asks for a layout. AppKit's animator writes the
/// width while a run lasts, every write asks for a layout, and `layout()` places the card, the bar and the
/// pane from the width standing then. The rail's placement of the buttons is asked for from the turn of the
/// flip and given up when the target width is written or the run completes.
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
    /// `@objc dynamic` so that `animator()` can run it: AppKit's animator writes it while a fold
    /// lasts, and `layout()` places everything from the value standing then. `fold(to:animated:)` is the caller that
    /// asks for a run; every other write is a cut.
    @objc dynamic var sidebarWidth: CGFloat = ShellGeometry.defaultSidebarWidth {
        didSet {
            if sidebarWidth == foldTarget { foldTarget = nil }
            needsLayout = true
        }
    }

    /// What a fold asked for: the width it starts from, the width it ends at and for how long.
    struct Fold: Equatable {
        let from: CGFloat
        let to: CGFloat
        let duration: TimeInterval
    }

    /// Whether the system's Reduce Motion is on, asked when a fold would travel; a test hands in its own answer.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }

    /// Told each fold the view asks AppKit for, never a cut.
    var onFold: (Fold) -> Void = { _ in }

    /// The width a fold in flight is travelling to, nil when none is. While it is set the buttons keep
    /// the rail's placement (`layout()`). It is cleared by the write of the target itself (`sidebarWidth`),
    /// by a cut (`fold(to:animated:)`), by the run's completion when it is still that run's (`foldRun`),
    /// and by the view's move to another window (`viewDidMoveToWindow`), which finishes the fold.
    /// If none of them came, the buttons would stay in the rail's placement at an expanded width.
    private(set) var foldTarget: CGFloat?

    /// Counts the runs and cuts, so a completion that arrives after a later one is ignored.
    private var foldRun = 0

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "sidebarWidth" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    /// Carries the fill, the radius and the shadow; never masks.
    let card = NSView()

    /// Masks at the card's radius; holds the pane and, above it, the page bar.
    let clip = NSView()

    private let sidebar: NSView
    private let pane: NSView
    private let bar: ShellPageBarView
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

    /// The three views are held for as long as this view lives.
    init(sidebar: NSView, pane: NSView, bar: ShellPageBarView) {
        self.sidebar = sidebar
        self.pane = pane
        self.bar = bar
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
        clip.addSubview(bar)

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

    /// **Brings the sidebar to `width`: one run of the width on `HelmMotion.interfaceCurve` for
    /// `HelmMotion.sidebarFoldDuration` when `animated`, the width standing is finite and differs from `width`, and
    /// Reduce Motion is off; a cut otherwise, except a `width` that is not finite, which is refused (below).** Returns whether a run was asked for. It writes no frame:
    /// `layout()` places the card, the sidebar, the bar and the buttons from the width standing, so there
    /// is one writer of frames. A cut is a plain write and drops the fold's claim (`foldTarget`); no row
    /// holds that AppKit's run in flight then stops writing. A `width` that is not finite (not-a-number or an infinity) is a caller's
    /// defect and is refused whole (nothing written, nothing heard, false): the stored width never gets
    /// here unclamped. The fold itself and the lights giving way to the capsule are not seen on a screen.
    @discardableResult
    func fold(to width: CGFloat, animated: Bool) -> Bool {
        guard width.isFinite else { return false }
        foldRun += 1
        guard animated, sidebarWidth.isFinite, sidebarWidth != width,
              HelmMotion.travels(reduceMotion: reducesMotion()) else {
            foldTarget = nil
            sidebarWidth = width
            return false
        }
        let run = foldRun
        let fold = Fold(from: sidebarWidth, to: width, duration: HelmMotion.sidebarFoldDuration)
        foldTarget = width
        needsLayout = true
        onFold(fold)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fold.duration
            context.timingFunction = HelmMotion.interfaceCurve
            animator().sidebarWidth = width
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.foldRun == run else { return }
                self.foldTarget = nil
                self.needsLayout = true
            }
        })
        return true
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
        let obstacle = buttons.place(rail: foldTarget != nil || ShellGeometry.isRail(sidebarWidth: sidebarWidth))
        let reach = buttons.reach
        placeBar(buttons: obstacle.isNull ? .null : convert(obstacle, to: bar),
                 reach: reach.isNull ? .null : convert(reach, to: bar))

        let reading = publicReading
        let chrome = WindowCorner.Chrome(hasToolbar: window?.toolbar != nil, systemMajor: system.majorVersion)
        let corner = WindowCorner.read(publicReading: reading, from: window, chrome: chrome)
        apply(corner)
        writeLine(corner, publicReading: reading, chrome: chrome)
    }

    /// The bar at the clip's top (the clip is not flipped, so its top is `maxY`), full width; the pane's
    /// additional top inset is what the bar's height needs beyond the safe area the pane has of its own,
    /// written only when it differs.
    private func placeBar(buttons: CGRect, reach: CGRect) {
        let height = min(ShellBarLayout.height, max(clip.bounds.height, 0))
        bar.frame = CGRect(x: 0, y: clip.bounds.maxY - height, width: clip.bounds.width, height: height)
        bar.place = ShellPageBarView.Place(buttons: buttons, reach: reach)
        let own = pane.safeAreaInsets.top - pane.additionalSafeAreaInsets.top
        let wanted = max(0, ShellBarLayout.height - own)
        if pane.additionalSafeAreaInsets.top != wanted { pane.additionalSafeAreaInsets.top = wanted }
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
