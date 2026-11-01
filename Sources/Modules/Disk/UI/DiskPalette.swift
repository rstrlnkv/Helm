import AppKit
import SwiftUI
import HelmUI

/// One colour vocabulary for the whole screen: the ring's wedge and the list
/// row for the same folder draw from the same swatch, which is what couples
/// the two panes visually. Keyed by path so a folder keeps its colour across
/// drill-downs and rescans.
///
/// Every colour a folder is drawn in is a **resolved** colour, not the swatch at
/// an opacity: `NSColor(Color)` is dynamic, so a blend made outside the
/// appearance block resolves against whatever appearance happens to be current.
/// A wedge or a row bar is the swatch blended into the window background inside
/// the block that knows which appearance it is drawing in, so the same folder is
/// the same colour in the ring and in the list, and each one can be measured.
///
/// Each swatch has four values: light and dark, each in the ordinary and the
/// Increase Contrast form. The ordinary pair is one colour in both appearances —
/// the eight colours this screen has always had. The increased pair is solved
/// for a floor: the outermost drawn ring, which is the faintest wedge, clears
/// 3:1 against the window background (a mark that carries meaning). Light goes
/// darker and dark goes lighter, by the smallest step that clears it; a dark
/// swatch that already clears it keeps its ordinary value. Measured against
/// `windowBackgroundColor`: white in light, #1E1E1E in dark.
@MainActor
enum DiskPalette {
    /// Light and dark of one setting, as 0xRRGGBB in sRGB.
    private struct Pair { let light: UInt32; let dark: UInt32 }
    private struct Swatch { let ordinary: Pair; let increased: Pair }

    /// Teal, slate, sea, periwinkle, moss, lilac, sand, clay — in the order the
    /// path's hash indexes them.
    private static let swatches: [Swatch] = [
        Swatch(ordinary: Pair(light: 0x649DD1, dark: 0x649DD1), increased: Pair(light: 0x487096, dark: 0x649DD1)),
        Swatch(ordinary: Pair(light: 0x6880BD, dark: 0x6880BD), increased: Pair(light: 0x576B9F, dark: 0x6E85BF)),
        Swatch(ordinary: Pair(light: 0x6AAAB8, dark: 0x6AAAB8), increased: Pair(light: 0x48737D, dark: 0x6AAAB8)),
        Swatch(ordinary: Pair(light: 0x7E78C2, dark: 0x7E78C2), increased: Pair(light: 0x6A65A3, dark: 0x837EC4)),
        Swatch(ordinary: Pair(light: 0x6BB3A6, dark: 0x6BB3A6), increased: Pair(light: 0x46756C, dark: 0x6BB3A6)),
        Swatch(ordinary: Pair(light: 0x8D79B8, dark: 0x8D79B8), increased: Pair(light: 0x746397, dark: 0x8F7CB9)),
        Swatch(ordinary: Pair(light: 0xCCA270, dark: 0xCCA270), increased: Pair(light: 0x826747, dark: 0xCCA270)),
        Swatch(ordinary: Pair(light: 0xC27A70, dark: 0xC27A70), increased: Pair(light: 0x955E57, dark: 0xC27A70)),
    ]

    // MARK: - The swatch, and the weights it is drawn at

    /// How much of the swatch a ring keeps, per ring out from the centre: the
    /// ring recedes by this much each step.
    static let ringStep = 0.14
    /// The fraction of the swatch in a list row's bar, light and dark: one
    /// opacity does not carry the same weight on both, and the bar measures
    /// about 1.10:1 over a white list at 0.10.
    private static let barWeight = (light: 0.28, dark: 0.10)
    /// …and under the pointer. The hovered row's wash is drawn beneath its bar.
    private static let hoverWeight = (light: 0.38, dark: 0.16)

    /// The two layers of a hovered row's bar, composited once:
    /// `1 − (1 − hover)(1 − bar)`.
    private static let hoveredBarWeight = (
        light: 1 - (1 - hoverWeight.light) * (1 - barWeight.light),
        dark: 1 - (1 - hoverWeight.dark) * (1 - barWeight.dark))

    /// The swatch for a folder: its dot in the list, and the hovered wedge.
    static func base(for path: String, increased: Bool) -> Color {
        full[increased ? 1 : 0][index(of: path)]
    }

    /// The wedge of `ring` (0 is the innermost): the swatch, receding.
    static func wedge(for path: String, ring: Int, increased: Bool) -> Color {
        wedges[increased ? 1 : 0][min(max(ring, 0), wedges[0].count - 1)][index(of: path)]
    }

    /// The bar behind a list row; `hovered` is the bar over the row's wash.
    static func rowBar(for path: String, hovered: Bool, increased: Bool) -> Color {
        bars[increased ? 1 : 0][hovered ? 1 : 0][index(of: path)]
    }

    /// The wash across a hovered row, under its bar.
    static func rowHover(for path: String, increased: Bool) -> Color {
        hovers[increased ? 1 : 0][index(of: path)]
    }

    private static func index(of path: String) -> Int {
        var hash: UInt64 = 5381
        for byte in path.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % UInt64(swatches.count))
    }

    // MARK: - The neighbours

    /// Free space in the ring: quiet, so real data reads first.
    static let freeSpace = Color.primary.opacity(0.06)
    /// The folded bucket of small items.
    static let otherItems = Color.primary.opacity(0.10)
    /// A folder macOS would not let the scan open: the system orange, blended
    /// into the window background inside the appearance
    /// (`HelmSurface.chosenWash`). The ring gets no `noAccess` flag today
    /// (`DiskViewModel.node(from:)`), so only the list row shows the warning.
    static let noAccess = HelmSurface.chosenWash(.orange)
    /// A file's dot in the list, which has no swatch of its own.
    static let fileDot = Color.secondary.opacity(0.5)

    /// The used-against-total bar of a volume: the track under it, and the part
    /// that is used.
    static let capacityTrack = Color.primary.opacity(0.10)
    static let capacityUsed = Color.accentColor.opacity(0.75)

    // MARK: - Built once

    /// Stored, not built per access: a `Color` made on demand never equals
    /// itself, and SwiftUI compares inputs the same way (`HelmSignal`'s reason).
    /// Indexed `[increased][…][swatch]`.
    private static let full = table([(light: 1, dark: 1)]).map { $0[0] }
    private static let wedges = table((0..<RingView.visibleRings).map {
        (light: 1 - Double($0) * ringStep, dark: 1 - Double($0) * ringStep)
    })
    private static let bars = table([barWeight, hoveredBarWeight])
    private static let hovers = table([hoverWeight]).map { $0[0] }

    private static func table(_ weights: [(light: Double, dark: Double)]) -> [[[Color]]] {
        [false, true].map { increased in
            weights.map { weight in
                swatches.map { blended($0, increased: increased, weight: weight) }
            }
        }
    }

    /// The swatch with `weight` of its colour and the rest window background,
    /// resolved inside the appearance it is drawn in. A weight of 1 is the
    /// swatch itself.
    private static func blended(_ swatch: Swatch, increased: Bool,
                                weight: (light: Double, dark: Double)) -> Color {
        let pair = increased ? swatch.increased : swatch.ordinary
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let ink = srgb(dark ? pair.dark : pair.light)
            let fraction = dark ? weight.dark : weight.light
            guard fraction < 1 else { return ink }
            var out = ink
            appearance.performAsCurrentDrawingAppearance {
                guard let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) else { return }
                // Component-wise in sRGB: `NSColor.blended(withFraction:of:)` mixes in
                // Generic RGB and draws lighter than the arithmetic the swatches were
                // solved with, enough to put the Increase Contrast ring under 3:1.
                func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * fraction }
                out = NSColor(srgbRed: mix(base.redComponent, ink.redComponent),
                              green: mix(base.greenComponent, ink.greenComponent),
                              blue: mix(base.blueComponent, ink.blueComponent), alpha: 1)
            }
            return out
        })
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
