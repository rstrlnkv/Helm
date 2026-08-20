import AppKit

/// Whether the panel's tab strip has room for its tabs' names.
///
/// This is the answer that replaced a setting. «Tab labels» offered text, glyph
/// and both, and `TabLabelStyle`'s own documentation said why that was the wrong
/// shape: the right one «depends on things the app cannot see: how many tabs
/// there are, how long their names came out, and whether the person named them
/// at all» — and every one of those three is in `PanelLayout`. The panel is a
/// fixed 320 pt, so the question has an answer rather than a taste, and the strip
/// that would have needed the setting is the one that is already too full to read.
///
/// **Every tab or none.** A strip where one tab shows a word and the next shows a
/// symbol is not a strip, so the measurement is of the whole row: the names fit,
/// or none of them is drawn.
public enum TabStripFit {

    /// 8 pt of padding either side of a tab's content — `PanelTabStrip`'s own
    /// `.padding(.horizontal, 8)`.
    static let padding: CGFloat = 16
    /// The strip's `HStack(spacing: 4)`.
    static let gap: CGFloat = 4
    /// A 13 pt SF Symbol's square, which is what a glyph-only tab holds.
    static let glyph: CGFloat = 15
    /// The «+» that makes a tab: a 12 pt symbol in the same 8 pt padding.
    static let addButton: CGFloat = 28

    /// The style the strip should draw.
    ///
    /// **One array of pairs, not a name array beside a glyph array.** Two
    /// parallel arrays let a caller hand over four names and three glyphs, and
    /// the answer to that is a `guard` returning something plausible — an
    /// unrepresentable state is cheaper than a defended one.
    ///
    /// - Parameter widthOfName: a seam, so the arithmetic can be tested without
    ///   this Mac's font deciding the answer. Production takes the default,
    ///   which measures at the font the strip draws.
    public static func style(tabs: [(title: String, glyph: String?)], editing: Bool,
                             available: CGFloat,
                             widthOfName: (String) -> CGFloat = TabStripFit.ink) -> TabLabelStyle {
        guard !tabs.isEmpty else { return .text }
        let names = width(of: tabs.map { widthOfName($0.title) + padding }, editing: editing)
        if names <= available { return .text }
        // Names that do not fit are only worth giving up if every tab has
        // something to be recognised by. One tab without a glyph would draw as
        // an empty padded button, which is the state the deleted pop-up could
        // be put into by hand.
        return tabs.allSatisfy { $0.glyph != nil } ? .glyph : .text
    }

    /// A row of tabs of the given widths, with the gaps between them and the
    /// «+» when the mode that offers it is on.
    private static func width(of tabs: [CGFloat], editing: Bool) -> CGFloat {
        let count = tabs.count + (editing ? 1 : 0)
        let gaps = CGFloat(max(0, count - 1)) * gap
        return tabs.reduce(0, +) + gaps + (editing ? addButton : 0)
    }

    /// What a name costs at the font the strip sets it in.
    public static func ink(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: HelmText.rowDetailNSFont]).width
    }
}
