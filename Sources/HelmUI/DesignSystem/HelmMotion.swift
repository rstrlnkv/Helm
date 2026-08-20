import SwiftUI
import AppKit
import HelmRuntime

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
    /// overshoot and a glyph that turns forever are exactly what it exists to
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

    /// The header strip lighting under the pointer, and going out again.
    ///
    /// **Asymmetric, and measured that way off macOS itself.** System Settings
    /// and Finder were recorded on this Mac at ~32 fps: in over 12 frames
    /// (0,19 s), out over 20 (0,33 s), monotonic in both directions with no
    /// overshoot. Nothing already in this vocabulary says that — `interface`
    /// is a spring with a little bounce, and `disclosure` has the right shape
    /// but would enter 0,11 s slower than the system does.
    ///
    /// One name rather than two tokens, because it is one behaviour with two
    /// halves; `.smooth` is a spring with the bounce set to zero, which is what
    /// "monotonic, no overshoot" means in this vocabulary.
    public static func hover(entering: Bool) -> Animation {
        reduced ? instant : .smooth(duration: entering ? 0.19 : 0.33)
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
        let distance = Double(levels.clamped(to: 1...4))
        return .easeInOut(duration: 0.50 + 0.16 * (distance - 1))
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

    /// Whether one glyph may morph into another.
    ///
    /// The same shape as `spins` and for the same reason: a decision made of
    /// arguments can be asserted, a decision that reads `NSWorkspace` can only
    /// be asserted about the machine it ran on. There is no `requested:` half
    /// — a glyph that changes what it says always wants to be seen changing;
    /// the only question is whether the person has asked for stillness.
    public static func swaps(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

public extension View {
    /// The one way a glyph turns forever — the refresh buttons on the list
    /// screens while their list reloads.
    ///
    /// `.symbolEffect(.rotate, options: .repeating)` on its own does not honour
    /// Reduce Motion; SwiftUI leaves that to us, and these two spun regardless.
    func helmSteadySpin(_ active: Bool) -> some View {
        symbolEffect(.rotate, options: .repeating,
                     isActive: HelmMotion.spins(requested: active,
                                                reduceMotion: HelmMotion.reduceMotion))
    }

    /// The one way a glyph becomes a different glyph.
    ///
    /// `symbol` is the name the `Image` is drawing, and it is an argument
    /// rather than something this modifier could read, because
    /// `.contentTransition` needs a transaction to fire at all: a bare
    /// `.contentTransition` is a decoration that draws one value where the
    /// same view with an `.animation` beside it draws twelve (measured on a
    /// rolling digit, `RuleEditor.swift`). So the modifier carries both halves
    /// and there is no way to take one without the other.
    ///
    /// **Magic Replace, with a fallback that is not optional.** Layers the two
    /// symbols share travel; the rest is replaced. Apple makes `fallback:`
    /// part of the signature because a pair may share nothing — `pencil` and
    /// `checkmark` do — and then the whole glyph slides up and away instead.
    /// One token for both cases: the pair decides which it gets, not the
    /// call site, so nobody has to judge two symbols by eye.
    ///
    /// Reduce Motion cuts twice over. `HelmMotion.interface` collapses to a
    /// 0.01 s cut on its own, and the transition goes to `.identity` as well,
    /// so the glyph changes without the layers being taken apart first.
    func helmSymbolSwap(_ symbol: String) -> some View {
        contentTransition(HelmMotion.swaps(reduceMotion: HelmMotion.reduceMotion)
                          ? .symbolEffect(.replace.magic(fallback: .downUp))
                          : .identity)
            .animation(HelmMotion.interface, value: symbol)
    }
}
