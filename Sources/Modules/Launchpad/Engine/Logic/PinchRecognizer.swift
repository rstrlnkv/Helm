import Foundation

/// What a hand did: its fingers came together, or went apart.
public enum PinchDirection: Equatable, Sendable {
    case pinch, spread
}

/// How a scrub ended: the hand's progress reached the commit point or was flicked there (`complete`), or fell short (`revert`).
public enum PinchOutcome: Equatable, Sendable {
    case complete, revert
}

/// What a hand did to the window, frame by frame: it began a scrub (`progress` 0 to 1, where 1 is what the old one-shot
/// pinch needed), moved it, and ended it. At most one event comes from one frame.
public enum PinchEvent: Equatable, Sendable {
    case began(PinchDirection, progress: Double)
    case moved(Double)
    case ended(PinchOutcome)
}

/// Every number the recognizer judges by, in one place. **They are untuned guesses** until measured on a real trackpad:
/// a change here is the whole of a tuning, and the log's frame and scrub counts are what it is tuned from.
struct PinchThresholds: Equatable, Sendable {
    var fingers = 4...5
    /// The hand has landed when its fingers have stayed this long (seconds) with the centroid inside `landedMovement`.
    var landedFor = 0.04
    var landedMovement = 0.03
    /// Progress is 1 when the mean distance from the centroid has fallen to `pinchRatio` of what it was (or risen to `spreadRatio`)
    /// and has moved `minChange`: where the one-shot pinch fired.
    var pinchRatio = 0.70
    var spreadRatio = 1.35
    var minChange = 0.06
    /// Progress is 0 until the ratio passes `beginRatio` (`beginSpreadRatio`) and the distance moves `beginChange`: the dead zone of a resting hand.
    var beginRatio = 0.92
    var beginSpreadRatio = 1.08
    var beginChange = 0.02
    /// A scrub begins when progress has stayed at least `beginProgress` for `beginHold` seconds and the spread change is at
    /// least `swipeShare` times the centroid's travel: a swipe moves the centroid more than it changes the spread.
    var beginProgress = 0.08
    var beginHold = 0.04
    var swipeShare = 1.0
    /// A `moved` event follows a change of at least this much progress, and the ends 0 and 1 always.
    var progressStep = 0.004
    /// A scrub completes at this progress, or at `flickFloor` when progress was rising at `flickSpeed` (a second's share of the whole)
    /// over the last `speedWindow` seconds.
    var commitAt = 0.5
    var flickSpeed = 2.0
    var flickFloor = 0.15
    var speedWindow = 0.08
    /// A scrub held longer than this (seconds) is reverted: the hand is resting.
    var scrubLimit = 10.0
    /// The count may leave `fingers` this long (seconds) before the session is over.
    var countGrace = 0.10
    /// A centroid that travels this far with the spread unchanged is a swipe (Spaces, Mission Control), not a pinch.
    var swipeTravel = 0.15
    /// A hand armed and not yet scrubbing by then (seconds) is resting, not gesturing.
    var armedLimit = 2.0
}

/// Four or five fingers coming together or going apart, from frames of one trackpad. A value: `feed` is the whole of it.
///
/// A session starts when 4 or 5 fingers are down and is armed when they have held still enough to have landed. An armed
/// hand whose fingers have clearly come together or gone apart, not swiped, begins a scrub; the scrub follows the hand
/// until it ends (every finger lifted, a finger more or less, a swipe, too long), and after any end it says nothing until
/// every finger has lifted. Time is the frames' own.
struct PinchRecognizer: Equatable, Sendable {
    private struct Point: Equatable { var x: Double; var y: Double }
    private struct Sample: Equatable { var t: Double; var p: Double }
    /// A direction seen since `since` at a progress that qualifies.
    private struct Pending: Equatable { var direction: PinchDirection; var since: Double }
    private struct Scrub: Equatable {
        var direction: PinchDirection
        var since: Double
        var anchor: Point
        var baseline: Double
        var count: Int
        var progress: Double
        var emitted: Double
        var outSince: Double?
        /// At most 16, none older than `speedWindow` before the newest.
        var samples: [Sample]
    }
    private enum Phase: Equatable {
        case idle
        case landing(since: Double, anchor: Point, outSince: Double?)
        case armed(since: Double, anchor: Point, baseline: Double, count: Int, outSince: Double?, pending: Pending?)
        case scrubbing(Scrub)
        /// Ended or cancelled: nothing until the pad is empty.
        case spent
    }

    let thresholds: PinchThresholds
    private var phase = Phase.idle
    /// The latest frame's time: a frame older than it is a clock that started over, and so a new session.
    private var lastTime = -Double.infinity

    init(thresholds: PinchThresholds = PinchThresholds()) { self.thresholds = thresholds }

    mutating func feed(_ frame: TouchFrame) -> PinchEvent? {
        let down = frame.down
        let t = frame.time
        let wasScrubbing: Bool = if case .scrubbing = phase { true } else { false }
        if t < lastTime {
            phase = .idle
            lastTime = t
            return wasScrubbing ? .ended(.revert) : nil
        }
        lastTime = t
        guard !down.isEmpty else {
            let event = ended(at: t, after: phase)
            phase = .idle
            return event
        }
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
                phase = radius > 0 ? .armed(since: t, anchor: centre, baseline: radius, count: down.count, outSince: nil, pending: nil) : .spent
            } else {
                phase = .landing(since: since, anchor: anchor, outSince: nil)
            }
            return nil
        case .armed(let since, let anchor, let baseline, let count, _, let pending):
            guard inRange else { phase = outOfRange(at: t); return nil }
            // A finger landed or lifted inside 4 to 5: the spread was measured for another hand, so it is landed again.
            guard down.count == count else { phase = .landing(since: t, anchor: centre, outSince: nil); return nil }
            guard t - since <= thresholds.armedLimit else { phase = .spent; return nil }
            let change = radius - baseline
            let travel = distance(centre, anchor)
            if travel > thresholds.swipeTravel, abs(change) < thresholds.minChange { phase = .spent; return nil }
            let direction: PinchDirection? = change < 0 ? .pinch : change > 0 ? .spread : nil
            let share = direction.map { progress($0, radius: radius, baseline: baseline) } ?? 0
            guard let direction, share >= thresholds.beginProgress, abs(change) >= thresholds.swipeShare * travel else {
                phase = .armed(since: since, anchor: anchor, baseline: baseline, count: count, outSince: nil, pending: nil)
                return nil
            }
            guard let pending, pending.direction == direction else {
                phase = .armed(since: since, anchor: anchor, baseline: baseline, count: count, outSince: nil, pending: Pending(direction: direction, since: t))
                return nil
            }
            guard t - pending.since >= thresholds.beginHold else { return nil }
            phase = .scrubbing(Scrub(direction: direction, since: t, anchor: anchor, baseline: baseline, count: count, progress: share,
                                     emitted: share, outSince: nil, samples: [Sample(t: t, p: share)]))
            return .began(direction, progress: share)
        case .scrubbing(var scrub):
            guard inRange else {
                let out = scrub.outSince ?? t
                if t - out > thresholds.countGrace {
                    let event = PinchEvent.ended(outcome(scrub, end: out))
                    phase = .spent
                    return event
                }
                scrub.outSince = out
                phase = .scrubbing(scrub)
                return nil
            }
            guard down.count == scrub.count else {
                let event = PinchEvent.ended(outcome(scrub, end: t))
                phase = .spent
                return event
            }
            scrub.outSince = nil
            let change = radius - scrub.baseline
            let swiped = distance(centre, scrub.anchor) > thresholds.swipeTravel && abs(change) < thresholds.minChange
            if swiped || t - scrub.since > thresholds.scrubLimit {
                phase = .spent
                return .ended(.revert)
            }
            scrub.progress = progress(scrub.direction, radius: radius, baseline: scrub.baseline)
            scrub.samples.append(Sample(t: t, p: scrub.progress))
            scrub.samples.removeAll { $0.t < t - thresholds.speedWindow }
            if scrub.samples.count > 16 { scrub.samples.removeFirst(scrub.samples.count - 16) }
            let moved = scrub.progress != scrub.emitted
                && (abs(scrub.progress - scrub.emitted) >= thresholds.progressStep || scrub.progress == 0 || scrub.progress == 1)
            if moved { scrub.emitted = scrub.progress }
            phase = .scrubbing(scrub)
            return moved ? .moved(scrub.progress) : nil
        }
    }

    /// How far `direction`'s gesture has come, 0 to 1: the smaller of the ratio's share and the distance's share, so it is 1 exactly
    /// where the one-shot pinch fired. Not a number is 0.
    private func progress(_ direction: PinchDirection, radius: Double, baseline: Double) -> Double {
        let ratio = radius / baseline
        let t = thresholds
        let ratioShare: Double, absShare: Double
        switch direction {
        case .pinch:
            ratioShare = (t.beginRatio - ratio) / (t.beginRatio - t.pinchRatio)
            absShare = ((baseline - radius) - t.beginChange) / (t.minChange - t.beginChange)
        case .spread:
            ratioShare = (ratio - t.beginSpreadRatio) / (t.spreadRatio - t.beginSpreadRatio)
            absShare = ((radius - baseline) - t.beginChange) / (t.minChange - t.beginChange)
        }
        let share = min(ratioShare, absShare)
        return share.isNaN ? 0 : min(max(share, 0), 1)
    }

    /// The end of a scrub that stopped at `phase`'s last progress; nil when the phase was no scrub.
    private func ended(at t: Double, after phase: Phase) -> PinchEvent? {
        guard case .scrubbing(let scrub) = phase else { return nil }
        return .ended(outcome(scrub, end: t))
    }

    /// Complete from `commitAt`, or from `flickFloor` when the last `speedWindow` seconds before `end` were rising at `flickSpeed`.
    private func outcome(_ scrub: Scrub, end: Double) -> PinchOutcome {
        if scrub.progress >= thresholds.commitAt { return .complete }
        let recent = scrub.samples.filter { $0.t >= end - thresholds.speedWindow && $0.t <= end }
        guard let first = recent.first, let last = recent.last, recent.count >= 2, last.t - first.t >= 0.02 else { return .revert }
        let speed = (last.p - first.p) / (last.t - first.t)
        return speed >= thresholds.flickSpeed && scrub.progress >= thresholds.flickFloor ? .complete : .revert
    }

    /// The count left its range: the moment is remembered the first time, and the session is over once it has lasted past the grace.
    private func outOfRange(at t: Double) -> Phase {
        switch phase {
        case .landing(let since, let anchor, let out):
            if let out, t - out > thresholds.countGrace { return .spent }
            return .landing(since: since, anchor: anchor, outSince: out ?? t)
        case .armed(let since, let anchor, let baseline, let count, let out, _):
            if let out, t - out > thresholds.countGrace { return .spent }
            return .armed(since: since, anchor: anchor, baseline: baseline, count: count, outSince: out ?? t, pending: nil)
        case .idle, .spent, .scrubbing:
            return phase
        }
    }

    private func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
