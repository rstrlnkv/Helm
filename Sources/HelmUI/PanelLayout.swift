import Foundation

/// What the panel holds: tabs, their widgets, and the size each one takes.
///
/// **Tabs from the first commit, even though the tab bar is the last thing
/// built.** A layout stored as a flat list would need a format migration the
/// day tabs arrive, and this codebase has paid for one of those already —
/// `moduleOrder` to `sidebarLayout`, with the migration still sitting in the
/// store. One tab costs a pair of braces now and nothing later. The bar itself
/// appears only from the second tab, so until somebody makes one there is
/// nothing on screen to say a tab exists.
public struct PanelLayout: Equatable, Codable, Sendable {

    public struct Tab: Equatable, Codable, Sendable, Identifiable {
        public var id: String
        /// Set on the tab Helm seeds, so a rename can be undone and a fresh
        /// install's tab is named in the reader's language rather than in
        /// whatever language it was created in.
        public var seed: String?
        /// The name the person gave it. `nil` means the seeded one.
        public var name: String?
        public var widgets: [Slot]

        public init(id: String, seed: String? = nil, name: String? = nil, widgets: [Slot]) {
            self.id = id; self.seed = seed; self.name = name; self.widgets = widgets
        }
    }

    /// One widget in one tab.
    ///
    /// `widget` is an id, not a module id — though today every widget is its
    /// module's only one and the two strings are equal. The panel already has
    /// one widget planned that belongs to no module (the permissions notice,
    /// which arrives by itself and leaves with the grant), and a field that
    /// means «module» would have to be widened for it. One string either way.
    public struct Slot: Equatable, Codable, Sendable {
        public var widget: String
        public var size: PanelWidgetSize

        public init(widget: String, size: PanelWidgetSize) {
            self.widget = widget; self.size = size
        }

        /// A size this build has never heard of reads as `wide`, rather than
        /// failing the decode.
        ///
        /// Synthesised `Decodable` throws on an unknown raw value, and the
        /// throw is not local: `JSONDecoder` gives up on the whole document, so
        /// one slot written by a newer build would empty the entire panel and
        /// the next save would make it permanent. A downgrade should cost the
        /// person a widget's proportions, not their arrangement.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            widget = try container.decode(String.self, forKey: .widget)
            let raw = try container.decode(String.self, forKey: .size)
            size = PanelWidgetSize(rawValue: raw) ?? .wide
        }
    }

    public var tabs: [Tab]

    /// Widgets the person took off the panel.
    ///
    /// **Without this, removing one was undone by the next read.** `reconciled`
    /// adds any id this build can draw that the layout does not hold — which is
    /// how a module that arrives with an update joins the panel — and a widget
    /// somebody has just removed is exactly that: an id this build can draw
    /// that the layout does not hold. So it came back on the next launch, and
    /// the panel looked like it had forgotten.
    ///
    /// «Arrived» and «taken off» are different facts and neither can be
    /// inferred from the other, so the second one is written down.
    public var dismissed: [String]

    public init(tabs: [Tab], dismissed: [String] = []) {
        self.tabs = tabs
        self.dismissed = dismissed
    }

    /// A layout written before `dismissed` existed decodes with none.
    ///
    /// Synthesised `Decodable` does not use a property's default value — it
    /// throws on the missing key, and `JSONDecoder` gives up on the whole
    /// document — so every panel arranged before this build would have read as
    /// no panel at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([Tab].self, forKey: .tabs)
        dismissed = try container.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }

    /// Every widget in the panel, tab by tab.
    public var allSlots: [Slot] { tabs.flatMap(\.widgets) }

    // MARK: - Seeding

    /// One tab holding everything offered, at `wide` — which is exactly the
    /// panel Helm has always drawn, in the order the person arranged.
    public static func seeded(from widgets: [String]) -> PanelLayout {
        PanelLayout(tabs: [Tab(id: "seed.main", seed: "main", name: nil,
                               widgets: widgets.map { Slot(widget: $0, size: .wide) })])
    }

    // MARK: - The invariant

    /// The layout as it must be before anything draws it.
    ///
    /// Two rules, and the second is where this parts company with
    /// `SidebarLayout.reconciled`:
    ///
    /// - **No widget twice.** A half-written save is reachable, and a widget
    ///   held in two places would draw in two places.
    /// - **An unknown widget is kept, not dropped.** The sidebar's membership
    ///   is the registry's to decide, so anything not in the registry is
    ///   wrong there. The panel's membership is the *person's* — they put
    ///   these here — so an id this build cannot draw is a module that is
    ///   switched off, or one that a downgrade has temporarily taken away.
    ///   Dropping it would mean an update could empty somebody's panel and
    ///   the next save would make that permanent. It is skipped at the draw
    ///   instead, which is a decision about pixels rather than about storage.
    ///
    /// `arriving` is what to add: ids offered by this build that the layout has
    /// never seen. They go to the end of the first tab — the one somebody
    /// looking at the panel is already on.
    public func reconciled(arriving: [String]) -> PanelLayout {
        var seen = Set<String>()
        var tabs = self.tabs.map { tab -> Tab in
            var copy = tab
            copy.widgets = tab.widgets.filter { seen.insert($0.widget).inserted }
            return copy
        }
        if tabs.isEmpty { tabs = [Tab(id: "seed.main", seed: "main", name: nil, widgets: [])] }
        // Not everything absent is missing: the ones taken off were absent on
        // purpose.
        let taken = Set(dismissed)
        let fresh = arriving.filter { !seen.contains($0) && !taken.contains($0) }
        tabs[0].widgets.append(contentsOf: fresh.map { Slot(widget: $0, size: .wide) })
        return PanelLayout(tabs: tabs, dismissed: dismissed)
    }

    // MARK: - Rearranging

    /// Where a widget is, if it is anywhere.
    public func placement(of widget: String) -> (tab: Int, index: Int)? {
        for (t, tab) in tabs.enumerated() {
            if let i = tab.widgets.firstIndex(where: { $0.widget == widget }) { return (t, i) }
        }
        return nil
    }

    public func size(of widget: String) -> PanelWidgetSize? {
        placement(of: widget).map { tabs[$0.tab].widgets[$0.index].size }
    }

    /// Moves a widget to `index` within `tab`.
    ///
    /// Removed from wherever it was *first*, so a move inside one tab is the
    /// same call as a move between two and neither can leave a copy behind —
    /// the mistake the sidebar's own move was written to avoid.
    public func moving(_ widget: String, toTab tab: Int, at index: Int) -> PanelLayout {
        guard let from = placement(of: widget), tabs.indices.contains(tab) else { return self }
        var copy = self
        let slot = copy.tabs[from.tab].widgets.remove(at: from.index)
        let bound = max(0, min(index, copy.tabs[tab].widgets.count))
        copy.tabs[tab].widgets.insert(slot, at: bound)
        return copy
    }

    /// Why a widget cannot take a size, or nil if it can.
    ///
    /// **The refusal lives here rather than in a disabled button.** A greyed
    /// control says «not this»; a refusal can say what to do instead, and this
    /// one has something to say: go through `wide` first. Two steps, both of
    /// which show what they did.
    public func refusal(growing widget: String, to size: PanelWidgetSize) -> Refusal? {
        guard let current = self.size(of: widget) else { return nil }
        if size == .tall, current == .compact { return .tallNeedsFullWidth }
        return nil
    }

    public enum Refusal: Equatable, Sendable {
        /// Only a full-width widget may grow downwards: a tall narrow one opens
        /// a hole beside itself that nothing fills without masonry.
        case tallNeedsFullWidth
    }

    /// Refused sizes leave the layout untouched — the caller asks `refusal`
    /// first and says why, rather than watching nothing happen.
    public func resizing(_ widget: String, to size: PanelWidgetSize) -> PanelLayout {
        guard let at = placement(of: widget), refusal(growing: widget, to: size) == nil
        else { return self }
        var copy = self
        copy.tabs[at.tab].widgets[at.index].size = size
        return copy
    }

    /// Taking a widget off is remembered, or the next read puts it back.
    public func removing(_ widget: String) -> PanelLayout {
        guard let at = placement(of: widget) else { return self }
        var copy = self
        copy.tabs[at.tab].widgets.remove(at: at.index)
        if !copy.dismissed.contains(widget) { copy.dismissed.append(widget) }
        return copy
    }

    /// Adds a widget to the end of a tab, at `wide`. Never twice: a widget
    /// already in the panel is moved rather than copied.
    public func adding(_ widget: String, toTab tab: Int) -> PanelLayout {
        guard tabs.indices.contains(tab) else { return self }
        var next = removing(widget)
        // Putting it back is the answer to having taken it off, so the note
        // that it was taken off goes with it. Otherwise a widget added from the
        // gallery would be one somebody had to add again after every update.
        next.dismissed.removeAll { $0 == widget }
        next.tabs[tab].widgets.append(Slot(widget: widget, size: .wide))
        return next
    }

    /// Refused, without a place to remove it from.
    ///
    /// `removing` only knows how to take a widget out of a tab, and a module in
    /// the utilities drawer was never in one — so taking it off the panel is
    /// this rather than that.
    public func dismissing(_ widget: String) -> PanelLayout {
        guard !dismissed.contains(widget) else { return self }
        var copy = self
        copy.dismissed.append(widget)
        return copy
    }

    /// Wanted again, without a place in the grid.
    ///
    /// The utilities drawer holds modules that have no widget, so «put it back»
    /// cannot mean «add a slot». It means only: stop refusing it. The same
    /// `dismissed` list answers for both, because from the person's side it is
    /// one fact — this is not something I want in the panel.
    public func restoring(_ widget: String) -> PanelLayout {
        var copy = self
        copy.dismissed.removeAll { $0 == widget }
        return copy
    }

    /// Whether the person has taken this off the panel.
    public func isDismissed(_ widget: String) -> Bool { dismissed.contains(widget) }

    // MARK: - Tabs

    /// A tab is only worth its strip once there is a second one. Until then the
    /// panel is a grid and nothing on screen says a tab exists.
    public var showsTabBar: Bool { tabs.count > 1 }

    public func addingTab(id: String) -> PanelLayout {
        var copy = self
        copy.tabs.append(Tab(id: id, seed: nil, name: nil, widgets: []))
        return copy
    }

    public func renamingTab(_ id: String, to name: String?) -> PanelLayout {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.tabs[index].name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return copy
    }

    /// Closing a tab hands its widgets to the neighbour rather than dropping
    /// them.
    ///
    /// Somebody arranged those; «close» is about the tab, and taking six
    /// widgets with it is a second, larger action nobody asked for. The
    /// neighbour is the tab to the left, or the one to the right if this was
    /// the first — the one that is about to be looked at either way.
    ///
    /// The last tab cannot be closed: a panel with no tabs has nowhere to put
    /// anything.
    public func removingTab(_ id: String) -> PanelLayout {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id })
        else { return self }
        var copy = self
        let orphans = copy.tabs.remove(at: index).widgets
        let neighbour = max(0, index - 1)
        copy.tabs[neighbour].widgets.append(contentsOf: orphans)
        return copy
    }
}
