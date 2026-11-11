import SwiftUI

/// The look values only Layout draws: what was typed, the badge preview's grid, the tall tile's fortnight.
enum LayoutLook {
    /// A typed word, monospaced so a slip and its fix line up letter for letter.
    static let typed = Font.system(.body, design: .monospaced)
    /// The slot a badge sits in, in the preview's tile.
    static let badgeSlot: CGFloat = 26
    /// The narrowest a preview tile goes before the grid drops to fewer columns.
    static let previewTile: CGFloat = 132
    static let sparkHeight: CGFloat = 26
    /// A day with nothing still draws this tall, so the fortnight reads as a row of days.
    static let sparkFloor: CGFloat = 2
    static let sparkCorner: CGFloat = 1.5
    static let sparkToday = 0.9
    static let sparkPast = 0.35
}
