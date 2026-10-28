import AppKit
import SwiftUI

/// The fills a Helm surface is drawn with: a small set over `Color.primary`, no
/// border among them, and what a tint is blended into (`rowWashOpacity`, `chosenWash(_:)`).
public enum HelmSurface {
    /// Measured against a real `Form` section on the same background: at 0.05
    /// the card sat 10 L from the panel where the system's section sits 7, in
    /// both themes — a heavier card claiming to be the same surface.
    public static let cardFill = Color.primary.opacity(0.035)
    /// A recessed area *inside* a card: console output, an unselected swatch.
    public static let wellFill = Color.primary.opacity(0.05)
    /// The same idea on a panel card, which already sits at 0.06 — a well
    /// there has to be heavier to read as recessed at all.
    public static let onPanelFill = Color.primary.opacity(0.08)
    /// A card on the panel's glass. Heavier than `cardFill` because glass
    /// gives less to sit against than a window background does.
    public static let panelCardFill = Color.primary.opacity(0.06)
    public static let hairline = Color.primary.opacity(0.10)
    /// The selected tab on the panel's glass: a fill and nothing else. A
    /// material here was glass drawn on glass, which is the one thing Liquid
    /// Glass asks a design not to do, and its shadow carried nothing.
    public static let panelSelection = Color.primary.opacity(0.12)
    /// The plate `HelmBarAppearance.flat` is named for.
    public static let barPlate = Color.primary.opacity(0.05)
    /// The pick on `barPlate`.
    public static let barPick = Color.primary.opacity(0.10)
    /// The selected row of the sidebar (`HelmSidebarRow`). The owner's value; `barPick` holds the same
    /// number, and `wellFill` and `barPlate` hold `rowHover`'s, so they move independently.
    public static let rowSelection = Color.primary.opacity(0.10)
    /// The hovered row of the sidebar: half of `rowSelection`.
    public static let rowHover = Color.primary.opacity(0.05)
    /// The wash under a log row that carries a signal: the row's own signal colour at this opacity.
    public static let rowWashOpacity = 0.06

    /// What a chosen pill (`HelmPillChoice`) is filled with: `tint` blended 0.22 of the way into the window
    /// background, opaque.
    ///
    /// Blended **inside** the appearance rather than drawn as `tint.opacity(0.22)`: `NSColor(Color)` returns a
    /// dynamic colour, so a blend made one line outside the block resolves against whatever appearance happens
    /// to be current — the same trap `HelmMetricStrip` documents. It also means the fill is a colour that can
    /// be measured, rather than one that depends on what it lands on. Build it once and keep it: each call
    /// allocates a colour and a provider closure.
    public static func chosenWash(_ tint: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            var out = NSColor.windowBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                guard let ink = NSColor(tint).usingColorSpace(.sRGB),
                      let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
                      let blended = base.blended(withFraction: 0.22, of: ink)
                else { return }
                out = blended
            }
            return out
        })
    }
}
