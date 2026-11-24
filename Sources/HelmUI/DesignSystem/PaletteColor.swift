import SwiftUI
import AppKit
/// The active-tint palette for status icons — Calendar's, which is the system's.
///
/// The tinted colours are far apart in sRGB, the closest pair about 100 units
/// in either appearance, so no two swatches read as one colour (`systemRed` and
/// `systemPink`, 22 units apart, would). And the system's colours change with
/// the appearance, which matters in the menu bar, the one surface that follows
/// the desktop rather than the app.
///
/// `mint`, `cyan` and `pink` are **retired, not removed**: they are somebody's
/// stored setting, and a case that stops existing reads back as white with no
/// explanation. They resolve; `offered` is what the menu lists.
public enum PaletteColor: String, CaseIterable, Sendable {
    case white, red, orange, yellow, green, blue, purple, brown
    case mint, cyan, pink

    /// What the colour menu offers, in Calendar's order. White leads because it
    /// is the untinted default — `nil` and `"white"` are the same answer in
    /// `MenuBarIcon.nsColor(forTintToken:)`.
    public static let offered: [PaletteColor] = [
        .white, .red, .orange, .yellow, .green, .blue, .purple, .brown,
    ]

    /// The colour as the menu-bar glyph and its text are drawn: the system's own,
    /// and plain white for `.white` — the untinted glyph, not the swatch's grey.
    /// The one table both `color` and `MenuBarIcon.nsColor(forTintToken:)` read, and
    /// exhaustive, so a new case cannot reach either as white by default.
    public var nsColor: NSColor {
        switch self {
        case .white: return .white
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .brown: return .systemBrown
        // Retired: reachable only from a stored value.
        case .mint: return .systemMint
        case .cyan: return .systemCyan
        case .pink: return .systemPink
        }
    }

    var color: Color {
        // Not `.white`: on a light card that is 1.06:1 against the paper, held
        // apart only by a hairline ring. The lightest *grey*, `#f1f1f7`, the same
        // in both appearances because it stands for «no tint» rather than for a colour.
        if self == .white { return Color(hex: 0xF1F1F7) }
        return Color(nsColor: nsColor)
    }
    /// The colour's name in the user's language: on a swatch the colour itself
    /// is the only other signal there is.
    public var label: String {
        switch self {
        case .white: return L(.white)
        case .red: return L(.red)
        case .orange: return L(.orange)
        case .yellow: return L(.yellow)
        case .green: return L(.green)
        case .blue: return L(.blue)
        // Apple's own word, out of `CalendarFoundation.framework`'s table,
        // which is where Calendar's colour names live: Russian says «Лиловый»
        // where a translator reaching for the dictionary writes «Фиолетовый»,
        // and this app is meant to read like the system.
        case .purple: return L(.purple)
        case .brown: return L(.brown)
        case .mint: return L(.mint)
        case .cyan: return L(.cyan)
        case .pink: return L(.pink)
        }
    }

    /// A filled circle in this colour, as an image.
    ///
    /// Not an SF Symbol with a `foregroundStyle`: a menu-style `Picker` is an
    /// `NSMenu`, and an `NSMenuItem` takes an image and drops a SwiftUI tint, so
    /// the swatch is handed over already coloured. Not a template either, which
    /// the menu would recolour.
    public var swatchImage: NSImage { Self.swatchImage(of: NSColor(color)) }

    /// A disc in an arbitrary colour, drawn as the palette's own are
    /// (`swatchImage`). The colour is taken as an `NSColor` rather than the
    /// case: the drawing block is `@Sendable` and capturing the case itself
    /// makes the compiler ask questions about a type it has no reason to.
    public static func swatchImage(of fill: NSColor) -> NSImage {
        let side: CGFloat = 12
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            fill.setFill()
            disc.fill()
            // A hairline: `.white` is a pale grey on a pale menu and needs an
            // edge to be a disc at all.
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
}
