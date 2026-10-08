import AppKit

/// **Places the bar's five zones where `ShellBarLayout` says.** It measures
/// nothing: every number but its own width is given to it, in `measures` and
/// `place`, and every zone's view is handed in through `setView(_:for:)`. It sets
/// no height of its own. It reads one setting, the system's double-click action, and
/// touches its window only in `mouseDown(with:)`, where it asks the window to drag on a
/// press and to zoom, to minimize or nothing on a double click. It is an accessibility group (role toolbar) of the
/// zones it shows; its label is written by whoever owns it, and so is its menu, which it withholds inside
/// `place.reach`.
///
/// **One pass, in this order.** `layout()` builds one `ShellBarLayout.Input`
/// from the bar's width, `measures` and `place`, asks `ShellBarLayout.frames`
/// once, stores the answer in `frames`, tells `verdictsChanged` if either verdict
/// differs from the last pass, and only then sets the zones' frames, exactly as
/// answered and never rounded. A zone whose frame has no width is hidden.
///
/// **The verdicts go out before any frame is set** so the receiver can swap a
/// zone's view (the search field for its magnifier) inside the call and see the
/// new view placed in this same pass. The receiver must not write `measures` or
/// `place` from inside the call: the pass has already read them and does not
/// read them again, so the frames it sets are the old answer's. For
/// that reason the natural widths must not depend on the verdicts, which is why
/// both widths of the tabs are inputs.
@MainActor
final class ShellPageBarView: NSView {

    /// Left to right; also the order of `subviews`, whatever order the views were given in.
    enum Zone: Int, CaseIterable { case name, tabs, actions, search, status }

    /// What the page's content needs. Written by whoever owns the zones' views.
    /// Each field is the field of the same meaning in `ShellBarLayout.Input`,
    /// which says what it holds.
    struct Measures: Equatable {
        var name: CGFloat = 0
        var tabs: CGFloat = 0
        var tabsFolded: CGFloat = 0
        var actions: CGFloat = 0
        var status: CGFloat = 0
        var hasSearch = false
        var alwaysCollapseSearch = false
        var searchInUse = false
    }

    /// Where the bar stands. Written by whoever sets the bar's frame, in the same pass.
    /// Each field but `reach` is the field of the same meaning in `ShellBarLayout.Input`,
    /// which says what it holds.
    struct Place: Equatable {
        var cardMinX: CGFloat = 0
        var windowWidth: CGFloat = 0
        var buttons: CGRect = .null
        /// The window-button capsule's hover zone in the bar's coordinates; the bar opens no menu on a point
        /// inside it. Not an input of the layout. `.null`, and a rectangle with a not-a-number side, contain
        /// no point, so the menu opens as everywhere else on the bar.
        var reach: CGRect = .null
    }

    struct Verdicts: Equatable {
        var tabsFolded = false
        var searchFolded = false
    }

    var measures = Measures() {
        didSet { if measures != oldValue { needsLayout = true } }
    }

    var place = Place() {
        didSet { if place != oldValue { needsLayout = true } }
    }

    /// The last answer; nil until the first layout.
    private(set) var frames: ShellBarLayout.Frames?
    private(set) var verdicts = Verdicts()

    /// One slot, one receiver. Called inside `layout()`, only when a verdict
    /// changed, before any frame of that pass is set. The bar holds the closure,
    /// so a receiver that holds the bar must not capture itself strongly.
    var verdictsChanged: ((Verdicts) -> Void)?

    private var views: [Zone: NSView] = [:]

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
    }

    required init?(coder: NSCoder) { fatalError("ShellPageBarView is built in code") }

    /// `nil` takes the zone's view out; the same view again does nothing. The
    /// subviews stay in `Zone.allCases` order whatever order the views come in,
    /// a replaced view leaves its superview, and a new view asks for a layout.
    func setView(_ view: NSView?, for zone: Zone) {
        let old = views[zone]
        if old === view { return }
        old?.removeFromSuperview()
        views[zone] = view
        if let view {
            let later = Zone.allCases.filter { $0.rawValue > zone.rawValue }.compactMap { views[$0] }
            if let next = later.first {
                addSubview(view, positioned: .below, relativeTo: next)
            } else {
                addSubview(view)
            }
            needsLayout = true
        }
    }

    func view(for zone: Zone) -> NSView? { views[zone] }

    // MARK: - Accessibility and the window's handle

    /// The zones that hold a view which is not hidden, left to right: `accessibilityChildren()` is built from
    /// their views. A zone with no view, and a zone whose frame the layout gave no width, are out.
    var reachableZones: [Zone] {
        Zone.allCases.filter { views[$0].map { !$0.isHidden } ?? false }
    }

    /// The unignored accessibility elements of the reachable zones' views, in zone order: a view that is
    /// itself an element stands as itself, any other is replaced by the elements inside it. A hidden view is
    /// not among them.
    override func accessibilityChildren() -> [Any]? {
        NSAccessibility.unignoredChildren(from: reachableZones.compactMap { views[$0] })
    }

    /// The zones whose views are the window's handle: a point on them answers the bar, not the view. This
    /// line decides that the page's name and the status word both count as handle; take `.status` out and a
    /// status view that claims the point answers itself.
    private static let handleZones: Set<Zone> = [.name, .status]

    /// A point on a handle zone's view, or on anything inside it, answers the bar whatever that view would
    /// answer; a point on any other zone's view answers what `super` answers.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        for zone in Self.handleZones {
            if let view = views[zone], hit === view || hit.isDescendant(of: view) { return self }
        }
        return hit
    }

    /// The bar's menu, except on a point inside `place.reach`: there the press is meant for the window
    /// buttons' capsule. A left press there lands on the bar as anywhere else on it: `hitTest(_:)` does not
    /// read `place.reach`.
    override func menu(for event: NSEvent) -> NSMenu? {
        if place.reach.contains(convert(event.locationInWindow, from: nil)) { return nil }
        return super.menu(for: event)
    }

    override var mouseDownCanMoveWindow: Bool { true }

    /// What a double click on the bar asks of the window, after the system's title-bar setting.
    enum DoubleClick: Equatable { case zoom, minimize, nothing }

    /// The title bar's double-click action from the stored `AppleActionOnDoubleClick` string. An absent value
    /// and every spelling not known here answer zoom. That the system's own title bar zooms with no value
    /// stored, and the spellings "Minimize" and "None", are taken as given: only the key's absence was read
    /// (`defaults read -g AppleActionOnDoubleClick`), no test reads a real setting and nobody has tried them
    /// by hand.
    nonisolated static func doubleClick(stored: String?) -> DoubleClick {
        switch stored {
        case "Minimize": .minimize
        case "None": .nothing
        default: .zoom
        }
    }

    /// A double click asks the window for the title bar's action, any other press asks it to
    /// drag. That a press moves the window and that a double click zooms it are known to no test and have not
    /// been tried by hand.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            switch Self.doubleClick(stored: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
            case .zoom: window?.performZoom(nil)
            case .minimize: window?.performMiniaturize(nil)
            case .nothing: break
            }
        } else {
            window?.performDrag(with: event)
        }
    }

    override func layout() {
        super.layout()
        let answer = ShellBarLayout.frames(for: ShellBarLayout.Input(
            barWidth: bounds.width,
            cardMinX: place.cardMinX,
            windowWidth: place.windowWidth,
            nameWidth: measures.name,
            tabsWidth: measures.tabs,
            tabsFoldedWidth: measures.tabsFolded,
            actionsWidth: measures.actions,
            statusWidth: measures.status,
            hasSearch: measures.hasSearch,
            alwaysCollapseSearch: measures.alwaysCollapseSearch,
            searchInUse: measures.searchInUse,
            buttons: place.buttons))
        frames = answer

        let now = Verdicts(tabsFolded: answer.tabsFolded, searchFolded: answer.searchFolded)
        if now != verdicts {
            verdicts = now
            verdictsChanged?(now)
        }

        for zone in Zone.allCases {
            guard let view = views[zone] else { continue }
            let frame = switch zone {
            case .name: answer.name
            case .tabs: answer.tabs
            case .actions: answer.actions
            case .search: answer.search
            case .status: answer.status
            }
            view.isHidden = frame.width <= 0
            if frame.width > 0 { view.frame = frame }
        }
    }
}
