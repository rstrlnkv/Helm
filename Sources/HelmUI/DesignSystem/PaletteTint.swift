import AppKit
import SwiftUI

/// A tint the person chose themselves, as it travels: `#RRGGBB`.
///
/// The palette is eight named colours and a stored setting is one of their
/// names. A free choice cannot be a name, so it is the value — and the two
/// have to live in one string, because everything that draws the menu-bar icon
/// takes a single optional token and always has.
///
/// **sRGB, written and read.** `NSColorPanel` hands back whatever space the
/// person picked in, and a `deviceRGB` colour stored as three bytes and read
/// as sRGB is a different colour on the next launch. The conversion happens
/// once, here, on the way in.
public enum PaletteTint {
    /// The `#` is what tells a value from a name. No palette case starts with
    /// one, so the two can never be confused however the file was edited.
    public static func token(for color: Color) -> String {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()),
                      Int((srgb.blueComponent * 255).rounded()))
    }

    /// `nil` for anything that is not a custom token — a palette name, an empty
    /// string, junk from a hand-edited plist. The caller decides what to do
    /// with that; every one of them already had a fallback.
    public static func custom(_ token: String?) -> NSColor? {
        guard let token, token.hasPrefix("#") else { return nil }
        let digits = token.dropFirst()
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }
}
