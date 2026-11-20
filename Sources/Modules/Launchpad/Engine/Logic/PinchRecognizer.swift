import Foundation

/// What a hand did: its fingers came together, or went apart.
public enum PinchDirection: Equatable, Sendable {
    case pinch, spread
}

/// Every number the recognizer judges by, in one place. **They are untuned guesses** until measured on a real trackpad:
/// a change here is the whole of a tuning, and the log's frame and fire counts are what it is tuned from.
struct PinchThresholds: Equatable, Sendable {
    var fingers = 4...5
    /// The hand has landed when its fingers have stayed this long (seconds) with the centroid inside `landedMovement`.
    var landedFor = 0.04
    var landedMovement = 0.03
    /// A fire needs the mean distance from the centroid to fall to `pinchRatio` of what it was (or rise to `spreadRatio`) and to have moved `minChange`.
    var pinchRatio = 0.70
    var spreadRatio = 1.35
    var minChange = 0.06
    /// The count may leave `fingers` this long (seconds) before the session is over.
    var countGrace = 0.10
    /// A centroid that travels this far with the spread unchanged is a swipe (Spaces, Mission Control), not a pinch.
    var swipeTravel = 0.15
    /// An armed hand that has not fired by then (seconds) is resting, not gesturing.
    var armedLimit = 2.0
}

/// Four or five fingers coming together or going apart, from frames of one trackpad. A value: `feed` is the whole of it.
///
/// A session starts when 4 or 5 fingers are down, is armed when they have held still enough to have landed, fires at most
/// once, and after a fire or a cancel says nothing until every finger has lifted. Time is the frames' own.
struct PinchRecognizer: Equatable, Sendable {
    private enum Phase: Equatable {
        case idle
        case landing(since: Double, anchor: Point, outSince: Double?)
        case armed(since: Double, anchor: Point, baseline: Double, count: Int, outSince: Double?)
        /// Fired or cancelled: nothing until the pad is empty.
        case spent
    }
    private struct Point: Equatable { var x: Double; var y: Double }

    let thresholds: PinchThresholds
    private var phase = Phase.idle
    /// The latest frame's time: a frame older than it is a clock that started over, and so a new session.
    private var lastTime = -Double.infinity

    init(thresholds: PinchThresholds = PinchThresholds()) { self.thresholds = thresholds }

    mutating func feed(_ frame: TouchFrame) -> PinchDirection? {
        let down = frame.down
        let t = frame.time
        if t < lastTime { phase = .idle }
        lastTime = t
        guard !down.isEmpty else { phase = .idle; return nil }
        let inRange = thresholds.fingers.contains(down.count)
        let centre = Point(x: down.map(\.x).reduce(0, +) / Double(down.count), y: down.map(\.y).reduce(0, +) / Double(down.count))
        let radius = down.map { hypot($0.x - centre.x, $0.y - centre.y) }.reduce(0, +) / Double(down.count)

        switch phase {
        case .spent:
            return nil
        case .idle:
            if inRange { phase = .landing(since: t, anchor: centre, outSince: nil) }
            return nil
        case .landing(let since, let anchor, _):
            guard inRange else { phase = outOfRange(at: t); return nil }
            if distance(centre, anchor) > thresholds.landedMovement {
                phase = .landing(since: t, anchor: centre, outSince: nil)
            } else if t - since >= thresholds.landedFor {
                phase = radius > 0 ? .armed(since: t, anchor: centre, baseline: radius, count: down.count, outSince: nil) : .spent
            } else {
                phase = .landing(since: since, anchor: anchor, outSince: nil)
            }
            return nil
        case .armed(let since, let anchor, let baseline, let count, _):
            guard inRange else { phase = outOfRange(at: t); return nil }
            // A finger landed or lifted inside 4 to 5: the spread was measured for another hand, so it is landed again.
            guard down.count == count else { phase = .landing(since: t, anchor: centre, outSince: nil); return nil }
            guard t - since <= thresholds.armedLimit else { phase = .spent; return nil }
            let change = radius - baseline
            if distance(centre, anchor) > thresholds.swipeTravel, abs(change) < thresholds.minChange { phase = .spent; return nil }
            let direction: PinchDirection? =
                radius / baseline <= thresholds.pinchRatio && -change >= thresholds.minChange ? .pinch
                : radius / baseline >= thresholds.spreadRatio && change >= thresholds.minChange ? .spread : nil
            phase = direction == nil ? .armed(since: since, anchor: anchor, baseline: baseline, count: count, outSince: nil) : .spent
            return direction
        }
    }

    /// The count left its range: the moment is remembered the first time, and the session is over once it has lasted past the grace.
    private func outOfRange(at t: Double) -> Phase {
        switch phase {
        case .landing(let since, let anchor, let out):
            if let out, t - out > thresholds.countGrace { return .spent }
            return .landing(since: since, anchor: anchor, outSince: out ?? t)
        case .armed(let since, let anchor, let baseline, let count, let out):
            if let out, t - out > thresholds.countGrace { return .spent }
            return .armed(since: since, anchor: anchor, baseline: baseline, count: count, outSince: out ?? t)
        case .idle, .spent:
            return phase
        }
    }

    private func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
