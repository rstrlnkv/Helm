import AppKit

/// How wide a pop-up button has to be to show its own labels.
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

    /// The width that fits the longest of `labels`, never below `minimum` — so
    /// a row of short words keeps the column it was designed with.
    public static func fitting(_ labels: [String], minimum: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(minimum, (widest + chrome).rounded(.up))
    }

    /// A segmented control's chrome is per *segment*, not per control: about
    /// 26 pt around each label. Hard-coded widths are what this type exists to
    /// end — 260 was 3 pt from clipping in Russian and 110 pt too wide in
    /// Chinese, and `.fixedSize()` is not the answer either, because SwiftUI's
    /// fitting size for a segmented picker comes back at 404 pt in Russian.
    public static func segmented(_ labels: [String], minimum: CGFloat = 180) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let ink = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .reduce(0, +)
        return max(minimum, (ink + 26 * CGFloat(labels.count)).rounded(.up))
    }
}
