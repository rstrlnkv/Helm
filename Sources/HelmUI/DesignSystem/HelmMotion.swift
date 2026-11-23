import SwiftUI
import AppKit
import QuartzCore
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
/// Architecture/DesignSystem.md § Motion, which warns about. Those use `disclosure`, which is a spring with
/// the bounce set to zero: physical timing, no overshoot.
public enum HelmMotion {
    /// "Reduce motion" is a medical setting, not a preference: springs that
    /// overshoot and a glyph that turns forever are exactly what it exists to
    /// stop. SwiftUI does not honour it for us. Read fresh each time — AppKit
    /// keeps this current, so a change applies to the next animation without a
    /// relaunch — and collapse to an instant cut rather than removing the state
    /// change itself.
    ///
    /// The system setting, read fresh through `HelmAccessibility.system`: for AppKit code, for pages
    /// that are not yet on `\.helmTraits`, and for every `Animation` token below, which read it here: a view
    /// that animates by a token (`HelmButtonStyle` and `HelmPageHeader` by `hover(entering:)`) takes Reduce
    /// Motion from here and not from `\.helmTraits`.
    public static var reduceMotion: Bool {
        HelmAccessibility.system.reducedMotion
    }
    private static let instant = Animation.linear(duration: 0.01)

    /// Opening and closing measured-height sections. No overshoot by design.
    public static var disclosure: Animation {
        reduceMotion ? instant : .smooth(duration: 0.30)
    }

    /// Small state changes: reordering rows, toggling a filter, moving a
    /// selection, switching a tab. A touch of spring so it doesn't feel mechanical.
    public static var interface: Animation {
        reduceMotion ? instant : .snappy(duration: interfaceDuration)
    }

    /// `interface`'s duration alone, in seconds, for a caller that animates
    /// through AppKit — `NSAnimationContext` takes a number and has nowhere to
    /// put an `Animation`, so such a caller would
    /// otherwise carry the number as a literal of its own, which is the
    /// duplicate-constant shape nothing goes red on.
    ///
    /// **Not the same curve.** `interface` is a spring and an AppKit caller
    /// runs a timing function; what is shared here is the length, so
    /// the two move for the same time and not along the same path. A caller
    /// using this is responsible for its own `reduceMotion` branch, because a
    /// bare number cannot collapse the way a token does.
    public static var interfaceDuration: TimeInterval { 0.22 }

    /// `interface` for a `CALayer`: Core Animation takes a timing function and has nowhere to put a
    /// spring, so the curve is the nearest one without an overshoot — it leaves fast and settles slowly,
    /// as a snappy spring does. Its length is `interfaceDuration` where the caller runs for that long;
    /// the sidebar's fold runs this curve for `sidebarFoldDuration`, as its SwiftUI half, `sidebarFold`,
    /// is a snappy spring given the same duration. A caller using this is responsible for its own
    /// `reduceMotion` branch, as with the duration. A caller that drives a value by its own clock
    /// reads the curve at a fraction through `interfaceProgress(at:)`.
    public static var interfaceCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    }

    /// How far `interfaceCurve` has come at `fraction` of its length, 0 to 1: the curve's y where its x is
    /// `fraction`. The control points are read back from `interfaceCurve` itself, so there is no second copy
    /// of them; the parameter is found by bisection. A `fraction` below 0 reads 0 and one above 1 reads 1, as
    /// do the infinities; not-a-number reads 1, so a travel that does not know where it is ends at its target.
    /// Whether a caller may travel at all is `moves(reduceMotion:)`, which this does not ask.
    public static func interfaceProgress(at fraction: Double) -> Double {
        guard !fraction.isNaN else { return 1 }
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return 1 }
        let c = interfaceControlPoints
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low = 0.0
        var high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, c.x1, c.x2) < fraction { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, c.y1, c.y2)
    }

    /// `interfaceCurve`'s two inner control points, read once through `getControlPoint(at:values:)`.
    private static let interfaceControlPoints: (x1: Double, y1: Double, x2: Double, y2: Double) = {
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        interfaceCurve.getControlPoint(at: 1, values: &first)
        interfaceCurve.getControlPoint(at: 2, values: &second)
        return (Double(first[0]), Double(first[1]), Double(second[0]), Double(second[1]))
    }()

    /// The curve of the Display Corners mask's morph: ease in and out, the control points of `.easeInEaseOut`
    /// (0.42, 0, 0.58, 1). The standalone app's own curve, kept by the owner's decision of 2026-11-18 ("as in the
    /// original tweak") over `interfaceCurve`; it is not the app's interface curve and nothing else takes it. A
    /// caller using this is responsible for its own `reduceMotion` branch.
    public static var cornerMorphCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
    }

    /// How long a Display Corners mask takes to grow or shrink by `travel`, the distance its scale has to cover
    /// (0 to 1): 0.26 s per square root of the travel when rounding, 0.19 s when unrounding, never under 0.08 s.
    /// The lengths are the standalone app's, as is its curve, `cornerMorphCurve`. A
    /// travel that is not finite reads as 1 and one outside 0...1 is held to it. It does not ask `reduceMotion`: the caller, a layer animation, has
    /// its own branch, as with `interfaceDuration`.
    public static func cornerMorphDuration(rounding: Bool, travel: Double) -> TimeInterval {
        let travel = travel.isFinite ? min(max(travel, 0), 1) : 1
        return max(0.08, (rounding ? 0.26 : 0.19) * travel.squareRoot())
    }

    /// The sidebar folding to the rail and unfolding again: the rows' half of the move, written inside
    /// `withAnimation` where the fold flag lands. The width itself is driven by the shell's own clock
    /// along `interfaceCurve` for `sidebarFoldDuration`; the shell asks for this token only when it starts
    /// that, which is only when `moves` allows it, so both are asked for in the same turn and given the same duration.
    public static var sidebarFold: Animation {
        reduceMotion ? instant : .snappy(duration: sidebarFoldDuration)
    }

    /// `sidebarFold`'s duration alone, in seconds, for the width the shell drives. A caller using
    /// this is responsible for its own `reduceMotion` branch, as with `interfaceDuration`.
    public static var sidebarFoldDuration: TimeInterval { 0.26 }

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
    static func hover(entering: Bool) -> Animation {
        reduceMotion ? instant : .smooth(duration: entering ? 0.19 : 0.33)
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
    /// something you wait for. Eased rather than sprung because a spring that
    /// short is a spring nobody can see.
    public static var panelEntrance: Animation {
        reduceMotion ? instant : .easeOut(duration: 0.12)
    }

    /// How long a full-screen surface takes to come in, in seconds: its content settling from a little larger to its size as
    /// the window is revealed. The window runs its own clock and reads `interfaceProgress(at:)`, so there is no animation
    /// to hand over. A caller using this is responsible for its own `reduceMotion` branch, as with `interfaceDuration`.
    public static var windowZoomDuration: TimeInterval { 0.32 }

    /// A page that was dragged by the fingers coming to rest: a spring with no bounce that takes up the speed the fingers
    /// let go at, so a flick carries on and a slow let-go eases in. `velocity` is points a second along the move (negative
    /// is against it), `distance` the points still to travel; the speed is passed to the spring as distances a second
    /// (`pageSettleSpeed`), held to 0 to 8 so a hand-shake of a release cannot fling the page.
    public static func pageSettle(velocity: CGFloat, distance: CGFloat) -> Animation {
        guard !reduceMotion else { return instant }
        return .interpolatingSpring(duration: pageSettleDuration, bounce: 0, initialVelocity: Double(pageSettleSpeed(velocity: velocity, distance: distance)))
    }

    /// `pageSettle`'s initial speed, in distances a second: `velocity` over `distance`, 0 for a speed that is against the move,
    /// not a number, infinite, or over no distance, and never over 8.
    public static func pageSettleSpeed(velocity: CGFloat, distance: CGFloat) -> CGFloat {
        distance > 1 && velocity.isFinite ? (velocity / distance).clamped(to: 0...8) : 0
    }

    /// `pageSettle`'s duration alone, in seconds, for a caller that must know how long a settle lasts (the swipe ignores a new
    /// touch until it is over). A caller using this is responsible for its own `reduceMotion` branch.
    public static var pageSettleDuration: TimeInterval { 0.36 }

    /// A tile moving out of the way of one being dragged over it.
    ///
    /// A spring, and the one place in this app where the overshoot is the
    /// point: a card that slides aside and settles reads as a physical thing
    /// being pushed, which is exactly the claim a drag makes. Small enough not
    /// to wobble — 0.28 with a high damping is one soft landing, not a bounce
    /// anybody has to wait out.
    public static var reorder: Animation {
        reduceMotion ? instant : .spring(response: 0.28, dampingFraction: 0.72)
    }

    /// A cut name scrolling to its end under the pointer: steady, at a reading pace (40 pt a second, never under 0.3 s), no spring. Instant under Reduce Motion.
    public static func marquee(distance: CGFloat) -> Animation {
        reduceMotion ? instant : .linear(duration: marqueeDuration(distance: distance))
    }

    /// `marquee`'s length in seconds, for the caller that waits it out.
    public static func marqueeDuration(distance: CGFloat) -> TimeInterval { max(0.3, Double(distance) / 40) }

    /// The wobble of a tile in Launchpad's edit mode: a short ease back and forth, forever, started a little later for some seeds (eight phases over the whole 0.24 s cycle, by `seed`) so the tiles
    /// are not in step. **nil under Reduce Motion**: the tile then does not move at all (the badges say it is editing), never a still tilt.
    public static func wiggle(seed: Int) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.12).delay(Double(abs(seed % 8)) * 0.03).repeatForever(autoreverses: true)
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
        reduceMotion ? instant : .easeOut(duration: 0.5)
    }

    /// `wellFade`: the grey well marking where the carried tile came from. It
    /// outlives the drag — the handover swaps the tile inside a transaction
    /// with animations off, and the well has to go on fading through it — so it
    /// is a shade quicker than the slot it sits in.
    public static var wellFade: Animation {
        reduceMotion ? instant : .easeOut(duration: 0.4)
    }

    /// Large morphs where the shape itself changes — a pill growing into a
    /// card. Bouncy enough to read as fluid.
    public static var emphasis: Animation {
        reduceMotion ? instant : .spring(response: 0.42, dampingFraction: 0.78)
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
        guard !reduceMotion else { return instant }
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
    static var spinDown: Animation {
        reduceMotion ? instant : .easeOut(duration: 0.55)
    }

    /// Whether an indefinite symbol spin may run.
    ///
    /// Both facts are arguments rather than one being read from the system, so
    /// the rule can be tested at all: a check that consults `NSWorkspace` only
    /// proves the machine it ran on was set the way the test assumed.
    static func spins(requested: Bool, reduceMotion: Bool) -> Bool {
        requested && !reduceMotion
    }

    /// Whether a decision that is only a matter of motion may move at all: the
    /// same shape as `spins` and for the same reason, a decision made of an
    /// argument can be asserted, one that reads `NSWorkspace` can only be
    /// asserted about the machine it ran on. There is no `requested:` half; the
    /// only question is whether the person has asked for stillness. Its callers:
    /// the header row's tabs slide their pick to a pressed tab (`HelmHeaderTabs`),
    /// the screenshot editor's palette lifts the picked pen, marker, pencil,
    /// eraser or ruler by `PaletteObject.lift`, the settings window's sidebar
    /// travels to the rail or back (`ShellContentView.fold(to:animated:)`), the
    /// window buttons' plate morphs between its closed shape and its open one
    /// (`ShellWindowButtons.show(animated:)`), one glyph morphs into another
    /// (`helmSymbolSwap`), and the screenshot overlay flashes the shot it has taken.
    /// Under Reduce Motion the palette object is still raised — that is how it
    /// shows the choice — and only the travel is cut; there is no flash at all
    /// and the overlay closes at once.
    public static func moves(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

extension View {
    /// The one way a glyph turns forever — the refresh buttons on the list
    /// screens while their list reloads.
    ///
    /// `.symbolEffect(.rotate, options: .repeating)` on its own does not honour
    /// Reduce Motion; SwiftUI leaves that to us, and these two spun regardless.
    public func helmSteadySpin(_ active: Bool) -> some View {
        modifier(SteadySpin(active: active))
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
    public func helmSymbolSwap(_ symbol: String) -> some View {
        modifier(SymbolSwap(symbol: symbol))
    }
}

private struct SteadySpin: ViewModifier {
    let active: Bool
    @Environment(\.helmTraits) private var traits

    func body(content: Content) -> some View {
        content.symbolEffect(.rotate, options: .repeating,
                             isActive: HelmMotion.spins(requested: active,
                                                        reduceMotion: traits.reducedMotion))
    }
}

private struct SymbolSwap: ViewModifier {
    let symbol: String
    @Environment(\.helmTraits) private var traits

    func body(content: Content) -> some View {
        content
            .contentTransition(HelmMotion.moves(reduceMotion: traits.reducedMotion)
                               ? .symbolEffect(.replace.magic(fallback: .downUp))
                               : .identity)
            .animation(HelmMotion.interface, value: symbol)
    }
}
