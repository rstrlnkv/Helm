import SwiftUI

/// One vocabulary of motion for the whole app.
///
/// Springs, not ease curves: an eased move reads as "smoothed", a spring reads
/// as physical, and that difference is most of what makes Apple's own
/// disclosure and morph animations feel alive.
///
/// The exception is anything whose height is measured and clipped. A bouncy
/// spring overshoots its target, and an overshooting height clips its own
/// content for a frame or two — exactly the class of panel glitch
/// ARCHITECTURE.md warns about. Those use `disclosure`, which is a spring with
/// the bounce set to zero: physical timing, no overshoot.
public enum HelmMotion {
    /// Opening and closing measured-height sections. No overshoot by design.
    public static let disclosure = Animation.smooth(duration: 0.30)

    /// Small state changes: reordering rows, toggling a filter, moving a
    /// selection. A touch of spring so it doesn't feel mechanical.
    public static let interface = Animation.snappy(duration: 0.22)

    /// Large morphs where the shape itself changes — a pill growing into a
    /// card. Bouncy enough to read as fluid.
    public static let emphasis = Animation.spring(response: 0.42, dampingFraction: 0.78)


    /// Steady rotation (the About page's bezel while a check runs) — the one
    /// place a linear curve is correct, because the motion has no destination.
    public static func steadyRotation(seconds: Double) -> Animation {
        .linear(duration: seconds).repeatForever(autoreverses: false)
    }
}
