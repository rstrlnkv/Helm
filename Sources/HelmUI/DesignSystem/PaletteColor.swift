import SwiftUI
import AppKit
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

    public var swatchImage: NSImage {
        // `self.color` is read out here rather than inside the drawing block:
        // the block is `@Sendable` and capturing the case itself makes the
        // compiler ask questions about a type it has no reason to.
        let fill = NSColor(color)
        let side: CGFloat = 12
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            fill.setFill()
            disc.fill()
            // The same hairline the swatches always had: `.white` is a pale
            // grey on a pale menu and needs an edge to be a disc at all.
            NSColor.labelColor.withAlphaComponent(0.20).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            return true
        }
        // A template image is recoloured by the menu, which is exactly what has
        // to not happen here.
        image.isTemplate = false
        return image
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

    /// A filled circle in this colour, as an image.
    ///
    /// **Not an SF Symbol with a `foregroundStyle` on it.** A `Picker` with the
    /// menu style is drawn by AppKit as an `NSMenu`, and an `NSMenuItem` takes
    /// an *image*: the tint SwiftUI is asked to apply to a symbol inside one is
    /// dropped, which is why the ten colours arrived as ten identical grey dots
    /// and then as no dots at all. Drawn here and handed over already coloured,
    /// there is nothing left for the menu to strip.
    ///
    /// `isTemplate` stays false for the same reason — a template image is
    /// recoloured by the menu, which is exactly what has to not happen.
}
