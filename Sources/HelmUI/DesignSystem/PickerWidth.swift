import AppKit

/// How wide a picker has to be to show its own labels — a pop-up's width and a
/// segmented control's, which are different arithmetic on the same measurement.
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
    static let segmentChrome: CGFloat = 24

    /// The longest label's ink at the system font. Both widths here are built on
    /// it — a pop-up draws the longest label once, a segmented control draws its
    /// width once per segment, and that difference is the whole difference
    /// between the two functions below.
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

    /// A segmented control's chrome is per *segment*, not per control: 24 pt
    /// around each label, calibrated across eleven label sets, four scripts and
    /// two-to-four segments.
    ///
    /// And every segment is as wide as the **widest** label, because that is how
    /// the control divides itself up — so the width is `count × (widest + 24)`,
    /// never the labels added together. Adding them was this helper's own
    /// arithmetic until 2026-08-11, and it is a pop-up's: it agrees only when
    /// every label is the same length, which English nearly is and Russian is
    /// not. The log's three levels were handed 263 pt where the control asks
    /// 403.5, and nothing said so, because the number came from the helper whose
    /// whole job was to end widths chosen by hand.
    ///
    /// Rounded up per segment, and to the half point, because that is the grid
    /// AppKit lays a segment out on: over 400 random label sets in four scripts
    /// this answers `sizeToFit` **exactly**, never a half point short and never a
    /// half point over. Rounding at the end instead came out 0.5 pt short in five
    /// of eighteen real label sets — and a computed width that comes out short is
    /// worse than a written one, because it looks measured.
    ///
    /// There is no minimum to pass, either: a floor above what the labels ask for
    /// is the slack this arithmetic exists to remove, and it centres the control
    /// in its own frame — which walks the left edge of the row away from the
    /// gutter every row below it starts at.
    public static func segmented(_ labels: [String]) -> CGFloat {
        let segment = ((widestInk(of: labels) + segmentChrome) * 2).rounded(.up) / 2
        return segment * CGFloat(labels.count)
    }
}
