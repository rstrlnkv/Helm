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

    public init(tabs: [Tab]) { self.tabs = tabs }

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
        let fresh = arriving.filter { !seen.contains($0) }
        tabs[0].widgets.append(contentsOf: fresh.map { Slot(widget: $0, size: .wide) })
        return PanelLayout(tabs: tabs)
    }
}
