import AppKit

/// What a striped list's rows draw at, with `Section` headers left out.
///
/// Row 0 is a header on any striped list that opens with a `Section` —
/// `isGroupRowStyle` is AppKit's own way to tell the two apart, and
/// a check that read `rect(ofRow: 0)` blindly would pass by comparing the
/// table's `rowHeight` against a header's height rather than a row's.
public enum StripedListPitch {
    /// Every mounted row that is not a `Section` header, top to bottom.
    public static func realRowHeights(in table: NSTableView) -> [CGFloat] {
        (0..<table.numberOfRows).compactMap { row in
            if table.rowView(atRow: row, makeIfNecessary: false)?.isGroupRowStyle == true { return nil }
            let height = table.rect(ofRow: row).height
            return height > 0 ? height : nil
        }
    }
}
