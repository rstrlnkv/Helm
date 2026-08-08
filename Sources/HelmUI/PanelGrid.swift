import Foundation

/// How much of the panel a widget takes.
///
/// **A word, never a column count.** `wide` is two columns at 300 pt and three
/// at 480, and a model that stored `2` would be wrong the moment the panel
/// changed width — with no error and nothing to notice. The mockups made this
/// rule executable before it was written here: seven live panels, resizable,
/// and none of them holds a number that can go stale.
public enum PanelWidgetSize: String, CaseIterable, Codable, Sendable {
    /// One column. A figure, and nothing to press.
    case compact
    /// Every column, one row. A figure and the one thing to do about it.
    case wide
    /// Every column, growing downwards. Why the figure is what it is.
    case tall

    /// What the panel's own settings call it: 1×1, 2×1, 2×N.
    ///
    /// Not localised, and not «Small / Medium / Large». The proportion is the
    /// fact, it is the same fact in eight languages, and «large» would be a
    /// third word for the two that already have one.
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
///
/// Pure so the rules can be argued with in a test: how many columns a width
/// gets, which sizes a widget may actually take, and what happens to a stored
/// size that the module no longer offers.
public enum PanelGrid {
    /// The narrowest a tile is allowed to be. Below it a button already costs
    /// the figure it sits under, which is the whole content of a compact
    /// widget.
    public static let minimumTile: CGFloat = 144
    public static let padding: CGFloat = 12
    public static let gap: CGFloat = 8

    /// The tallest the panel may be: an 800 pt display, less the menu bar and
    /// a margin. Past it the grid scrolls and the footer stays.
    public static let maximumHeight: CGFloat = 768

    /// The narrowest panel two 144 pt tiles fit in: 2 × 144 + 8 + 2 × 12.
    ///
    /// Below it the floor cannot be honoured at all, because two columns is the
    /// minimum. The panel is drawn at exactly this width, which is what makes
    /// the floor a rule rather than a sentence.
    public static let narrowestPanel: CGFloat = 2 * minimumTile + gap + 2 * padding

    /// Columns at a given panel width — never fewer than two.
    ///
    /// The width decides how many columns fit, never how narrow a tile may
    /// get. A panel that cannot hold another 144 pt column gets wider tiles
    /// instead of another one: the first version of this promised three
    /// columns at 400 pt, which is 120 pt a tile — narrower than the floor it
    /// had just argued for.
    public static func columns(for width: CGFloat) -> Int {
        let inner = width - padding * 2
        return max(2, Int(((inner + gap) / (minimumTile + gap)).rounded(.down)))
    }

    /// The width of one tile, for a widget that has to know.
    public static func tileWidth(for width: CGFloat) -> CGFloat {
        let count = CGFloat(columns(for: width))
        return (width - padding * 2 - gap * (count - 1)) / count
    }

    /// The size a widget actually gets, given what its module offers.
    ///
    /// **Clamped to the nearest, never dropped.** A module that stops offering
    /// `tall` in some build must not make a widget vanish out of somebody's
    /// panel: they arranged it, and a layout that quietly loses a member is a
    /// layout nobody trusts. Nearest is measured along `compact → wide → tall`,
    /// which is the order of how much room the answer takes.
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
    /// **A bar that is not drawn is `nil`, never its last measurement.** That
    /// is the whole reason this is a function rather than four lines in the
    /// card: the test was applied to the tab strip and not to the footer, so
    /// switching the last footer button off left 38 pt reserved under a footer
    /// that had stopped being drawn — and a grid that had exactly fitted began
    /// to scroll. SwiftUI does report the collapse; the writer's
    /// `guard measured > 0` throws that report away, which is correct there and
    /// is why the reader has to say which bars exist.
    ///
    /// A strip of 0 is a strip nothing has measured yet, not a strip with no
    /// room: it falls back to the ceiling, which is the only answer that draws
    /// a panel at all before the first geometry callback lands.
    ///
    /// **And a bar nobody draws takes its gap with it.** The card is three
    /// blocks with `gap` between them, of which only the tab strip is
    /// conditional, so the gaps drawn are two when the strip is there and one
    /// when it is not — measured, `PanelCardGapsProbe`. This read `gap * 2`
    /// unconditionally from the day it was four lines in the card, and the
    /// seeded panel is one tab, which is no strip: rendered at a 320 pt strip
    /// the card stopped 8 pt short of the strip it had been given and the grid
    /// scrolled for exactly those 8 pt. The footer block is the other case and is
    /// why the term hangs on `top` alone: it is drawn whether or not anything
    /// is in it, and an empty `VStack` still costs its neighbour's spacing, so
    /// `foot` says how tall it is and never whether its gap exists.
    public static func roomForGrid(strip: CGFloat, top: CGFloat?, foot: CGFloat?) -> CGFloat {
        let ceiling = min(strip > 0 ? strip : maximumHeight, maximumHeight)
        let gaps = gap * (top == nil ? 1 : 2)
        return max(minimumGrid, ceiling - (top ?? 0) - (foot ?? 0) - padding * 2 - gaps)
    }

    /// The least the grid is ever given: one row, rather than a sliver of one.
    public static let minimumGrid: CGFloat = 120

    /// The grid, as rows of indices into `sizes`.
    ///
    /// SwiftUI has no column span, so the grid is built as rows and a
    /// full-width widget is a row of its own. Written here rather than in the
    /// view because it is the packing rule — compact widgets fill a row and
    /// then start another, a full-width one interrupts whatever row was being
    /// filled — and a rule that can only be seen by looking at a panel is a
    /// rule nobody can change safely.
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
