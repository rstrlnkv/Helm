import AppKit
import HelmRuntime
import HelmUI

/// **The shell's content view: the window's ground by the look, the sidebar on it,
/// and the opaque card inset from the window's edge, with the pane clipped inside
/// the card to the card's corners.** Every frame comes from `ShellGeometry`; the
/// view holds no radius of its own, it cuts the card from the window's corner and
/// applies it to the card and to the clip in one place, `apply(_:)`.
///
/// **The ground is the look's** (`HelmBarAppearance`): Flat is the system's flat
/// sidebar material behind the window, `.sidebar` and `.followsWindowActiveState`,
/// Glass is `NSGlassEffectView`. Both are full bleed and one is visible
/// (`showGround(_:)`); a live change of the look swaps them at once, without an
/// animation, as the header row's look does.
///
/// **The corner.** On macOS 27 it is the token `HelmRadius.window`, decided once
/// in `init`: nothing is read and no line is written. On macOS 26 it is
/// `WindowCorner`'s reading in `layout()` (not testable here, no such machine).
///
/// Subviews, bottom to top: the flat ground, the glass ground, the sidebar, as
/// wide as the card's x so the two cannot part; the card, and inside it the clip,
/// and inside that the pane; last, the window buttons' capsule
/// (`ShellWindowButtons`), above everything and hit by nothing.
/// The card carries the fill and the shadow and never masks, so the shadow is
/// not cut; the clip masks, so the pane's band does not run square to the
/// window's corner. The sidebar and the pane are handed in. This view names no page and builds no toolbar; the settings window has none.
///
/// **The clip holds the pane alone, and the pane starts where AppKit's strip ends:** this view adds nothing
/// to the pane's top safe-area inset; the pane's own hosting controller takes none from the title bar
/// (`safeAreaRegions = []`, `SettingsWindow`). It neither writes the
/// window buttons' frames nor reads them; `ShellWindowButtons` does.
///
/// **One reader on macOS 26.** `layout()` reads the corner, whoever asked for the layout:
/// AppKit on a resize, `viewDidMoveToWindow`, `sidebarWidth`'s setter (every write), and
/// `ShellWindowButtons` (full screen, a button's frame). Events only ask (`needsLayout = true`).
///
/// **The fold is the width travelling.** `fold(to:animated:)` starts a travel and writes no frame: it keeps
/// the fold it was asked for, asks for a layout and starts `foldLink`. The first call of the
/// link with a finite timestamp only records it; each other one writes `sidebarWidth`, from the time since that
/// first, or the target itself when the timestamp is not finite, is below the last or reaches the end, and does
/// nothing else, every write asks for a layout, and `layout()` places the card and the pane from the
/// width standing then. The rail's placement of the buttons is asked for
/// from the turn of the flip and given up when the target width is written, which ends the travel and the link.
///
/// **Not-a-number.** A sidebar width that is not a number is `ShellGeometry`'s
/// business (`cardFrame` reads it as 0), and the sidebar's frame is cut from the
/// card's x, so it is finite whenever the card's is. A radius the window
/// answers as not-a-number is a rung that did not answer
/// (`WindowCorner.read`), never a radius.
@MainActor
final class ShellContentView: NSView {

    /// The sidebar's width; the view does not clamp it (`ShellGeometry.railWidth` is
    /// outside `ShellGeometry.sidebarRange`). Setting it asks for a layout, and writing the
    /// width a fold is travelling to ends that fold's claim on the buttons (`foldTarget`).
    ///
    /// `layout()` places everything from the value standing. Every write other than the link's moves the width at
    /// once and ends the travel only when it writes the target or comes through `fold(to:animated:)` as a cut.
    private var sidebarWidth: CGFloat = ShellGeometry.defaultSidebarWidth {
        didSet {
            if sidebarWidth == foldTarget { endTravel() }
            needsLayout = true
        }
    }

    /// What a fold asked for: the width it starts from, the width it ends at and for how long.
    private struct Fold: Equatable {
        let from: CGFloat
        let to: CGFloat
        let duration: TimeInterval
    }

    /// The fold's source of frames: the display's own.
    private let foldLink = DisplayFoldLink()

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
    private var foldTarget: CGFloat? { travel?.fold.to }

    /// Whether `layout()` gives the window's buttons the rail's placement: a fold is travelling (`foldTarget`) or
    /// the width standing is the rail's (`ShellGeometry.isRail(sidebarWidth:)`). The one expression `layout()`
    /// places the buttons by.
    var buttonsStandInRail: Bool { foldTarget != nil || ShellGeometry.isRail(sidebarWidth: sidebarWidth) }

    /// Carries the fill, the radius and the shadow; never masks.
    private let card = NSView()

    /// Masks at the card's radius; holds the pane.
    private let clip = NSView()

    private let sidebar: NSView
    private let pane: NSView

    /// The Flat look's ground: the system's flat material behind the window (probe: it follows the window's
    /// activity by itself).
    private let flat = NSVisualEffectView()
    private let glass = NSGlassEffectView()
    /// The look the ground wears, read when it changes (`.helmBarAppearanceChanged`), never kept.
    private let look: () -> HelmBarAppearance
    private let buttons = ShellWindowButtons()
    /// The card's radius as last applied.
    private var applied: CGFloat?
    private var journal = WindowCorner.Journal()

    /// The window the journal was started for. Weak, so a freed window cannot be
    /// mistaken for a new one that reuses its address: a view taken out and put
    /// back into the same window keeps its journal and its bound, and only a
    /// different window starts a new one.
    private weak var journalWindow: NSWindow?
    /// Swaps the ground when the look changes; removed in `deinit`, which Swift 6 treats as nonisolated
    /// even on a `@MainActor` class.
    nonisolated(unsafe) private var lookObserver: NSObjectProtocol?
    private let system = ProcessInfo.processInfo.operatingSystemVersion

    /// Whether the corner is the token's (macOS 27 and later) and not read.
    private var cornerIsTheToken: Bool { system.majorVersion >= 27 }

    override var isFlipped: Bool { true }

    /// The views are held for as long as this view lives.
    init(sidebar: NSView, pane: NSView, look: @escaping () -> HelmBarAppearance) {
        self.sidebar = sidebar
        self.pane = pane
        self.look = look
        super.init(frame: .zero)

        flat.material = .sidebar
        flat.blendingMode = .behindWindow
        flat.state = .followsWindowActiveState
        glass.style = .regular
        addSubview(flat)
        addSubview(glass)
        showGround(look())
        lookObserver = NotificationCenter.default.addObserver(
            forName: .helmBarAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.showGround(self.look()) } }
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

        if cornerIsTheToken { apply(ShellGeometry.cardRadius(windowRadius: HelmRadius.window)) }
        resolveFill()
    }

    required init?(coder: NSCoder) { fatalError("ShellContentView is built in code") }

    deinit {
        if let lookObserver { NotificationCenter.default.removeObserver(lookObserver) }
    }

    // MARK: - the ground

    /// One ground is visible: the look's. An instant swap; the cases are named so a third look cannot be
    /// forgotten here.
    private func showGround(_ look: HelmBarAppearance) {
        switch look {
        case .flat:
            flat.isHidden = false
            glass.isHidden = true
        case .liquidGlass:
            flat.isHidden = true
            glass.isHidden = false
        }
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
        if let window, window !== journalWindow {
            journal = WindowCorner.Journal()
            journalWindow = window
        }
        needsLayout = true
    }

    /// Sets the card's and the clip's radius, only when it differs from the one applied. It writes no line:
    /// the journal is written in `layout()`, after this, and only for a view that has a window, so a layout
    /// in a window writes once per change, up to `WindowCorner.Journal.cap` lines.
    private func apply(_ radius: CGFloat) {
        guard radius != applied else { return }
        applied = radius
        card.layer?.cornerRadius = radius
        clip.layer?.cornerRadius = radius
    }

    // MARK: - the fold

    /// **Brings the sidebar to `width`: one travel of the width along `HelmMotion.interfaceCurve` for
    /// `HelmMotion.sidebarFoldDuration` when `animated`, the width standing is finite and differs from `width`, and
    /// Reduce Motion is off; a cut otherwise, except a `width` that is not finite, which is refused (below).** Returns whether a travel was started. It writes no frame:
    /// `layout()` places the card, the sidebar and the buttons from the width standing, so there
    /// is one writer of frames. A cut is a plain write, ends a travel in flight and stops its link, so a call
    /// of the link that is already on its way finds nothing to move. A `width` that is not finite (not-a-number or an infinity) is a caller's
    /// defect and is refused whole (nothing written, false): the stored width never gets
    /// here unclamped. The fold itself and the lights giving way to the capsule are not seen on a screen.
    @discardableResult
    func fold(to width: CGFloat, animated: Bool) -> Bool {
        guard width.isFinite else { return false }
        guard animated, sidebarWidth.isFinite, sidebarWidth != width,
              HelmMotion.travels(reduceMotion: HelmMotion.reduceMotion) else {
            endTravel()
            sidebarWidth = width
            return false
        }
        let fold = Fold(from: sidebarWidth, to: width, duration: HelmMotion.sidebarFoldDuration)
        travel = Travel(fold: fold)
        needsLayout = true
        foldLink.start(on: self) { [weak self] timestamp in self?.tick(timestamp) }
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

        flat.frame = bounds
        glass.frame = bounds

        let frame = ShellGeometry.cardFrame(in: bounds.size, sidebarWidth: sidebarWidth)
        card.frame = frame
        clip.frame = card.bounds
        pane.frame = clip.bounds
        sidebar.frame = CGRect(x: 0, y: 0, width: max(frame.minX, 0), height: bounds.height)
        let rail = buttonsStandInRail
        buttons.place(rail: rail)

        guard !cornerIsTheToken else { return }
        let corner = WindowCorner.read(from: window, systemMajor: system.majorVersion)
        apply(ShellGeometry.cardRadius(windowRadius: corner.radius))
        writeLine(corner)
    }

    /// Hands the window's activity to the buttons' capsule, whose dots are coloured only while it is active
    /// and the system's tint is not Graphite.
    func setWindowAppearsActive(_ active: Bool) {
        buttons.setWindowAppearsActive(active)
    }

    private func writeLine(_ corner: WindowCorner) {
        guard let window else { return }
        let system = system
        guard let line = journal.line(for: corner, {
            WindowCorner.logLine(corner, window: window,
                                 override: UserDefaults.standard.object(forKey: WindowCorner.overrideKey),
                                 system: system)
        }) else { return }
        switch corner.rung {
        case .windowSelector: HelmLog.shared.info(WindowCorner.logCategory, line)
        case .guess, .none: HelmLog.shared.warn(WindowCorner.logCategory, line)
        }
    }
}
