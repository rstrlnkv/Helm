import Foundation

/// The angular transform that turns one wedge into the whole ring.
///
/// Drilling used to be a cross-fade between two scaled rings: the old ring grew
/// and faded, the new one appeared from nothing. Nothing connected the wedge
/// the user clicked to the ring they ended up looking at, so the gesture said
/// "something changed" rather than "you are now inside this".
///
/// Here the clicked wedge widens until it *is* the ring, its own children slide
/// inward to take its place, and everything else spreads out past the edge and
/// goes. Reversed, it is the way back: the ring narrows into the wedge it came
/// from, inside its parent.
public enum RingUnfold {
    /// 12 o'clock, where every layout starts.
    public static let top = -Double.pi / 2
    public static let full = 2 * Double.pi

    /// How much the pivot has to widen to fill the circle.
    ///
    /// A wedge narrower than a whisker would ask for an enormous scale and take
    /// every other angle to infinity with it, so the span is floored — the
    /// animation stays finite even for a sliver.
    public static func scale(span: Double, progress t: Double) -> Double {
        let span = max(abs(span), 1e-4)
        return 1 + t * (full / span - 1)
    }

    /// Where an angle sits partway through the unfold.
    ///
    /// At `t = 0` this is the identity — the ring is exactly as laid out. At
    /// `t = 1` the pivot's start is at 12 o'clock and its end is all the way
    /// round.
    public static func angle(_ angle: Double, pivotStart: Double, span: Double,
                             progress t: Double) -> Double {
        let k = scale(span: span, progress: t)
        return top + (angle - pivotStart) * k + (1 - t) * (pivotStart - top)
    }

    /// Which ring an arc is drawn in partway through: the pivot's descendants
    /// move one ring inward, because that is where they will be once the drill
    /// lands. Everything else stays put.
    public static func ring(_ ring: Int, isDescendant: Bool, progress t: Double) -> Double {
        isDescendant ? Double(ring) - t : Double(ring)
    }

    /// The pivot itself is on its way to becoming the middle, and everything
    /// outside its subtree is on its way out; both fade. Its descendants stay
    /// solid — they are what the user is about to be looking at.
    ///
    /// `isSpare` is the level that is not drawn until the unfold needs it. The
    /// ring shows three levels; the drill promotes each one inward, so the
    /// level that becomes the new outermost was never on screen and had nowhere
    /// to slide in from — it simply appeared, whole, the instant the tree
    /// swapped. Now it is laid out one level deeper than is drawn and enters
    /// the way everything else does: sliding inward, and fading up with the
    /// same progress, which is 0 exactly where it is invisible anyway.
    public static func opacity(isPivot: Bool, isDescendant: Bool, isSpare: Bool = false,
                               progress t: Double) -> Double {
        if isSpare { return isDescendant ? max(0, min(1, t)) : 0 }
        if isDescendant { return 1 }
        return max(0, 1 - t)
    }

    /// True while an arc is still inside the visible circle. Past the unfold
    /// the other branches have been pushed beyond a full turn, and drawing them
    /// would wrap them back over the ring they were making way for.
    public static func isVisible(start: Double, end: Double) -> Bool {
        end > top && start < top + full
    }
}
