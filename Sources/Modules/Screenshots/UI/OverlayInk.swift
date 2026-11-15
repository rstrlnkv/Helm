import AppKit
import HelmUI

/// The overlay's translucent and accent inks on the frozen picture, the one table of them; `Spotlights.color` is the export's own, and pure white and black stay with the layer that draws them. Not the kit's tokens, which are the opposite of a window's
/// ground: the ground here is whatever was on the screen, so an ink holds on white and on black alike and is the same in both
/// appearances; only the accent follows the appearance. Under Increase Contrast an ink is stronger, the accent itself is not; a flag since the appearance will not
/// say so (`HelmAccessibility`). Resolved once, when a view is built, and never in `apply`: a scene is applied on every pointer event.
struct OverlayInk {
    let accent, wash, dim, line, lineEdge, handleEdge, strip, stripEdge, ticks, pill, grid: CGColor
    /// A shape's outline under Increase Contrast, white over a dark one, and nil otherwise; one ink is 1:1 on a ground of its own value.
    let contrastEdge, contrastEdgeUnder: CGColor?

    init(increased: Bool, appearance: NSAppearance) {
        var accent = NSColor.controlAccentColor.cgColor
        var wash = accent
        appearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.cgColor
            wash = NSColor.controlAccentColor.withAlphaComponent(increased ? 0.40 : 0.28).cgColor
        }
        self.accent = accent
        self.wash = wash
        // Reduce Transparency: a plate behind words stops showing the picture through it. The other inks are marks on the picture.
        let reduced = HelmAccessibility.system.reducedTransparency
        dim = Self.black(increased ? 0.60 : 0.45)
        line = NSColor.white.withAlphaComponent(increased ? 1 : 0.85).cgColor
        lineEdge = Self.black(increased ? 0.85 : 0.6)
        handleEdge = Self.black(increased ? 0.85 : 0.6)
        strip = NSColor.white.withAlphaComponent(increased ? 0.8 : 0.5).cgColor
        stripEdge = Self.black(increased ? 0.5 : 0.28)
        ticks = Self.black(increased ? 0.75 : 0.45)
        pill = Self.black(reduced ? 1 : (increased ? 0.8 : 0.6))
        grid = Self.black(increased ? 0.25 : 0.12)
        contrastEdge = increased ? line : nil
        contrastEdgeUnder = increased ? lineEdge : nil
    }

    private static func black(_ alpha: CGFloat) -> CGColor { NSColor.black.withAlphaComponent(alpha).cgColor }

    /// The same in every case but one: the plate under a label, white on it holds on any page; solid under Reduce Transparency.
    static var plate: CGColor { black(HelmAccessibility.system.reducedTransparency ? 1 : 0.7) }
    /// The eraser's circle, a cursor drawn once.
    static var eraserFill: NSColor { .white.withAlphaComponent(0.55) }
    static var eraserEdge: NSColor { .black.withAlphaComponent(0.55) }
}
