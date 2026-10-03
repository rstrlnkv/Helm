import CoreGraphics
import HelmRuntime

/// Where the shots of the after-shot window stand when there is more than one: folded into a pile in the corner, or
/// unfolded into a row that reaches leftward from it. Numbers and bookkeeping only, so the window's view, its clock
/// and a test ask the same functions; nothing here knows a view.
///
/// **An age, not an index.** A shot is named by how many shots are newer than it: 0 is the newest, which stands in
/// the corner in both shapes. The list itself is kept oldest first (`add`), so the shot at index `i` of `count` has
/// the age `count - 1 - i`.
public enum ShotShelf {
    /// The most shots the window holds. The one after that pushes the oldest out; it is never refused.
    public static let limit = 20
    /// How many sheets of the pile are drawn, and how many shots of the row are seen at once.
    public static let visible = 3

    /// The pile: each older sheet stands this far up and left of the one over it, smaller and fainter by these.
    public static let step: CGFloat = 7
    public static let shrink: CGFloat = 0.05
    public static let fade: CGFloat = 0.22

    /// The row: a slot is as wide as the largest picture (`ShotThumbnail.maxWidth`), with this between two slots.
    public static let gap: CGFloat = 16
    public static var pitch: CGFloat { ShotThumbnail.maxWidth + gap }
    /// How wide the cut edge of a row that is between two rests fades to nothing.
    public static let edgeFade: CGFloat = 28

    /// Seconds the pointer is away from the row before it folds back.
    public static let foldDelay: Double = 1
    /// Seconds without a scroll before the row comes to rest on a whole slot, and before its bar goes.
    public static let snapDelay: Double = 0.2
    public static let barLinger: Double = 1

    /// A clock that adds up tenths of a second does not reach a whole one: ten of 0.1 are 0.9999999999999999, and
    /// 5 less fifty of them is not 0. What is left of a delay is over when it is within this of nothing, so every
    /// delay of the window is judged by the one question, `isOver(left:)`.
    public static let clockTolerance: Double = 1e-9
    public static func isOver(left: Double) -> Bool { left <= clockTolerance }

    // MARK: - The list

    /// Puts `shot` on the list as its newest and returns what that pushed out, oldest first: nothing while the list
    /// is within `limit`.
    public static func add<Shot>(_ shot: Shot, to shots: inout [Shot]) -> [Shot] {
        shots.append(shot)
        let excess = max(0, shots.count - limit)
        let out = Array(shots.prefix(excess))
        shots.removeFirst(excess)
        return out
    }

    private static func bounded(_ count: Int) -> Int { min(max(count, 0), limit) }

    // MARK: - The pile

    /// How one sheet of the pile is drawn.
    public struct Sheet: Equatable, Sendable {
        /// From the newest sheet's place, in points; up and left are negative.
        public let offset: CGSize
        /// About the sheet's top left corner.
        public let scale: CGFloat
        public let opacity: CGFloat
    }

    /// The sheet of the shot of this age. Past the `visible` newest a sheet lies under the last drawn one and is not
    /// seen. An age below zero is the newest's.
    public static func sheet(age: Int) -> Sheet {
        let depth = CGFloat(min(max(age, 0), visible - 1))
        return Sheet(offset: CGSize(width: -step * depth, height: -step * depth), scale: 1 - shrink * depth,
                     opacity: age < visible ? 1 - fade * depth : 0)
    }

    // MARK: - The row

    /// The row's width: as many slots as are seen at once.
    public static func width(count: Int) -> CGFloat {
        let slots = CGFloat(min(bounded(count), visible))
        return slots > 0 ? slots * ShotThumbnail.maxWidth + (slots - 1) * gap : 0
    }

    /// How far the row can be scrolled toward its oldest shot: nothing until there are more shots than are seen.
    public static func farthest(count: Int) -> CGFloat {
        CGFloat(max(0, bounded(count) - visible)) * pitch
    }

    /// An offset inside what the row can be scrolled by. One that is not a number is the rest by the newest.
    public static func clamped(_ offset: CGFloat, count: Int) -> CGFloat {
        offset.clamped(to: 0...farthest(count: count), whenNotANumber: 0)
    }

    /// The offset after a scroll of `delta` points toward the oldest (negative toward the newest). A wheel that
    /// reports lines and not points (`precise` false) moves one slot a notch, whatever the number: a few points
    /// would be taken back by the rest that follows. A delta that is not a number moves nothing.
    public static func scrolled(_ offset: CGFloat, by delta: CGFloat, precise: Bool = true, count: Int) -> CGFloat {
        let far = farthest(count: count)
        let move = delta.clamped(to: -far...far, whenNotANumber: 0)
        let step = precise || move == 0 ? move : (move > 0 ? pitch : -pitch)
        return clamped(clamped(offset, count: count) + step, count: count)
    }

    /// The nearest rest: a whole number of slots.
    public static func snapped(_ offset: CGFloat, count: Int) -> CGFloat {
        clamped((clamped(offset, count: count) / pitch).rounded() * pitch, count: count)
    }

    /// Where the slot of the shot of this age begins, from the row's leading edge, at this offset.
    public static func leading(age: Int, offset: CGFloat, count: Int) -> CGFloat {
        width(count: count) - ShotThumbnail.maxWidth - CGFloat(max(age, 0)) * pitch + clamped(offset, count: count)
    }

    /// How far the slot of the shot of this age stands from the corner, where the newest's is at rest: negative is
    /// toward the row's leading edge.
    public static func shift(age: Int, offset: CGFloat, count: Int) -> CGFloat {
        leading(age: age, offset: offset, count: count) + ShotThumbnail.maxWidth - width(count: count)
    }

    /// The «N more» label: which shot carries it and what it counts.
    public struct More: Equatable, Sendable {
        /// The age of the farthest shot that is seen whole.
        public let on: Int
        /// How many shots past it are not seen at all; one that is cut by the edge is seen, and is not counted.
        public let count: Int
    }

    /// Nil when every shot is seen at least in part, or none is seen whole.
    public static func more(count: Int, offset: CGFloat) -> More? {
        let count = bounded(count), row = width(count: count)
        // Half a point of slack: an offset that came out of a scroll is not exactly a whole slot.
        let slack: CGFloat = 0.5
        var farWhole: Int?, unseen = 0
        for age in 0..<count {
            let start = leading(age: age, offset: offset, count: count)
            if start >= -slack, start + ShotThumbnail.maxWidth <= row + slack { farWhole = age }
            if start + ShotThumbnail.maxWidth <= slack { unseen += 1 }
        }
        guard let farWhole, unseen > 0 else { return nil }
        return More(on: farWhole, count: unseen)
    }
}
