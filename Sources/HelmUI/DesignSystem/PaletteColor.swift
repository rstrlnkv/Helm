import SwiftUI
import AppKit
/// The active-tint palette for status icons — Calendar's, which is the system's.
///
/// **This reverses an earlier decision, and the reversal is measured.** The
/// palette used to be ten hand-picked hexes «not the system's», on the finding
/// that `systemRed` and `systemPink` are **22 units of sRGB apart** — two of
/// the ten swatches were the same colour, in the one control whose entire
/// content is which colour you picked. That finding was about a set containing
/// both a red and a pink. Calendar's set has neither problem: measured on this
/// Mac, the closest pair of the seven is orange/yellow at **103** units in
/// light and red/orange at **101** in dark, against 22 for the pair that
/// caused the rewrite.
///
/// What the system's colours buy that a hex cannot: they change with the
/// appearance. `systemRed` is `#FF383C` in light and `#FF4245` in dark, and the
/// icon they tint sits in the menu bar, which is the one surface that follows
/// the desktop rather than the app.
///
/// `mint`, `cyan` and `pink` are **retired, not removed**. They are somebody's
/// stored setting on a Mac that has already run Helm, and a case that stops
/// existing reads back as white with no explanation. They resolve; `offered` is
/// what the menu lists.
public enum PaletteColor: String, CaseIterable, Sendable {
    case white, red, orange, yellow, green, blue, purple, brown
    case mint, cyan, pink

    /// What the colour menu offers, in Calendar's order. White leads because it
    /// is the untinted default — `nil` and `"white"` are the same answer in
    /// `MenuBarIcon.nsColor(tintToken:)`.
    public static let offered: [PaletteColor] = [
        .white, .red, .orange, .yellow, .green, .blue, .purple, .brown,
    ]

    public var color: Color {
        switch self {
        // Not `.white`: on a light card that is 1.06:1 against the paper, held
        // apart only by a hairline ring. The lightest *grey*, which is what v3
        // spells `#f2f2f7` for, and it is the same in both appearances because
        // it stands for «no tint» rather than for a colour.
        case .white: return Color(hex: 0xF1F1F7)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .brown: return Color(nsColor: .systemBrown)
        // Retired: reachable only from a stored value written before the
        // palette became Calendar's.
        case .mint: return Color(nsColor: .systemMint)
        case .cyan: return Color(nsColor: .systemCyan)
        case .pink: return Color(nsColor: .systemPink)
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
        case .blue: return L("Blue")
        // Apple's own word, out of `CalendarUI.framework`'s table: Russian says
        // «Лиловый» where a translator reaching for the dictionary writes
        // «Фиолетовый», and this app is meant to read like the system.
        case .purple: return L("Purple")
        case .brown: return L("Brown")
        case .mint: return L("Mint")
        case .cyan: return L("Cyan")
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
