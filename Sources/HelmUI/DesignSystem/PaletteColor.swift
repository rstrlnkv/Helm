import SwiftUI
/// The fixed active-tint palette for status icons (Keep Awake picks from this).
public enum PaletteColor: String, CaseIterable, Sendable {
    case white, red, orange, yellow, green, mint, cyan, blue, purple, pink
    /// The redesign's own ten, not the system's.
    ///
    /// Measured off a capture: `Color.red` and `Color.pink` are `systemRed` and
    /// `systemPink`, and on a 20 pt circle they are **22 units of sRGB apart**
    /// — identical red channel, six of green, twenty-one of blue — in light and
    /// in dark alike. Two of the ten swatches were the same colour, in the one
    /// control whose entire content is which colour you picked. v3's pair is 78
    /// apart because its pink is a magenta.
    ///
    /// And `.white` is 255,254,255 on a 248 card — 1.06:1, held apart only by a
    /// hairline ring measuring 1.08:1. v3 spells that slot `#f2f2f7` precisely
    /// so it reads as the lightest *grey* rather than as the paper.
    public var color: Color {
        switch self {
        case .white: return Color(hex: 0xF2F2F7)
        case .red: return Color(hex: 0xE5484D)
        case .orange: return Color(hex: 0xDE7A21)
        case .yellow: return Color(hex: 0xE5B62C)
        case .green: return Color(hex: 0x2EA05A)
        case .mint: return Color(hex: 0x4CC7A4)
        case .cyan: return Color(hex: 0x3AA8C1)
        case .blue: return Color(hex: 0x2F7CF6)
        case .purple: return Color(hex: 0x8B5CF6)
        case .pink: return Color(hex: 0xE0559A)
        }
    }
    /// The colour's name in the user's language. It was `rawValue.capitalized`
    /// — the one user-visible string in the app that skipped `L()` — and on a
    /// swatch the colour itself is the only other signal there is.
    public var label: String {
        switch self {
        case .white: return L("White")
        case .red: return L("Red")
        case .orange: return L("Orange")
        case .yellow: return L("Yellow")
        case .green: return L("Green")
        case .mint: return L("Mint")
        case .cyan: return L("Cyan")
        case .blue: return L("Blue")
        case .purple: return L("Purple")
        case .pink: return L("Pink")
        }
    }
}

private extension Color {
    /// The mockups carry these as hex and so does every other design token in
    /// this house; spelled as three doubles they stop being greppable against
    /// the stylesheet they came from.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
