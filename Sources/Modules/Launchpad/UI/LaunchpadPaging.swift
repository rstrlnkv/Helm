import AppKit

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

    static func page(of index: Int, capacity: Int) -> Int {
        capacity > 0 ? max(0, index) / capacity : 0
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

/// What a scroll wheel or a trackpad says, as at most one page turn a gesture. Pure: no timer, time comes in with the event.
///
/// A trackpad swipe sums its deltas and turns once when 40 pt are travelled, and not again until the fingers lift; the
/// momentum after the lift never turns. A device that sends deltas with no phases at all is a swipe that ends when its
/// events stop for 250 ms. A wheel's notches turn once and then wait 250 ms by the events' own timestamps.
struct LaunchpadScrollPager {
    static let swipeDistance: CGFloat = 40
    static let wheelPause: TimeInterval = 0.25

    private var travelled: CGFloat = 0
    private var turned = false
    private var lastWheelTurn = -TimeInterval.infinity
    private var lastPhaseless = -TimeInterval.infinity

    /// -1 previous page, +1 next, nil nothing. The horizontal delta when there is one, else the vertical; a negative delta
    /// (content dragged left, a wheel rolled down) goes forward.
    mutating func feed(dx: CGFloat, dy: CGFloat, precise: Bool, phase: NSEvent.Phase, momentum: NSEvent.Phase,
                       time: TimeInterval) -> Int? {
        let delta = dx != 0 ? dx : dy
        guard delta.isFinite else { return nil }
        guard precise else { return wheel(delta, time) }
        if !momentum.isEmpty { return nil }
        if phase.isEmpty {
            if time - lastPhaseless >= Self.wheelPause { travelled = 0; turned = false }
            lastPhaseless = time
        }
        if phase.contains(.began) || phase.contains(.mayBegin) { travelled = 0; turned = false }
        defer { if phase.contains(.ended) || phase.contains(.cancelled) { travelled = 0; turned = false } }
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
