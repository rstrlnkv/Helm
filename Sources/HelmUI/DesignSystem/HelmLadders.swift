import CoreGraphics

/// **Space has one ladder: 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40 pt.**
///
/// One ladder, because a value chosen by eye at each site is one decision
/// taken many times, and nobody can see the difference between 10 and 12 pt.
/// The steps are close together where they are small, because 2 pt matters at
/// 4 pt and does not at 40, and above that each is about half again the one
/// below, so a value chosen by eye has one obvious neighbour to round to. A
/// number off the ladder is a number somebody has to argue for.
public enum HelmSpace {
    /// Hairline separation: a glyph from the word it belongs to.
    public static let s1: CGFloat = 2
    /// Inside a control: a badge's own padding.
    public static let s2: CGFloat = 4
    /// A label from its value.
    public static let s3: CGFloat = 6
    /// Between rows of one list.
    public static let s4: CGFloat = 8
    /// A card's inner padding, and the gap between two cards.
    public static let s5: CGFloat = 12
    /// Between the blocks of one section.
    public static let s6: CGFloat = 18
    /// Between sections of a page.
    public static let s7: CGFloat = 28
    /// A page's own margins, and the space under its header.
    public static let s8: CGFloat = 40
}

/// **A corner has one ladder: 6 · 10 · 14 · 16 · 26 pt.**
///
/// Each step names the thing it belongs to rather than a size: the call site
/// should say what it is drawing, not how round it wants it.
public enum HelmRadius {
    /// A control: a button, a field, a segment.
    public static let ctl: CGFloat = 6
    /// The one card: 10, so it reads apart from SwiftUI's own grouped-`Form`
    /// section card, which is 12 and nobody here's to change.
    public static let card: CGFloat = 10
    /// A frame around cards: the panel's own card and the well inside it.
    public static let frame: CGFloat = 14
    /// The settings window's corner on macOS 27, held here rather than read from the system. It matches the
    /// corner of System Settings' window as read off screenshots. The card is cut from it
    /// (`ShellGeometry.cardRadius(windowRadius:)`), 12 pt.
    public static let window: CGFloat = 16
    /// The panel. Big because it hangs off the menu bar with nothing around it.
    public static let panel: CGFloat = 26
}
