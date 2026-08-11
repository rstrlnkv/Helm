import AppKit
import SwiftUI

/// WCAG contrast, measured the way a window draws it rather than on paper.
///
/// Two things make this arithmetic easy to get wrong in a way that always
/// passes, and both were paid for once already (`HelmText`'s comment carries the
/// story). **A dynamic colour has to be resolved in an appearance**, or the
/// reading is about whatever appearance the test process happens to be in. And
/// **a translucent ink has to be composited onto the surface it lands on**: read
/// raw, `Color.primary.opacity(0.30)` is still `labelColor`, which measures
/// 14.94:1 against the window in light — so every opacity clears every
/// threshold, and the check cannot fail.
///
/// The same four functions were spelled by hand in `SignalColourContrastTests`,
/// `MetricTintTests`, `ChannelInkTests` and `ModuleTintTests`, and only two of
/// the four composited. `Scripts/design/contrast.swift` is the same arithmetic
/// again on the measuring side, and the two agree token for token.
public enum Contrast {

    /// Body text, and anything Helm treats as body text.
    public static let bodyFloor = 4.5
    /// A mark that carries meaning: a chevron, a dot, an icon beside a word.
    public static let markFloor = 3.0

    public static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Paints `ink` — which carries the alpha — onto `surface` and returns what
    /// lands there.
    public static func over(_ ink: NSColor, _ surface: NSColor) -> NSColor {
        let f = ink.usingColorSpace(.sRGB)!, b = surface.usingColorSpace(.sRGB)!
        let a = f.alphaComponent
        func mix(_ i: CGFloat, _ s: CGFloat) -> CGFloat { i * a + s * (1 - a) }
        return NSColor(srgbRed: mix(f.redComponent, b.redComponent),
                       green: mix(f.greenComponent, b.greenComponent),
                       blue: mix(f.blueComponent, b.blueComponent),
                       alpha: 1)
    }

    /// Resolves a dynamic colour the way the window will.
    public static func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> NSColor {
        var out: NSColor = .clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB)!
        }
        return out
    }

    /// The same, for one of macOS's own colours.
    public static func system(_ keyPath: KeyPath<NSColor.Type, NSColor>,
                              _ appearance: NSAppearance.Name) -> NSColor {
        var out: NSColor = .clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = NSColor.self[keyPath: keyPath].usingColorSpace(.sRGB)!
        }
        return out
    }

    public static func luminance(_ color: NSColor) -> Double {
        let s = color.usingColorSpace(.sRGB)!
        func linear(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(s.redComponent)
             + 0.7152 * linear(s.greenComponent)
             + 0.0722 * linear(s.blueComponent)
    }
}
