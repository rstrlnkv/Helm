import AppKit
import HelmUI

/// **The settings window's `NSToolbar`, which carries one thing: the page's tabs, under Liquid Glass** (owner's
/// decision, 2026-11-23). The tabs are the system's own `NSSegmentedControl` in a bordered toolbar item, so they get
/// the toolbar's glass track and the press-and-hold lens that nothing outside a toolbar draws. The name, status,
/// actions and search stay in the card's row (`helmCardHeader`); under Flat the window has no toolbar at all.
///
/// **How the page reaches it**: the page's declaration is relayed by `HelmTabsRelay` through `sink`, and a clear
/// placeholder in the row (`HelmTabsSlot`) says where the card's row puts the strip; the row's layout keeps centring
/// it on the card and giving way. The toolbar positions its items itself and a control cannot be placed by frame, so
/// a leading spacer item is given the width that brings the strip's left edge to the placeholder's (`spacerWidth`),
/// solved again whenever the placeholder, the window or the declaration moves.
///
/// **Measured** (macOS 27.3, a window with these flags): the item's container must be exactly the control's width,
/// because the item's viewer swallows every click over its frame, a wider one killed the search field under it;
/// `isBordered` is required (it is the glass track); the item sits at window-top y 8...44 with the toolbar and the
/// card's row at 4...56, so the row raises its content by 4 under Glass (`CardHeader.raise`); a taller container
/// made a 44 pt glass track and took window drags; with the toolbar the window's three buttons stand 10 right and 10 down of where they stood
/// (`ShellGeometry.toolbarShift`). A trailing ghost item killed the button at the right and is not used.
///
/// Installed only under `.liquidGlass`, at creation and again on `.helmBarAppearanceChanged`. Not customizable, not
/// autosaved. Accessibility: one element per segment (radio button), not the control itself.
@MainActor final class SettingsToolbar: NSObject, NSToolbarDelegate {
    private static let tabsID = NSToolbarItem.Identifier("helm.tabs")
    private static let leadID = NSToolbarItem.Identifier("helm.tabs.lead")

    /// The spacer's width that puts the strip's left edge at `wantedMinX`. `chrome` is what lies left of the strip
    /// besides the spacer: the toolbar's start after the traffic lights and the gap between items, in the window's x.
    /// Absolute, not a correction of the last reading, since a reading taken while the toolbar has not laid out yet
    /// is stale and a correction on it overshoots. Never below zero.
    nonisolated static func spacerWidth(chrome: CGFloat, wantedMinX: CGFloat) -> CGFloat {
        let width = wantedMinX - chrome
        return width.isFinite ? max(width, 0) : 0
    }

    private let toolbar = NSToolbar(identifier: "HelmSettingsToolbar")
    private let strip = TabsStrip()
    private let lead = LeadSpacer()
    private var leadItem: NSToolbarItem?
    private var tabsItem: NSToolbarItem?
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
    }

    /// What the window puts in the environment of its detail pane.
    var sink: HelmTabsSink {
        HelmTabsSink(
            declare: { [weak self] owner, declaration in self?.declare(owner, declaration) },
            place: { [weak self] owner, rect in self?.place(owner, rect) },
            release: { [weak self] owner in self?.release(owner) })
    }

    // MARK: - the window

    /// Wears the toolbar under `look` and takes it off otherwise; again on every change of the look.
    func attach(to window: NSWindow, look: @escaping @MainActor () -> HelmBarAppearance) {
        self.window = window
        install(look())
        tokens.append(NotificationCenter.default.addObserver(
            forName: .helmBarAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.install(look()) }
        })
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.solve() }
        })
    }

    /// What a test reads of the item: the members here and on `TabsStrip` named `ForTesting` have no other caller.
    var stripForTesting: TabsStrip { strip }
    var tabsItemIsHiddenForTesting: Bool { tabsItem?.isHidden ?? true }

    var isInstalledForTesting: Bool { window?.toolbar === toolbar }

    private func install(_ look: HelmBarAppearance) {
        guard let window else { return }
        if look == .liquidGlass {
            if window.toolbar !== toolbar {
                window.toolbarStyle = .unified
                window.toolbar = toolbar
                window.titlebarSeparatorStyle = .none
            }
            solve()
        } else if window.toolbar != nil {
            window.toolbar = nil
        }
    }

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

    /// Shows `declaration` in the strip; nil hides the items.
    func apply(_ declaration: HelmTabsDeclaration?) {
        strip.apply(declaration)
        let hidden = declaration == nil
        tabsItem?.isHidden = hidden
        leadItem?.isHidden = hidden
        solve()
    }

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

    private func solve() {
        guard let window, window.toolbar === toolbar, declaration != nil, let slot, strip.window === window else { return }
        watchViewers()
        guard let viewer = lead.superview, viewer.window === window else { return }
        let origin = window.contentView.map { $0.convert($0.bounds.origin, to: nil).x } ?? 0
        let chrome = strip.convert(strip.bounds, to: nil).minX - viewer.frame.width
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

    /// The toolbar's viewers are the views the items' views sit in; their frames change when the toolbar lays out.
    private var watched: [NSView] = []

    private func watchViewers() {
        for view in [strip.superview, lead.superview].compactMap({ $0 }) where !watched.contains(where: { $0 === view }) {
            watched.append(view)
            view.postsFrameChangedNotifications = true
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.solve() }
            })
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.leadID, Self.tabsID]
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
            leadItem = item
        case Self.tabsID:
            item.view = strip
            // The glass track of the look: an unbordered item loses it.
            item.isBordered = true
            item.visibilityPriority = .user
            tabsItem = item
        default:
            return nil
        }
        item.isHidden = declaration == nil
        return item
    }
}
