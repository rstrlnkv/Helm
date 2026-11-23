import AppKit
import HelmUI

/// **The settings window's `NSToolbar`, worn under both looks; it carries one thing: the page's tabs, under Liquid
/// Glass** (owner's decision, 2026-11-23). The tabs are the system's own `NSSegmentedControl`, so they get the press-and-hold
/// lens that nothing outside a toolbar draws. The name, status, actions and search stay in the card's row
/// (`helmCardHeader`); under Flat the toolbar has no items and the row draws the tabs.
///
/// **Installed once and kept**: `attach(to:)` sets `window.toolbar` and never again. Taking the toolbar off and
/// putting it back made a glass the strip drew itself come back empty.
///
/// **How the page reaches it**: the page's declaration is relayed by `HelmTabsRelay` through `sink`, and a clear
/// placeholder in the row (`HelmTabsSlot`) says where the card's row puts the strip; the row's layout keeps centring
/// it on the card and giving way. The toolbar positions its items itself and a control cannot be placed by frame, so
/// a leading spacer item is given the width that brings the strip's left edge to the placeholder's (`spacerWidth`),
/// solved again whenever the placeholder, the window or the declaration moves. A reading taken before the toolbar has
/// laid the strip out (the strip left of the spacer's end) is stale and writes nothing (`chrome`); the viewers'
/// frame notifications ask again.
///
/// **Measured** (macOS 27.3, unified, icon-only): the toolbar is 52 pt tall and centres every item at window y 26,
/// while the card's row centres at y 30 (`ShellGeometry.inset` 4 + `CardHeader.height` 52 / 2). A *bordered* item's
/// glass track follows the item view's alignment rect and stays centred at 26, so the item is *unbordered* and the
/// strip draws its own track (`NSGlassEffectView`) at the control's place, 12 to 48. The item's view is 44 pt tall
/// (`TabsStrip.lift` above the control) so the toolbar's centring leaves the control at the row's centre. The price:
/// the item's viewer takes presses over its whole frame, so the 8 pt band above the tabs no longer drags the window.
/// The viewer also swallows clicks, so the item's width is exactly the control's. A trailing ghost item killed the
/// button at the right and is not used.
///
/// **The items are in the toolbar only while a page declares tabs**: an item whose `isHidden` goes false is zoomed in
/// from small by the toolbar (measured on video, about 4 frames; no transaction, animation context, layout pass or
/// layer change stops it), while an item inserted shows at full size in one frame. So no declaration leaves the toolbar
/// without items, a declaration holds the spacer and the tabs, in that order.
///
/// Not customizable, not autosaved. Accessibility: one element per segment (radio button), not the control itself.
@MainActor final class SettingsToolbar: NSObject, NSToolbarDelegate {
    static let tabsID = NSToolbarItem.Identifier("helm.tabs")
    static let leadID = NSToolbarItem.Identifier("helm.tabs.lead")

    /// The spacer's width that puts the strip's left edge at `wantedMinX`. `chrome` is what lies left of the strip
    /// besides the spacer: the toolbar's start after the traffic lights and the gap between items, in the window's x.
    /// Absolute, not a correction of the last reading, since a reading taken while the toolbar has not laid out yet
    /// is stale and a correction on it overshoots. Never below zero.
    nonisolated static func spacerWidth(chrome: CGFloat, wantedMinX: CGFloat) -> CGFloat {
        let width = wantedMinX - chrome
        return width.isFinite ? max(width, 0) : 0
    }

    /// One identifier per toolbar: toolbars of one identifier keep their items in step, so a second one alive (a test's,
    /// a window not yet released) was handed the first's items and refused the insertion of its own ("already contains").
    private let toolbar = NSToolbar(identifier: "HelmSettingsToolbar-\(UUID().uuidString)")
    private let strip = TabsStrip()
    private let lead = LeadSpacer()
    private weak var window: NSWindow?

    private var owner: UUID?
    private var declaration: HelmTabsDeclaration?
    private var slot: CGRect?
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        strip.onPick = { [weak self] index in self?.picked(index) }
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        for watch in watching.values { NotificationCenter.default.removeObserver(watch.token) }
    }

    /// What the window puts in the environment of its detail pane.
    var sink: HelmTabsSink {
        HelmTabsSink(
            declare: { [weak self] owner, declaration in self?.declare(owner, declaration) },
            place: { [weak self] owner, rect in self?.place(owner, rect) },
            release: { [weak self] owner in self?.release(owner) })
    }

    // MARK: - the window

    /// Wears the toolbar, once, under every look.
    func attach(to window: NSWindow) {
        self.window = window
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        window.titlebarSeparatorStyle = .none
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.solve() }
        })
    }

    /// What a test reads of the item: the members here and on `TabsStrip` named `ForTesting` have no other caller.
    var stripForTesting: TabsStrip { strip }
    var itemIdentifiersForTesting: [NSToolbarItem.Identifier] { toolbar.items.map(\.itemIdentifier) }

    var watchedCountForTesting: Int { watching.count }

    var isInstalledForTesting: Bool { window?.toolbar === toolbar }

    // MARK: - what the page says

    /// An owner that was replaced or released is dead: nothing it says later (a late `place`, `declare` or `release`
    /// of a row that a change of language rebuilt) touches the new one. A first word from an owner never heard of is
    /// its arrival: `place` may come before `declare`, so a `place` alone is held until it declares. Deliberately
    /// unbounded: an evicted owner would read as new and could take the toolbar back.
    private var retired: Set<UUID> = []
    private var arrival: (owner: UUID, rect: CGRect?)?

    private func declare(_ owner: UUID, _ declaration: HelmTabsDeclaration?) {
        guard !retired.contains(owner) else { return }
        if owner != self.owner {
            if let old = self.owner { retired.insert(old) }
            self.owner = owner
            slot = arrival?.owner == owner ? arrival?.rect : nil
            arrival = nil
        }
        self.declaration = declaration
        apply(declaration)
    }

    private func place(_ owner: UUID, _ rect: CGRect?) {
        guard !retired.contains(owner) else { return }
        guard owner == self.owner else {
            arrival = (owner, rect)
            return
        }
        slot = rect
        solve()
    }

    private func release(_ owner: UUID) {
        if arrival?.owner == owner { arrival = nil }
        guard owner == self.owner else { return }
        retired.insert(owner)
        self.owner = nil
        declaration = nil
        slot = nil
        apply(nil)
    }

    /// Shows `declaration` in the strip; nil takes the items out of the toolbar (never hides them, see the header).
    func apply(_ declaration: HelmTabsDeclaration?) {
        strip.apply(declaration)
        if declaration == nil {
            for index in toolbar.items.indices.reversed() where Self.ids.contains(toolbar.items[index].itemIdentifier) {
                toolbar.removeItem(at: index)
            }
        } else {
            for id in Self.ids where !toolbar.items.contains(where: { $0.itemIdentifier == id }) {
                toolbar.insertItem(withItemIdentifier: id, at: toolbar.items.count)
            }
        }
        solve()
    }

    private static let ids = [leadID, tabsID]

    /// The control's own press: the page is told, then the selection is read again one turn later and the control
    /// put back on it, so a write the page refused snaps back.
    private func picked(_ index: Int) {
        guard let declaration, declaration.tabs.indices.contains(index) else { return }
        declaration.select(declaration.tabs[index].id)
        DispatchQueue.main.async { [weak self] in
            guard let self, let now = self.declaration else { return }
            self.strip.select(now.tabs.firstIndex { $0.id == now.selected } ?? -1)
        }
    }

    // MARK: - the spacer

    /// Brings the strip's left edge to the placeholder's. It runs when the placeholder, the window or the declaration
    /// moves, and again whenever the toolbar moves the items' viewers (`watchViewers`), since the toolbar's own layout
    /// comes a turn after the width is written and again when an item is shown or hidden. It writes only when the
    /// edge is more than half a point off, so it settles; `settling` stops a run that does not.
    private var settling = 0

    /// What lies left of the strip besides the spacer, in the window's x. Nil while the strip does not yet stand right
    /// of the spacer's viewer (the toolbar has not laid out: a stale reading, which once gave a spacer of 1078 pt and
    /// pushed the tabs out of the toolbar for good).
    nonisolated static func chrome(stripMinX: CGFloat, viewerMinX: CGFloat, viewerWidth: CGFloat) -> CGFloat? {
        guard stripMinX.isFinite, viewerMinX.isFinite, viewerWidth.isFinite,
              stripMinX >= viewerMinX + viewerWidth - 0.5 else { return nil }
        return stripMinX - viewerWidth
    }

    private func solve() {
        guard let window, window.toolbar === toolbar, declaration != nil, let slot, strip.window === window else { return }
        watchViewers()
        guard let viewer = lead.superview, viewer.window === window else { return }
        let origin = window.contentView.map { $0.convert($0.bounds.origin, to: nil).x } ?? 0
        guard let chrome = Self.chrome(stripMinX: strip.convert(strip.bounds, to: nil).minX,
                                       viewerMinX: viewer.convert(viewer.bounds, to: nil).minX,
                                       viewerWidth: viewer.frame.width) else { return }
        let width = Self.spacerWidth(chrome: chrome, wantedMinX: origin + slot.minX)
        guard abs(width - lead.width) > 0.5 else { settling = 0; return }
        guard settling < 40 else { return }
        settling += 1
        lead.width = width
        if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.leadID }) {
            toolbar.removeItem(at: index)
            toolbar.insertItem(withItemIdentifier: Self.leadID, at: index)
        }
        DispatchQueue.main.async { [weak self] in self?.solve() }
    }

    /// The toolbar's viewers are the views the items' views sit in; their frames change when the toolbar lays out. An
    /// item put in again gets a new viewer, so the observers of viewers that are no longer the items' are removed
    /// first: at most the strip's and the spacer's are held, and the viewers weakly.
    private struct Watch {
        weak var view: NSView?
        let token: NSObjectProtocol
    }
    nonisolated(unsafe) private var watching: [ObjectIdentifier: Watch] = [:]

    private func watchViewers() {
        let current = [strip.superview, lead.superview].compactMap { $0 }
        let keep = Set(current.map(ObjectIdentifier.init))
        for (id, watch) in watching where !keep.contains(id) || watch.view == nil {
            NotificationCenter.default.removeObserver(watch.token)
            watching[id] = nil
        }
        for view in current where watching[ObjectIdentifier(view)] == nil {
            view.postsFrameChangedNotifications = true
            let token = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.solve() }
            }
            watching[ObjectIdentifier(view)] = Watch(view: view, token: token)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        declaration == nil ? [] : Self.ids
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.leadID, Self.tabsID]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.leadID:
            item.view = lead
            item.isBordered = false
            item.visibilityPriority = .user
        case Self.tabsID:
            item.view = strip
            // Unbordered: the strip draws its own track (`TabsStrip`), the bordered one stays at y 26.
            item.isBordered = false
            item.visibilityPriority = .user
        default:
            return nil
        }
        return item
    }
}
