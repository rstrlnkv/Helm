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
