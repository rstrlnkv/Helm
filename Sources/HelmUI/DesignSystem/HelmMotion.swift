import SwiftUI
import AppKit
import QuartzCore
import HelmRuntime

/// One vocabulary of motion for the whole app (Architecture/DesignSystem.md § Motion).
///
/// Springs, not ease curves: an eased move reads as "smoothed", a spring as
/// physical. Anything whose height is measured and clipped uses `disclosure`,
/// a spring with zero bounce, because an overshooting height clips its own
/// content for a frame.
public enum HelmMotion {
    /// Reduce Motion is a medical setting, not a preference, and SwiftUI does
    /// not honour it for us. Read fresh through `HelmAccessibility.system` on
    /// each access, so a change applies to the next animation without a
    /// relaunch; a token collapses to an instant cut rather than dropping the
    /// state change. Every `Animation` token reads it here, not from
    /// `\.helmTraits`, as do AppKit code and pages not on `\.helmTraits`.
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

    /// `interface`'s duration alone, for a caller that animates through AppKit:
    /// `NSAnimationContext` takes a number, and a literal of its own would be a
    /// duplicate constant nothing goes red on. The length is shared, not the
    /// curve. A caller using this is responsible for its own `reduceMotion`
    /// branch, because a bare number cannot collapse the way a token does.
    public static var interfaceDuration: TimeInterval { 0.22 }

    /// `interface` for a `CALayer`: Core Animation takes a timing function, not
    /// a spring, so this is the nearest curve without overshoot, leaving fast and
    /// settling slowly. Run for `interfaceDuration`, or for `sidebarFoldDuration`
    /// by the sidebar's fold beside its SwiftUI half, `sidebarFold`. A caller
    /// using it owns its `reduceMotion` branch; one that drives a value by its
    /// own clock reads the curve through `interfaceProgress(at:)`.
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

    /// The curve of the Display Corners mask's morph: ease in and out (0.42, 0,
    /// 0.58, 1), the standalone app's own curve, kept by the owner's choice over
    /// `interfaceCurve`. Nothing else takes it. A caller using it owns its
    /// `reduceMotion` branch.
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
    /// Asymmetric, as in System Settings and Finder: in over 0.19 s, out over
    /// 0.33 s, with no overshoot. `.smooth` is a spring with zero bounce, which
    /// is what "no overshoot" means here; `interface` bounces, and `disclosure`
    /// enters slower than the system does.
    static func hover(entering: Bool) -> Animation {
        reduceMotion ? instant : .smooth(duration: entering ? 0.19 : 0.33)
    }

    /// A panel arriving on screen from the menu bar.
    ///
    /// Opacity only, short and eased out: macOS menus and menu-bar extras do
    /// not grow, scale or slide, and a scale from the top edge reads as a web
    /// popover. 0.12 s keeps the card from blinking into existence without
    /// making a glance at one number something to wait for. Eased, because a
    /// spring that short is a spring nobody can see.
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

    /// A tile moving out of the way of one being dragged over it: the one place
    /// where the overshoot is the point, since a card pushed aside that settles
    /// reads as a physical thing. High damping makes it one soft landing, not a
    /// bounce to wait out.
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

    /// The two fades a carried tile leaves behind it, both slower than the hand.
    ///
    /// `slotFade`: the tile's own content stepping aside as it is picked up. The
    /// overlay covers the slot from the first frame, so a shorter fade ends
    /// before a quick drag clears the slot and the eye meets a hole that arrived
    /// at once. Half a second keeps the slot dimming as it comes out from under
    /// the hand.
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
    /// Eased, not a spring: a spring starts at its highest velocity, which for a
    /// shape travelling across the screen reads as a snap with a long tail, and
    /// `emphasis`'s overshoot at the end of a long arc reads as a snap too. An
    /// eased curve starts still.
    ///
    /// `levels` is how far the ring travels: a breadcrumb jump across several
    /// levels covers more ground and needs the time to show it.
    public static func ringMorph(levels: Int = 1) -> Animation {
        guard !reduceMotion else { return instant }
        let distance = Double(levels.clamped(to: 1...4))
        return .easeInOut(duration: 0.50 + 0.16 * (distance - 1))
    }

    /// How a wheel that was turning comes to rest: a short coast forward, never
    /// a rewind. Retargeting the angle back to zero would visibly un-spin the
    /// wheel; a thing with momentum decelerates.
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

    /// Whether a decision that is only a matter of motion may move at all; an
    /// argument for the reason `spins` takes one. There is no `requested:` half:
    /// the only question is whether the person has asked for stillness.
    /// `command grep -rn 'HelmMotion.moves' Sources` lists the callers. Under
    /// Reduce Motion a caller cuts only the travel: the screenshot palette's
    /// picked object is still raised, since that is how it shows the choice,
    /// and the overlay's flash is not drawn at all.
    public static func moves(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

extension View {
    /// The one way a glyph turns forever: the refresh buttons while their list
    /// reloads. `.symbolEffect(.rotate, options: .repeating)` on its own does
    /// not honour Reduce Motion.
    public func helmSteadySpin(_ active: Bool) -> some View {
        modifier(SteadySpin(active: active))
    }

    /// The one way a glyph becomes a different glyph.
    ///
    /// `symbol` is an argument because `.contentTransition` needs a transaction
    /// to fire at all, so the modifier carries the transition and the animation
    /// together and neither can be taken alone.
    ///
    /// Magic Replace: layers the two symbols share travel, the rest is replaced.
    /// A pair that shares nothing (`pencil`, `checkmark`) takes the fallback and
    /// slides up and away, so the pair decides, not the call site. Under Reduce
    /// Motion the transition is `.identity` as well as the curve being cut.
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
