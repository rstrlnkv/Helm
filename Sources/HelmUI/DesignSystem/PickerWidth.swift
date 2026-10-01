import AppKit

/// How wide a pop-up picker has to be to show its own labels. (A segmented
/// control is not one: it divides itself into equal segments, so its width is
/// the widest label times the count — nothing here answers for it, and the one
/// helper that did had no caller left once the log's level filter moved into
/// the window's toolbar.)
///
/// The rule editor sets a fixed width on every picker so its rows read as
/// columns rather than as ragged sentences. The widths were chosen against the
/// English labels and then translated past: at 13 pt the field picker was 150
/// while Spanish needs 184 for "Fecha de modificación", French 173.5, Russian
/// 156.5 — and English itself needs 155 for "Downloaded from". A fixed number
/// cannot survive a string change in eight languages, so the number is measured
/// instead of written down.
///
/// The chrome — the arrows, the bezel and the insets either side of the title —
/// is 48 pt at the system font size, constant to within half a point across the
/// labels this app actually shows (`NSPopUpButton.sizeToFit()` against the same
/// strings, 47.6–48.0). Adding it to the widest title is the same arithmetic
/// `sizeToFit` does, without building a button per row.
public enum HelmPickerWidth {
    static let chrome: CGFloat = 48

    /// The longest label's ink at the system font. A pop-up draws the longest
    /// label once, so both widths here are built on it.
    private static func widestInk(of labels: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
    }

    /// The width that fits the longest of `labels`, never below `minimum` — so
    /// a row of short words keeps the column it was designed with.
    public static func fitting(_ labels: [String], minimum: CGFloat) -> CGFloat {
        max(minimum, (widestInk(of: labels) + chrome).rounded(.up))
    }

    /// The same width for a pop-up whose items carry a **symbol** beside the
    /// title, which AppKit gives a column of its own.
    ///
    /// Measured with `NSPopUpButton.sizeToFit` over an SF Symbol on every item,
    /// against the eight translations of VPN's three notice modes: 15.1…21.6 pt
    /// more than `fitting` answers, so 22. Without it the arithmetic is short by
    /// a whole glyph and the control truncates the word it is set to — which is
    /// what `fitting` alone was about to do in four of the eight languages.
    ///
    /// The floor applies to the finished width, not to the titles: a caller's
    /// minimum is the column they drew, and a column measured before the symbol
    /// went in is a different number than the one they meant.
    public static func fittingSymbolled(_ labels: [String], minimum: CGFloat) -> CGFloat {
        max(minimum, fitting(labels, minimum: 0) + symbolColumn)
    }

    /// What a symbol beside the title costs — see `fittingSymbolled`.
    static let symbolColumn: CGFloat = 22
}
