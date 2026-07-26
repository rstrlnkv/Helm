import SwiftUI
import AppKit

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
    /// "Reduce motion" is a medical setting, not a preference: springs that
    /// overshoot and a bezel that spins forever are exactly what it exists to
    /// stop. SwiftUI does not honour it for us. Read fresh each time — AppKit
    /// keeps this current, so a change applies to the next animation without a
    /// relaunch — and collapse to an instant cut rather than removing the state
    /// change itself.
    private static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private static let instant = Animation.linear(duration: 0.01)

    /// Opening and closing measured-height sections. No overshoot by design.
    public static var disclosure: Animation {
        reduced ? instant : .smooth(duration: 0.30)
    }

    /// Small state changes: reordering rows, toggling a filter, moving a
    /// selection. A touch of spring so it doesn't feel mechanical.
    public static var interface: Animation {
        reduced ? instant : .snappy(duration: 0.22)
    }

    /// Large morphs where the shape itself changes — a pill growing into a
    /// card. Bouncy enough to read as fluid.
    public static var emphasis: Animation {
        reduced ? instant : .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// Steady rotation (the About page's bezel while a check runs) — the one
    /// place a linear curve is correct, because the motion has no destination.
    /// Under Reduce Motion it does not turn at all; the progress spinner beside
    /// it already says the same thing.
    public static func steadyRotation(seconds: Double) -> Animation {
        guard !reduced else { return .linear(duration: 0) }
        return .linear(duration: seconds).repeatForever(autoreverses: false)
    }
}
