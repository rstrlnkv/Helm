import AppKit
import SwiftUI

/// A dynamic colour resolved in a named appearance, the way a window draws it.
///
/// Unresolved, the reading is about whatever appearance the test process happens to be in.
public enum Contrast {

    /// Resolves a dynamic colour the way the window will.
    public static func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> NSColor {
        var out: NSColor = .clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB)!
        }
        return out
    }
}
