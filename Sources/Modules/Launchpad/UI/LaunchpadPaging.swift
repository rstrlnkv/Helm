import AppKit
import HelmUI

/// Pages, as arithmetic over a flat list: the window holds no list of pages' views, only which numbers are live.
enum LaunchpadPaging {
    /// At least one: an empty list is one empty page.
    static func pageCount(items: Int, capacity: Int) -> Int {
        guard capacity > 0 else { return 1 }
        return max(1, (items + capacity - 1) / capacity)
    }

    static func slice<T>(_ items: [T], page: Int, capacity: Int) -> [T] {
        guard capacity > 0, page >= 0 else { return [] }
        let from = page * capacity
        guard from < items.count else { return [] }
        return Array(items[from..<min(items.count, from + capacity)])
    }

    /// The pages of segments (the list cut at each page break), each cut again by what a page holds; never an empty page, and
    /// at least one.
    static func pages<T>(_ segments: [[T]], capacity: Int) -> [[T]] {
        let chunks = segments.flatMap { segment in
            (0..<pageCount(items: segment.count, capacity: capacity)).map { slice(segment, page: $0, capacity: capacity) }
        }.filter { !$0.isEmpty }
        return chunks.isEmpty ? [[]] : chunks
    }

    /// The page that holds the tile at `index` of the whole list, given the index each page starts at (a page break makes a
    /// page start before the capacity is reached, so the arithmetic is not `index / capacity`).
    static func page(of index: Int, starts: [Int]) -> Int {
        starts.lastIndex { $0 <= index } ?? 0
    }

    /// Where an arrow key takes the selection. The first press selects the first tile; a step past either end stays;
    /// down from a row above a short last row lands on its last tile.
    static func moved(_ selection: Int?, dx: Int, dy: Int, columns: Int, count: Int) -> Int? {
        guard count > 0, columns > 0 else { return nil }
        guard let from = selection, from >= 0, from < count else { return 0 }
        let to = from + dx + dy * columns
        if to >= 0, to < count { return to }
        if dy > 0, from / columns < (count - 1) / columns { return count - 1 }
        return from
    }

    /// A page number held inside the pages there are.
    static func clamped(_ page: Int, count: Int) -> Int { max(0, min(page, count - 1)) }
}

/// What a scroll wheel or a device with no phases says, as at most one page turn. Pure: no timer, time comes in with the event.
///
/// A trackpad's tracked swipe is `LaunchpadSwipe`'s; this takes what that does not: a device that sends deltas with no phases
/// at all is a swipe that sums 40 pt, turns once, and ends when its events stop for 250 ms. A wheel's notches turn once and
/// then wait 250 ms by the events' own timestamps.
struct LaunchpadScrollPager {
    static let swipeDistance: CGFloat = 40
    static let wheelPause: TimeInterval = 0.25

    private var travelled: CGFloat = 0
    private var turned = false
    private var lastWheelTurn = -TimeInterval.infinity
    private var lastPhaseless = -TimeInterval.infinity

    /// -1 previous page, +1 next, nil nothing. The horizontal delta when there is one, else the vertical; a negative delta
    /// (content dragged left, a wheel rolled down) goes forward. The panel hands a precise delta with a phase to `LaunchpadSwipe`, never here.
    mutating func feed(dx: CGFloat, dy: CGFloat, precise: Bool, time: TimeInterval) -> Int? {
        let delta = dx != 0 ? dx : dy
        guard delta.isFinite else { return nil }
        guard precise else { return wheel(delta, time) }
        if time - lastPhaseless >= Self.wheelPause { travelled = 0; turned = false }
        lastPhaseless = time
        guard !turned else { return nil }
        travelled += delta
        guard abs(travelled) >= Self.swipeDistance else { return nil }
        turned = true
        return travelled < 0 ? 1 : -1
    }

    private mutating func wheel(_ delta: CGFloat, _ time: TimeInterval) -> Int? {
        guard delta != 0, time - lastWheelTurn >= Self.wheelPause else { return nil }
        lastWheelTurn = time
        return delta < 0 ? 1 : -1
    }
}

/// A trackpad swipe with fingers on it, as what the page does: follows them, and on lift settles on the nearest page.
/// Pure: no timer, time comes in with the event.
///
/// Each event's delta adds to what the gesture has travelled; `.drag` says where the fingers have taken the page, `.release`
/// how many pages to turn and how fast the fingers left. Momentum after the lift is ignored: it never turns. A touch that
/// begins while the last release is still settling (`HelmMotion.pageSettleDuration`, none under Reduce Motion) is ignored until it ends.
struct LaunchpadSwipe {
    enum Output: Equatable { case none, drag(raw: CGFloat), release(step: Int, velocity: CGFloat) }

    /// The page's width: the distance that is half a turn. Set by the caller before a gesture.
    var width: CGFloat = 1000
    /// Reduce Motion, read by the caller before a gesture: a release then settles at once, so it locks nothing.
    var reduceMotion = false
    /// A flick at least this fast (pt/s), in the direction of the travel, turns the page from 40 pt.
    static let flickSpeed: CGFloat = 300
    /// How stiff the rubber band is: the larger, the sooner it gives way to its limit.
    private static let rubberStiffness: CGFloat = 0.55

    private var travelled: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastChange: TimeInterval?
    private var lockedUntil = -TimeInterval.infinity
    private var ignoring = false

    mutating func feed(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase, time: TimeInterval) -> Output {
        let delta = dx != 0 ? dx : dy
        guard delta.isFinite, momentum.isEmpty else { return .none }
        if phase.contains(.began) {
            reset()
            ignoring = time < lockedUntil
        } else if phase.contains(.mayBegin) {
            reset()
        }
        let ending = phase.contains(.ended) || phase.contains(.cancelled)
        if ignoring {
            if ending { ignoring = false }
            return .none
        }
        if delta != 0 {
            travelled += delta
            if let last = lastChange {
                let speed = delta / CGFloat(max(time - last, 1.0 / 240))
                velocity = velocity * 0.6 + speed * 0.4
            }
            lastChange = time
        }
        guard ending else { return delta != 0 ? .drag(raw: travelled) : .none }
        let was = travelled
        let speed = phase.contains(.cancelled) ? 0 : velocity
        reset()
        guard was != 0 else { return .none }
        lockedUntil = time + (reduceMotion ? 0 : HelmMotion.pageSettleDuration)
        return .release(step: phase.contains(.cancelled) ? 0 : Self.step(travelled: was, velocity: speed, width: width), velocity: speed)
    }

    private mutating func reset() { travelled = 0; velocity = 0; lastChange = nil }

    /// Where the page sits for `raw` points of drag: the fingers' own while there is a page to go to, a rubber band past the
    /// first and the last (it gives, ever less, and never by a whole page), never more than a page either way.
    static func offset(raw: CGFloat, canBack: Bool, canForward: Bool, width: CGFloat) -> CGFloat {
        guard raw.isFinite, width.isFinite, width > 0 else { return 0 }
        if raw > 0, !canBack { return rubber(raw, width) }
        if raw < 0, !canForward { return -rubber(-raw, width) }
        return raw.clamped(to: -width...width)
    }

    private static func rubber(_ x: CGFloat, _ width: CGFloat) -> CGFloat {
        (1 - 1 / (x * rubberStiffness / width + 1)) * width
    }

    /// -1 back, 0 stay, +1 forward: a turn when the page was pulled over half its width, or flicked: at least `flickSpeed`
    /// the same way as the travel, from `swipeDistance` on. Anything else, a nudge too, goes back to where it was.
    static func step(travelled: CGFloat, velocity: CGFloat, width: CGFloat) -> Int {
        guard travelled.isFinite, velocity.isFinite, width.isFinite, travelled != 0 else { return 0 }
        let way = travelled < 0 ? 1 : -1
        if abs(travelled) >= width / 2 { return way }
        let agrees = (velocity < 0) == (travelled < 0) && velocity != 0
        if abs(velocity) >= flickSpeed, agrees, abs(travelled) >= LaunchpadScrollPager.swipeDistance { return way }
        return 0
    }
}
