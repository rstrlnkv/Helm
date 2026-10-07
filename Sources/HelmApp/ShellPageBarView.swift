import AppKit

/// **Places the bar's five zones where `ShellBarLayout` says.** It measures
/// nothing and reads neither the window nor a setting: every number but its own width is
/// given to it, in `measures` and `place`, and every zone's view is handed in through
/// `setView(_:for:)`. It sets no height of its own.
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
    /// Each field is the field of the same meaning in `ShellBarLayout.Input`,
    /// which says what it holds.
    struct Place: Equatable {
        var cardMinX: CGFloat = 0
        var windowWidth: CGFloat = 0
        var buttons: CGRect = .null
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
