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
    private static var reduced: Bool { reduceMotion }

    /// The system setting, read fresh. Public only so the view modifier below
    /// can hand it to `spins` as a value.
    public static var reduceMotion: Bool {
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

    /// The disk ring opening or closing a level.
    ///
    /// `emphasis` is a spring with a little overshoot, which is right for a pill
    /// growing into a card and wrong here: the ring's arcs travel a long way
    /// round the circle, and an overshoot at the end of that reads as a snap
    /// rather than as life. This is a spring with no bounce at all, and it is
    /// slower — a morph of the whole screen is not a toggle.
    ///
    /// `levels` is how far the ring is travelling. Crossing two levels at once
    /// (a breadcrumb jump) covers more ground than a single drill and needs the
    /// time to show it; at the same duration it read as a cut with a blur.
    public static func ringMorph(levels: Int = 1) -> Animation {
        guard !reduced else { return instant }
        let distance = Double(max(1, min(levels, 4)))
        return .smooth(duration: 0.46 + 0.14 * (distance - 1))
    }

    /// Steady rotation (the About page's bezel while a check runs) — the one
    /// place a linear curve is correct, because the motion has no destination.
    /// Under Reduce Motion it does not turn at all; the progress spinner beside
    /// it already says the same thing.
    public static func steadyRotation(seconds: Double) -> Animation {
        guard !reduced else { return .linear(duration: 0) }
        return .linear(duration: seconds).repeatForever(autoreverses: false)
    }

    /// Whether an indefinite symbol spin may run.
    ///
    /// Both facts are arguments rather than one being read from the system, so
    /// the rule can be tested at all: a check that consults `NSWorkspace` only
    /// proves the machine it ran on was set the way the test assumed.
    public static func spins(requested: Bool, reduceMotion: Bool) -> Bool {
        requested && !reduceMotion
    }
}

public extension View {
    /// The one way a glyph turns forever — the refresh buttons on the list
    /// screens while their list reloads.
    ///
    /// `.symbolEffect(.rotate, options: .repeating)` on its own does not honour
    /// Reduce Motion; SwiftUI leaves that to us, and `HelmMotion.steadyRotation`
    /// has always done it for the About bezel. These two spun regardless.
    func helmSteadySpin(_ active: Bool) -> some View {
        symbolEffect(.rotate, options: .repeating,
                     isActive: HelmMotion.spins(requested: active,
                                                reduceMotion: HelmMotion.reduceMotion))
    }
}
