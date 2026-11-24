import Foundation
import HelmRuntime

/// What the panel holds: tabs, their widgets, and the size each one takes.
///
/// Stored as tabs even with one tab, so a second tab needs no format
/// migration. The tab bar appears only from the second tab, so until somebody
/// makes one nothing on screen says a tab exists.
public struct PanelLayout: Equatable, Codable, Sendable {

    public struct Tab: Equatable, Codable, Sendable, Identifiable {
        /// What a new tab is marked with, in the order they are handed out: the
        /// picker's first category, so there is one list of symbols to keep.
        static var glyphs: [String] { HelmGlyphCatalogue.categories[0].symbols }

        public var id: String
        /// Set on the tab Helm seeds, so a rename can be undone and a fresh
        /// install's tab is named in the reader's language rather than in
        /// whatever language it was created in.
        public var seed: String?
        /// The name the person gave it. `nil` means the seeded one.
        public var name: String?
        public var widgets: [Slot]
        /// An SF Symbol name. Optional because an older stored tab has none.
        public var glyph: String?

        init(id: String, seed: String? = nil, name: String? = nil,
                    widgets: [Slot], glyph: String? = nil) {
            self.id = id; self.seed = seed; self.name = name
            self.widgets = widgets; self.glyph = glyph
        }
    }

    /// One widget in one tab.
    ///
    /// `widget` is a widget id, not a module id, even where the two strings
    /// are equal: a widget that belongs to no module, such as a permissions
    /// notice, fits the same field.
    public struct Slot: Equatable, Codable, Sendable {
        public var widget: String
        public var size: PanelWidgetSize

        public init(widget: String, size: PanelWidgetSize) {
            self.widget = widget; self.size = size
        }

        /// A size this build has never heard of reads as `wide`, rather than
        /// failing the decode. Synthesised `Decodable` throws on an unknown raw
        /// value and `JSONDecoder` then gives up on the whole document, so one
        /// slot from a newer build would empty the panel and the next save would
        /// make it permanent.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            widget = try container.decode(String.self, forKey: .widget)
            let raw = try container.decode(String.self, forKey: .size)
            size = PanelWidgetSize(rawValue: raw) ?? .wide
        }
    }

    public var tabs: [Tab]

    /// Modules the person does not want **as a widget**. They are still in the
    /// panel, in the utilities drawer, which holds everything that is not a
    /// tile; that is the difference from `hidden`.
    ///
    /// Remembered because `reconciled` adds any id this build can draw that the
    /// layout does not hold, which is how a new module joins the panel, and a
    /// widget just removed is exactly that: without this list it comes back on
    /// the next launch.
    var dismissed: [String]

    /// Modules the person does not want in the panel **at all** — no tile, no
    /// row in the drawer. Only the gallery offers them back.
    var hidden: [String]

    public init(tabs: [Tab], dismissed: [String] = [], hidden: [String] = []) {
        self.tabs = tabs
        self.dismissed = dismissed
        self.hidden = hidden
    }

    /// A stored layout without `dismissed` or `hidden` decodes with none.
    /// Synthesised `Decodable` throws on a missing key instead of using the
    /// default, and `JSONDecoder` then gives up on the whole document.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([Tab].self, forKey: .tabs)
        dismissed = try container.decodeIfPresent([String].self, forKey: .dismissed) ?? []
        hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
    }

    /// Every widget in the panel, tab by tab.
    public var allSlots: [Slot] { tabs.flatMap(\.widgets) }

    // MARK: - Seeding

    /// One tab holding everything offered, in the order the person arranged.
    /// `sizes` is what each widget is worth at rest; everything not named is
    /// `wide`, which is what a module with a control needs.
    public static func seeded(from widgets: [String],
                              sizes: [String: PanelWidgetSize] = [:]) -> PanelLayout {
        PanelLayout(tabs: [Tab(id: "seed.main", seed: "main", name: nil,
                               widgets: widgets.map { Slot(widget: $0, size: sizes[$0] ?? .wide) },
                               glyph: Tab.glyphs[0])])
    }

    // MARK: - The invariant

    /// The layout as it must be before anything draws it.
    ///
    /// - **No widget twice.** A half-written save is reachable, and a widget
    ///   held in two places would draw in two places.
    /// - **An unknown widget is kept, not dropped**, unlike in
    ///   `SidebarLayout.reconciled`. The panel's membership is the person's, so
    ///   an id this build cannot draw is a module switched off or taken away by
    ///   a downgrade. Dropping it would let an update empty somebody's panel
    ///   for good; it is skipped at the draw instead.
    ///
    /// `arriving` is the ids offered by this build that the layout has never
    /// seen. They go to the end of the first tab.
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
        let away = Set(hidden)
        let fresh = arriving.filter { !seen.contains($0) && !taken.contains($0) && !away.contains($0) }
        tabs[0].widgets.append(contentsOf: fresh.map { Slot(widget: $0, size: .wide) })
        return PanelLayout(tabs: tabs, dismissed: dismissed, hidden: hidden)
    }

    // MARK: - Rearranging

    /// Where a widget is, if it is anywhere.
    public func placement(of widget: String) -> (tab: Int, index: Int)? {
        for (t, tab) in tabs.enumerated() {
            if let i = tab.widgets.firstIndex(where: { $0.widget == widget }) { return (t, i) }
        }
        return nil
    }

    /// Moves a widget to `index` within `tab`.
    ///
    /// Removed from wherever it was *first*, so a move inside one tab is the
    /// same call as a move between two and neither can leave a copy behind.
    public func moving(_ widget: String, toTab tab: Int, at index: Int) -> PanelLayout {
        guard let from = placement(of: widget), tabs.indices.contains(tab) else { return self }
        var copy = self
        let slot = copy.tabs[from.tab].widgets.remove(at: from.index)
        copy.tabs[tab].widgets.insert(slot, at: index.clamped(to: 0...copy.tabs[tab].widgets.count))
        return copy
    }

    /// Any offered size, including 1×1 straight to 2×N: `tall` is full width,
    /// so it never leaves a hole beside it.
    public func resizing(_ widget: String, to size: PanelWidgetSize) -> PanelLayout {
        guard let at = placement(of: widget) else { return self }
        var copy = self
        copy.tabs[at.tab].widgets[at.index].size = size
        return copy
    }

    /// Stops being a tile. It is still in the panel: the drawer holds
    /// everything that is not one.
    ///
    /// Remembered, or the next read would put the tile back.
    public func removing(_ widget: String) -> PanelLayout {
        var copy = self
        if let at = placement(of: widget) { copy.tabs[at.tab].widgets.remove(at: at.index) }
        if !copy.dismissed.contains(widget) { copy.dismissed.append(widget) }
        return copy
    }

    /// Adds a widget to the end of a tab, at `wide`. Never twice: a widget
    /// already in the panel is moved rather than copied.
    public func adding(_ widget: String, toTab tab: Int) -> PanelLayout {
        guard tabs.indices.contains(tab) else { return self }
        var next = removing(widget)
        // Promoting answers both refusals at once: it is a tile again, so it is
        // neither «not a tile» nor «not here», and the next update keeps it.
        next.dismissed.removeAll { $0 == widget }
        next.hidden.removeAll { $0 == widget }
        next.tabs[tab].widgets.append(Slot(widget: widget, size: .wide))
        return next
    }

    /// Out of the panel altogether — the second press, on a row that is
    /// already only a row.
    public func hiding(_ widget: String) -> PanelLayout {
        var copy = removing(widget)
        if !copy.hidden.contains(widget) { copy.hidden.append(widget) }
        return copy
    }

    /// Back into the drawer, from the gallery. Not back into the grid: a
    /// module with no widget has no tile to be given, and one that has a widget
    /// is promoted by `adding` instead.
    public func restoring(_ widget: String) -> PanelLayout {
        var copy = self
        copy.hidden.removeAll { $0 == widget }
        return copy
    }

    /// Not a tile — which is not the same as not in the panel.
    public func isDismissed(_ widget: String) -> Bool { dismissed.contains(widget) }
    /// Not in the panel at all.
    public func isHidden(_ widget: String) -> Bool { hidden.contains(widget) }

    // MARK: - Tabs

    /// A tab is only worth its strip once there is a second one. Until then the
    /// panel is a grid and nothing on screen says a tab exists.
    public var showsTabBar: Bool { tabs.count > 1 }

    /// A tab whose id is already taken is not added: `ForEach` keyed on the id
    /// would draw one row for two tabs and leave the second one's widgets
    /// where nobody can reach them.
    public func addingTab(id: String) -> PanelLayout {
        guard !tabs.contains(where: { $0.id == id }) else { return self }
        var copy = self
        // A different glyph from the ones already used. It runs out at eight, and
        // then repeats rather than refusing to make a tab.
        let taken = Set(copy.tabs.compactMap(\.glyph))
        let glyph = Tab.glyphs.first { !taken.contains($0) } ?? Tab.glyphs[copy.tabs.count % Tab.glyphs.count]
        copy.tabs.append(Tab(id: id, seed: nil, name: nil, widgets: [], glyph: glyph))
        return copy
    }

    public func settingGlyph(_ glyph: String?, onTab id: String) -> PanelLayout {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        copy.tabs[index].glyph = glyph
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
    /// them: «close» is about the tab, not the widgets somebody arranged. The
    /// neighbour is the tab to the left, or to the right for the first tab.
    /// The last tab cannot be closed.
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
