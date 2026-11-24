import AppKit

/// How wide a pop-up picker has to be to show its own labels. A segmented
/// control is not one: it divides itself into equal segments.
///
/// The rule editor sets a fixed width on every picker so its rows read as
/// columns. A number written down cannot survive a string change in eight
/// languages (Spanish needs far more than English for the same field), so the
/// width is measured instead.
///
/// The chrome (arrows, bezel and the insets beside the title) is 48 pt at the
/// system font size, constant to within half a point across this app's labels
/// by `NSPopUpButton.sizeToFit()`. Adding it to the widest title is the same
/// arithmetic `sizeToFit` does, without building a button per row.
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

    /// The width that fits the longest of `labels`, never below `minimum`, so
    /// a row of short words keeps the column it was drawn with.
    public static func fitting(_ labels: [String], minimum: CGFloat) -> CGFloat {
        max(minimum, (widestInk(of: labels) + chrome).rounded(.up))
    }

    /// The same width for a pop-up whose items carry a **symbol** beside the
    /// title, which AppKit gives a column of its own.
    ///
    /// Measured with `NSPopUpButton.sizeToFit` over an SF Symbol on every item,
    /// against the eight translations of VPN's three notice modes: up to 21.6 pt
    /// more than `fitting` answers, so 22. Without it the control truncates the
    /// word it is set to.
    ///
    /// The floor applies to the finished width, not to the titles: a caller's
    /// minimum is the column they drew.
    public static func fittingSymbolled(_ labels: [String], minimum: CGFloat) -> CGFloat {
        max(minimum, fitting(labels, minimum: 0) + symbolCost)
    }

    /// What a symbol beside the title costs — see `fittingSymbolled`.
    static let symbolCost: CGFloat = 22
}
