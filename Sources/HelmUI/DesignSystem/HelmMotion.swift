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

    /// How long `disclosure` takes, as a number.
    ///
    /// AppKit needs the figure and not the `Animation`: a table animating its
    /// own row heights takes an `NSAnimationContext` duration, and the rows and
    /// the block around them have to move on one clock. It was written twice —
    /// which is the arrangement where one of them gets changed.
    public static let disclosureSeconds: Double = 0.30

    /// Opening and closing measured-height sections. No overshoot by design.
    public static var disclosure: Animation {
        reduced ? instant : .smooth(duration: disclosureSeconds)
    }

    /// Small state changes: reordering rows, toggling a filter, moving a
    /// selection. A touch of spring so it doesn't feel mechanical.
    public static var interface: Animation {
        reduced ? instant : .snappy(duration: 0.22)
    }

    /// A panel arriving on screen from the menu bar.
    ///
    /// Short and eased-out, and **nothing but opacity**. macOS menus and
    /// menu-bar extras do not grow, scale or slide: they are simply there, over
    /// a fade fast enough that the fade is not what you notice. A scale from
    /// the top edge was tried and reads as a web popover — the motion is not
    /// wrong in itself, it is just not something this operating system does.
    ///
    /// 0.12 s: long enough that the card does not appear to blink into
    /// existence, short enough that a panel opened to read one number is not
    /// something you wait for.
    public static var panelEntrance: Animation {
        reduced ? instant : .easeOut(duration: 0.12)
    }

    /// A tile moving out of the way of one being dragged over it.
    ///
    /// A spring, and the one place in this app where the overshoot is the
    /// point: a card that slides aside and settles reads as a physical thing
    /// being pushed, which is exactly the claim a drag makes. Small enough not
    /// to wobble — 0.28 with a high damping is one soft landing, not a bounce
    /// anybody has to wait out.
    public static var reorder: Animation {
        reduced ? instant : .spring(response: 0.28, dampingFraction: 0.72)
    }

    /// The two fades a carried tile leaves behind it, both deliberately slower
    /// than the hand.
    ///
    /// They were inline `.easeOut` curves, which is the one thing a curve in
    /// this app may not be: an inline animation cannot be found by anyone
    /// looking for the app's vocabulary, and — the part that matters — it does
    /// not collapse under Reduce Motion, so the one gesture in Helm that fades
    /// two surfaces was also the one that kept fading with the setting on.
    /// The numbers are unchanged, and the reason for each is on it.
    ///
    /// `slotFade`: the tile's own content stepping aside as it is picked up.
    /// The overlay sits exactly on top of the slot from the first frame, so
    /// whatever happens in the first 150 ms is invisible; at 0.3 s the fade was
    /// over before a quick drag cleared the slot, and what the eye met was a
    /// dark hole that had arrived instantly. Half a second means the slot is
    /// still dimming as it comes out from under the hand.
    public static var slotFade: Animation {
        reduced ? instant : .easeOut(duration: 0.5)
    }

    /// `wellFade`: the grey well marking where the carried tile came from. It
    /// outlives the drag — the handover swaps the tile inside a transaction
    /// with animations off, and the well has to go on fading through it — so it
    /// is a shade quicker than the slot it sits in.
    public static var wellFade: Animation {
        reduced ? instant : .easeOut(duration: 0.4)
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
    /// rather than as life.
    /// Not a spring. A spring starts at its highest velocity and decays, which
    /// is what "alive" means for a control that pops — and what "abrupt" means
    /// for a shape that travels across the screen. Measured off a screen
    /// recording of the ring, frame to frame: the first frame of the move
    /// already held the largest change of the whole animation (193k of a 194k
    /// peak), then decayed for half a second. It read as a snap with a long
    /// tail, which is exactly what it was.
    ///
    /// An eased curve starts still, and that is the half a spring cannot do.
    ///
    /// `levels` is how far the ring is travelling. Crossing two levels at once
    /// (a breadcrumb jump) covers more ground than a single drill and needs the
    /// time to show it; at the same duration it read as a cut with a blur.
    public static func ringMorph(levels: Int = 1) -> Animation {
        guard !reduced else { return instant }
        let distance = Double(max(1, min(levels, 4)))
        return .easeInOut(duration: 0.50 + 0.16 * (distance - 1))
    }

    /// Steady rotation (the About page's bezel while a check runs) — the one
    /// place a linear curve is correct, because the motion has no destination.
    /// Under Reduce Motion it does not turn at all; the progress spinner beside
    /// it already says the same thing.
    public static func steadyRotation(seconds: Double) -> Animation {
        guard !reduced else { return .linear(duration: 0) }
        return .linear(duration: seconds).repeatForever(autoreverses: false)
    }

    /// How a wheel that was turning comes to rest: a short coast forward, never
    /// a rewind.
    ///
    /// The About bezel used to stop with `withAnimation(interface) { angle = 0 }`
    /// — a retarget from wherever the dial had got to back to zero, so the wheel
    /// visibly *un*-spun, with a snappy spring's overshoot at the end. A thing
    /// with momentum does not do that. Two dozen degrees is enough to read as
    /// deceleration and short enough that the check still feels finished.
    public static var spinDown: Animation {
        reduced ? instant : .easeOut(duration: 0.55)
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
