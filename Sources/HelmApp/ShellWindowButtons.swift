import AppKit
import HelmUI

/// **The one owner of the window's three buttons: where they stand, whether they show, and the capsule
/// that stands in for them in the rail.** Among the `Shell*` files nothing else writes their frames or
/// reads `standardWindowButton`; `SettingsToolbar.opensBarMenu(_:)` reads them too, to keep its menu off them.
///
/// Expanded, the buttons stand `ShellGeometry.buttonShift` right and `buttonDrop` down of where AppKit
/// puts them (their *home*). In the rail they keep their row and stand under a closed capsule of three
/// dots, at alpha 0; the pointer in the capsule's hover zone opens the capsule around them and shows the
/// real buttons, and the capsule answers no hit, so a press there is meant to reach them. Not measured: a
/// real pointer, the hover glyphs, a click and the zoom button's menu on a button that was at alpha 0. The
/// obstacle the page bar is handed is the closed capsule's frame in the rail, the buttons' union
/// otherwise, and never depends on hover, so nothing in the bar moves when the capsule opens.
///
/// **Held by origin, on both axes.** Measured: AppKit puts the buttons back at its own origins (below).
/// Assumed, not measured: that it lays them out from the titlebar's top, so that a change of the titlebar's
/// height would move a button offset on one axis only.
/// Every placement writes each button's origin: its home plus the offset. A write to a button's origin that
/// this object did not make and that reaches it (`NSView.frameDidChangeNotification`, an origin other than
/// the one written here) is taken for AppKit's: it becomes the new home and is answered in the same turn
/// with the placement. The rows make that write by hand. That answer does not hold every write AppKit makes:
/// the one inside an alpha write, below, left the zoom button at AppKit's origin, and why the answer missed
/// it is not measured. AppKit writing an origin in a shown window is not measured. This object's own writes
/// are told by `isPlacing` and by their value, so answering cannot loop. Measured in an unshown window: a
/// write to a button's alpha makes AppKit put the buttons back at its own origins (the rows of
/// `TheWindowButtonsStayWhereHelmPutThemTests` rest on it: the fold row goes red without the answer). So
/// every placement, and every hover change made without an animation, ends by putting back each button that
/// stands elsewhere, after the last alpha write. An animated change does it once at once and once more when
/// the animation completes; no row reaches that, the rows run with Reduce Motion on.
///
/// **Hover is an event-stream value.** `isOpen` is set by the tracking area's enter and exit, cleared by
/// leaving the rail, by full screen and by `attach(to: nil)`, and read again from the pointer's place in
/// every `place(rail:)` of a visible window, so an exit that never came is healed by the next layout.
///
/// In full screen no frame is written, the buttons' alpha goes back to 1 and the capsule is hidden: the
/// buttons are the system's there. Not run in a full-screen window.
/// Reduce Motion changes the capsule's size in the same turn, without an animation. `attach(to:)` stops
/// every observer; `deinit` removes the notification tokens.
@MainActor
final class ShellWindowButtons {

    /// The capsule's three rectangles in the content's coordinates.
    struct Capsule: Equatable {
        var closed: CGRect
        var open: CGRect
        var hoverZone: CGRect
    }

    /// Where Helm holds the buttons for one home.
    struct Placement: Equatable {
        /// From AppKit's home; x right, y down.
        var offset: CGSize
        /// The union where Helm holds the three buttons.
        var buttons: CGRect
        /// Nil: expanded, or a rail whose capsule cannot open onto the buttons (their home above the content).
        var capsule: Capsule?
    }

    /// The placement for `home`, the union of the three buttons where AppKit puts them in the content's
    /// coordinates. Nil when `home` is nil, empty, null or not a finite place: nothing is moved or hidden.
    nonisolated static func placement(home: CGRect?, rail: Bool) -> Placement? {
        guard let home, !home.isNull, !home.isInfinite, home.width > 0, home.height > 0,
              [home.minX, home.minY, home.width, home.height].allSatisfy(\.isFinite) else { return nil }
        let offset = ShellGeometry.buttonsOffset(home: home, rail: rail)
        let buttons = home.offsetBy(dx: offset.width, dy: offset.height)
        guard rail, home.minY >= 0 else { return Placement(offset: offset, buttons: buttons, capsule: nil) }
        return Placement(offset: offset, buttons: buttons,
                         capsule: Capsule(closed: ShellGeometry.capsuleClosedFrame(buttons: buttons),
                                          open: ShellGeometry.capsuleOpenFrame(buttons: buttons),
                                          hoverZone: ShellGeometry.capsuleHoverZone(buttons: buttons)))
    }

    /// What the page bar must clear: the closed capsule when there is one, else the buttons' union; `.null`
    /// for no placement. The open capsule never enters it.
    nonisolated static func obstacle(_ placement: Placement?) -> CGRect {
        guard let placement else { return .null }
        return placement.capsule?.closed ?? placement.buttons
    }

    /// The hover-zone view: the plate and three dots. It is the content view's topmost subview and answers
    /// no click.
    var capsule: NSView { view }

    /// Whether the Reduce Motion setting is on; read at every change, set by tests.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }

    /// Whether the capsule is open, the real buttons showing.
    private(set) var isOpen = false

    /// The plate in the capsule's coordinates.
    var plateFrame: CGRect { view.plate.frame }

    /// The real buttons' union now, in the capsule's superview's coordinates; `.null` without a window,
    /// a superview or buttons. Read by tests.
    var buttonsFrame: CGRect {
        guard let window, let content = view.superview else { return .null }
        return Self.standardButtons(of: window).reduce(CGRect.null) {
            $0.union(content.convert($1.bounds, from: $1))
        }
    }

    private let view = CapsuleView()
    private weak var window: NSWindow?
    private var watched: [Watch] = []
    /// Read in `deinit`, which Swift 6 treats as nonisolated even on a `@MainActor` class.
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
    /// Where AppKit puts each button, and where this object last put it, in the button's superview.
    private var homes: [ObjectIdentifier: CGPoint] = [:]
    private var wanted: [ObjectIdentifier: CGPoint] = [:]
    private var isPlacing = false
    private var rail = false
    private var current: Placement?
    private var applied: Applied?

    private struct Watch {
        let button: NSButton
        let postedFrameChanges: Bool
    }

    /// What the capsule and the buttons last showed, so a layout that changes nothing writes nothing and
    /// cannot cut a running animation short.
    private struct Applied: Equatable {
        var plate: CGRect
        var dots: CGFloat
        var buttons: CGFloat
    }

    init() {
        view.isHidden = true
        view.onHover = { [weak self] inside in self?.hover(inside) }
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: - the window

    /// Starts watching `window`'s buttons and full screen. Every call, the same window and nil included, first
    /// stops every observer, puts the buttons back home at alpha 1 and hides the capsule; it places nothing,
    /// the next `place(rail:)` does.
    func attach(to window: NSWindow?) {
        detach()
        guard let window else { return }
        self.window = window
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.view.superview?.needsLayout = true }
            })
        }
        watch(Self.standardButtons(of: window))
    }

    private func detach() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        let list = watched
        watched = []
        isPlacing = true
        for item in list {
            item.button.postsFrameChangedNotifications = item.postedFrameChanges
            if let home = homes[ObjectIdentifier(item.button)] { item.button.setFrameOrigin(home) }
            item.button.alphaValue = 1
        }
        isPlacing = false
        homes = [:]
        wanted = [:]
        current = nil
        applied = nil
        isOpen = false
        view.isHidden = true
        window = nil
    }

    private static func standardButtons(of window: NSWindow) -> [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .filter { $0.window === window && $0.superview != nil && !$0.isHidden }
    }

    private func watch(_ buttons: [NSButton]) {
        for button in buttons where !watched.contains(where: { $0.button === button }) {
            watched.append(Watch(button: button, postedFrameChanges: button.postsFrameChangedNotifications))
            button.postsFrameChangedNotifications = true
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: button, queue: nil
            ) { [weak self, weak button] _ in
                MainActor.assumeIsolated {
                    if let button { self?.frameChanged(button) }
                }
            })
        }
    }

    /// A button's frame changed. Its origin where this object put it is this object's own write; any other
    /// is taken for AppKit's, so it becomes the button's home and the placement is applied again.
    private func frameChanged(_ button: NSButton) {
        guard !isPlacing else { return }
        let id = ObjectIdentifier(button)
        if let want = wanted[id], abs(want.x - button.frame.origin.x) < 0.5,
           abs(want.y - button.frame.origin.y) < 0.5 { return }
        homes[id] = button.frame.origin
        applied = nil
        place(rail: rail)
        view.superview?.needsLayout = true
    }

    // MARK: - placing

    /// Puts the buttons and the capsule where the sidebar's width wants them; returns the obstacle in
    /// the capsule's superview's coordinates, `.null` when nothing is held (full screen, no window, a
    /// button missing or hidden, no place for the home).
    @discardableResult
    func place(rail: Bool) -> CGRect {
        self.rail = rail
        guard let window, let content = view.superview, !window.styleMask.contains(.fullScreen) else {
            return release()
        }
        let buttons = Self.standardButtons(of: window)
        guard buttons.count == 3 else { return release() }
        watch(buttons)
        var home = CGRect.null
        for button in buttons {
            let id = ObjectIdentifier(button)
            if homes[id] == nil { homes[id] = button.frame.origin }
            guard let superview = button.superview, let origin = homes[id] else { return release() }
            home = home.union(content.convert(CGRect(origin: origin, size: button.frame.size), from: superview))
        }
        guard let placement = Self.placement(home: home, rail: rail) else { return release() }
        current = placement

        isPlacing = true
        for button in buttons {
            let id = ObjectIdentifier(button)
            guard let superview = button.superview, let origin = homes[id] else { continue }
            let from = superview.convert(CGPoint.zero, from: content)
            let to = superview.convert(CGPoint(x: placement.offset.width, y: placement.offset.height), from: content)
            let target = CGPoint(x: origin.x + to.x - from.x, y: origin.y + to.y - from.y)
            wanted[id] = target
            if abs(button.frame.origin.x - target.x) > 0.01 || abs(button.frame.origin.y - target.y) > 0.01 {
                button.setFrameOrigin(target)
            }
        }
        isPlacing = false

        if let zone = placement.capsule {
            view.isHidden = false
            if view.frame != zone.hoverZone { view.frame = zone.hoverZone }
            if window.isVisible {
                isOpen = view.bounds.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
            view.layoutDots(around: zone.closed.offsetBy(dx: -zone.hoverZone.minX, dy: -zone.hoverZone.minY))
            show(animated: false)
        } else {
            giveBack(buttons)
        }
        holdOrigins()
        return Self.obstacle(placement)
    }

    /// Writes each watched button's origin to where it was placed, when it stands elsewhere: once, in
    /// order. No write of its own is answered: `isPlacing` is set, and `frameChanged` tells the same write by
    /// its value as well, so nothing here can repeat.
    private func holdOrigins() {
        isPlacing = true
        defer { isPlacing = false }
        for item in watched where item.button.superview != nil {
            guard let target = wanted[ObjectIdentifier(item.button)] else { continue }
            let origin = item.button.frame.origin
            if abs(origin.x - target.x) > 0.01 || abs(origin.y - target.y) > 0.01 {
                item.button.setFrameOrigin(target)
            }
        }
    }

    /// Nothing is held: the buttons show, the capsule is hidden and shut.
    private func release() -> CGRect {
        current = nil
        giveBack(watched.map(\.button))
        return .null
    }

    private func giveBack(_ buttons: [NSButton]) {
        isOpen = false
        applied = nil
        view.isHidden = true
        for button in buttons where button.alphaValue != 1 { button.alphaValue = 1 }
    }

    /// The dots' ink: coloured while the window appears active, grey while it does not. Always applies the
    /// placement again.
    func setWindowAppearsActive(_ active: Bool) {
        view.active = active
        place(rail: rail)
    }

    /// What the tracking area's enter and exit call. Without a capsule there is nothing to open.
    func hover(_ inside: Bool) {
        guard current?.capsule != nil else {
            isOpen = false
            return
        }
        guard inside != isOpen else { return }
        isOpen = inside
        show(animated: true)
        holdOrigins()
    }

    /// The plate, the dots and the real buttons for `isOpen`: only what differs from the last time is
    /// written, and it is animated only when asked to and Reduce Motion is off.
    private func show(animated: Bool) {
        guard let zone = current?.capsule else { return }
        let rect = (isOpen ? zone.open : zone.closed).offsetBy(dx: -zone.hoverZone.minX, dy: -zone.hoverZone.minY)
        let target = Applied(plate: rect, dots: isOpen ? 0 : 1, buttons: isOpen ? 1 : 0)
        guard target != applied else { return }
        applied = target
        view.plate.cornerRadius = rect.height / 2
        let real = watched.map(\.button)
        guard animated, HelmMotion.morphs(reduceMotion: reducesMotion()) else {
            view.plate.frame = rect
            for dot in view.dots { dot.alphaValue = target.dots }
            for button in real { button.alphaValue = target.buttons }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = HelmMotion.interfaceDuration
            context.timingFunction = HelmMotion.interfaceCurve
            view.plate.animator().frame = rect
            for dot in view.dots { dot.animator().alphaValue = target.dots }
            for button in real { button.animator().alphaValue = target.buttons }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.holdOrigins() }
        })
    }
}

/// The capsule's view: a glass plate and three dots, flipped like the content, hit by nothing, hidden from
/// accessibility (the real buttons stay in the tree), with one tracking area over its bounds.
private final class CapsuleView: NSView {
    let plate = NSGlassEffectView()
    let dots = (0..<3).map { _ in NSView() }
    var onHover: ((Bool) -> Void)?

    /// Whether the window appears active.
    var active = true {
        didSet { redrawInk() }
    }

    /// The dots' side and the gap between them.
    private static let dot: CGFloat = 6
    private static let gap: CGFloat = 4

    /// The ink of the dots while the window is active, in the order of the system's close, minimise and
    /// zoom buttons. The design system has no token for them; `AppearancePicker.swift` draws the same three
    /// lights from literals of its own, which are not these values. These are read nowhere else.
    private static let activeInks = [NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
                                     NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
                                     NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        plate.style = .regular
        addSubview(plate)
        for dot in dots {
            dot.wantsLayer = true
            dot.layer?.cornerRadius = Self.dot / 2
            addSubview(dot)
        }
        setAccessibilityElement(false)
        redrawInk()
    }

    required init?(coder: NSCoder) { fatalError("CapsuleView is built in code") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redrawInk()
    }

    /// The dots in a row, centred on `closed`.
    func layoutDots(around closed: CGRect) {
        let width = Self.dot * CGFloat(dots.count) + Self.gap * CGFloat(dots.count - 1)
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: closed.midX - width / 2 + CGFloat(i) * (Self.dot + Self.gap),
                               y: closed.midY - Self.dot / 2, width: Self.dot, height: Self.dot)
        }
    }

    /// The inks are colours of one appearance, so they are resolved here and again when it changes.
    private func redrawInk() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let inks = active ? Self.activeInks : Array(repeating: NSColor.labelColor.withAlphaComponent(0.25), count: 3)
            for (dot, ink) in zip(dots, inks) { dot.layer?.backgroundColor = ink.cgColor }
        }
    }
}
