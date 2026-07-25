import SwiftUI

/// One colour vocabulary for the whole screen: the ring's wedge and the list
/// row for the same folder draw from the same swatch, which is what couples
/// the two panes visually. Keyed by path so a folder keeps its colour across
/// drill-downs and rescans.
enum DiskPalette {
    static let swatches: [Color] = [
        Color(hue: 0.58, saturation: 0.52, brightness: 0.82),   // teal
        Color(hue: 0.62, saturation: 0.45, brightness: 0.74),   // slate blue
        Color(hue: 0.53, saturation: 0.42, brightness: 0.72),   // sea
        Color(hue: 0.68, saturation: 0.38, brightness: 0.76),   // periwinkle
        Color(hue: 0.47, saturation: 0.40, brightness: 0.70),   // moss
        Color(hue: 0.72, saturation: 0.34, brightness: 0.72),   // lilac
        Color(hue: 0.09, saturation: 0.45, brightness: 0.80),   // sand
        Color(hue: 0.02, saturation: 0.42, brightness: 0.76),   // clay
    ]

    static func base(for path: String) -> Color {
        var hash: UInt64 = 5381
        for byte in path.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return swatches[Int(hash % UInt64(swatches.count))]
    }
}
