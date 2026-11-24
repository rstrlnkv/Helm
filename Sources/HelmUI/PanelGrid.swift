import Foundation

/// How much of the panel a widget takes.
///
/// **A word, never a column count.** `wide` is two columns at 300 pt and three
/// at 480, and a stored `2` would go wrong silently the moment the panel
/// changed width.
public enum PanelWidgetSize: String, CaseIterable, Codable, Sendable {
    /// One column. A figure, and nothing to press.
    case compact
    /// Every column, one row. A figure and the one thing to do about it.
    case wide
    /// Every column, growing downwards. Why the figure is what it is.
    case tall

    /// What the panel's own settings call it: 1×1, 2×1, 2×N.
    ///
    /// Not localised, and not «Small / Medium / Large»: the proportion is the
    /// fact, and it is the same in eight languages.
    public var label: String {
        switch self {
        case .compact: "1×1"
        case .wide: "2×1"
        case .tall: "2×N"
        }
    }

    /// Whether this size occupies the whole row whatever the column count is.
    public var isFullWidth: Bool { self != .compact }
}

/// The panel's geometry, as arithmetic rather than as a layout.
public enum PanelGrid {
    /// The narrowest a tile is allowed to be. Below it a button already costs
    /// the figure it sits under, which is the whole content of a compact
    /// widget.
    public static let minimumTile: CGFloat = 144
    public static let padding: CGFloat = HelmSpace.s5
    public static let gap: CGFloat = HelmSpace.s4

    /// The height the panel draws at before its strip has been measured: an
    /// 800 pt display, less the menu bar and a margin. Only then, never a
    /// ceiling on a measured strip, which runs from the status item down to the
    /// screen's visible frame and so already stops at the Dock.
    private static let maximumHeight: CGFloat = 768

    /// Columns at a given panel width — never fewer than two.
    ///
    /// The width decides how many columns fit, never how narrow a tile may
    /// get: a panel that cannot hold another 144 pt column gets wider tiles.
    public static func columns(for width: CGFloat) -> Int {
        let inner = width - padding * 2
        return max(2, Int(((inner + gap) / (minimumTile + gap)).rounded(.down)))
    }

    /// The size a widget actually gets, given what its module offers.
    ///
    /// **Clamped to the nearest, never dropped.** A module that stops offering
    /// a size must not make a widget vanish from a panel somebody arranged.
    /// Nearest is measured along `compact → wide → tall`, the order of how
    /// much room the answer takes.
    public static func resolve(_ wanted: PanelWidgetSize,
                               offered: Set<PanelWidgetSize>) -> PanelWidgetSize? {
        guard !offered.isEmpty else { return nil }
        if offered.contains(wanted) { return wanted }
        let ladder = PanelWidgetSize.allCases
        guard let index = ladder.firstIndex(of: wanted) else { return nil }
        return ladder.enumerated()
            .filter { offered.contains($0.element) }
            .min { abs($0.offset - index) < abs($1.offset - index) }?
            .element
    }

    /// What the grid may take: the strip the panel is drawn in, less whichever
    /// pinned bars are actually drawn, the card's own padding and the gaps
    /// between its three blocks. Never less than one row, so a very short strip
    /// still shows something to scroll.
    ///
    /// **A bar that is not drawn is `nil`, never its last measurement.** The
    /// writer's `guard measured > 0` drops SwiftUI's report of the collapse,
    /// which is right there and is why the reader says which bars exist;
    /// otherwise a hidden footer keeps its room and a grid that fitted scrolls.
    ///
    /// A strip of 0 is a strip nothing has measured yet, not a strip with no
    /// room: it falls back to `maximumHeight`, the only answer that draws a
    /// panel before the first geometry callback lands. A measured strip is
    /// taken whole, however tall.
    ///
    /// **A bar nobody draws takes its gap with it.** The card is three blocks
    /// with `gap` between them, and only the tab strip is conditional, so the
    /// gaps are two with the strip and one without. The footer block is drawn
    /// even when empty and still costs its neighbour's spacing, so `foot` says
    /// how tall it is and never whether its gap exists.
    public static func roomForGrid(strip: CGFloat, top: CGFloat?, foot: CGFloat?) -> CGFloat {
        let ceiling = strip > 0 ? strip : maximumHeight
        let gaps = gap * (top == nil ? 1 : 2)
        return max(minimumGrid, ceiling - (top ?? 0) - (foot ?? 0) - padding * 2 - gaps)
    }

    /// The least the grid is ever given: one row, rather than a sliver of one.
    private static let minimumGrid: CGFloat = 120

    /// The grid, as rows of indices into `sizes`.
    ///
    /// SwiftUI has no column span, so a full-width widget is a row of its own.
    /// The packing rule lives here, not in the view, so it can be tested:
    /// compact widgets fill a row and then start another, and a full-width one
    /// interrupts whatever row was being filled.
    public static func rows(sizes: [PanelWidgetSize], columns: Int) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        for (index, size) in sizes.enumerated() {
            if size.isFullWidth {
                if !current.isEmpty { rows.append(current); current = [] }
                rows.append([index])
            } else {
                current.append(index)
                if current.count == columns { rows.append(current); current = [] }
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
