import CoreGraphics

/// How much of its own square each SF Symbol actually paints.
///
/// A symbol is drawn at a point size, but how much ink sits inside that size is
/// the symbol designer's business, and it varies a lot. Rendered at 100 pt and
/// measured to the ink (`Scripts/design/measure-symbols.swift`):
///
/// | symbol          | ink, widest side |
/// |-----------------|------------------|
/// | `keyboard`      | 127 |
/// | `doc.on.doc`    | 125 |
/// | `moon.zzz.fill` | 115 |
/// | `trash`         | 111 |
/// | `wand.and.rays` | 109 |
/// | `shippingbox`   | 108 |
/// | `gearshape`     | 107 |
/// | `info.circle`   | 101 |
/// | `chart.pie`     | 101 |
/// | `lock.shield`   |  99 |
///
/// So one point size across the set is 28% of *visual* size between the largest
/// and the smallest — which is exactly what the sidebar looked like: the
/// keyboard and the two documents crowding their tiles while the shield and the
/// pie sat in space.
///
/// Correcting each symbol towards the mean makes them the same size to the eye,
/// which is what "the same size" is supposed to mean. The table is measured
/// rather than tuned; re-run the script when a symbol changes or one is added.
public enum SymbolInk {

    /// Ink measured at 100 pt, divided by 100.
    static let ratios: [String: CGFloat] = [
        "keyboard": 1.27,
        "doc.on.doc": 1.25,
        "moon.zzz.fill": 1.15,
        "trash": 1.11,
        "wand.and.rays": 1.09,
        "shippingbox": 1.08,
        "gearshape": 1.07,
        "info.circle": 1.01,
        "chart.pie": 1.01,
        "lock.shield": 0.99,
    ]

    /// The size everything is corrected towards: the mean of the table. Chosen
    /// as the mean rather than a round number so the correction is as small as
    /// it can be — an unmeasured symbol lands here and is no worse off than it
    /// was before.
    static let mean: CGFloat = 1.103

    /// The factor to multiply a point size by so this symbol paints the same
    /// amount as the rest. 1 for anything not in the table.
    public static func correction(for symbol: String) -> CGFloat {
        guard let ratio = ratios[symbol] else { return 1 }
        return mean / ratio
    }
}
