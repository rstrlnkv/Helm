import Foundation

/// One finger on a trackpad, in the pad's own coordinates: 0 to 1 across each axis.
struct Touch: Equatable, Sendable {
    let x: Double
    let y: Double
    /// In contact with the pad, as against hovering over it or leaving it.
    let isDown: Bool
}

/// One frame of what a trackpad reports: the fingers on it at one moment, read from a private layout (MultitouchSupport's
/// records) that Apple does not document and has changed before. The initialiser is therefore the only way in, and it
/// refuses what no real pad sends, so a layout that moved reads as a run of refused frames (`FrameTrust`) and never as a hand.
struct TouchFrame: Equatable, Sendable {
    /// Which trackpad sent it (its place in the list the system gave), so two pads are never one hand.
    let device: Int
    /// The frame's own clock, in seconds; every judgement of time uses it, never `Date()`.
    let time: Double
    let touches: [Touch]

    static let maxTouches = 10
    /// A finger may be reported a little past the pad's edge, no further.
    static let positionRange = -0.05...1.05
    /// The record's `state` value for a finger in contact (`MTTouchStateTouching`); the system's own states run 0 through 7.
    static let touchingState = 4
    static let stateRange = 0...7
    /// The port watches this many pads at most and ignores the rest; it is also the range a frame's `device` may have.
    static let maxDevices = 16

    /// nil when `count` is not 0 through `maxTouches` (checked before `touch` is asked for any record, so a wild count
    /// reads nothing), when `device` is outside 0 up to `maxDevices` or `time` is not finite, or when any record has a position that is no number or lies
    /// outside the range, or a state the system does not have. `touch(i)` answers record `i` as (x, y, state).
    init?(device: Int, time: Double, count: Int, touch: (Int) -> (x: Double, y: Double, state: Int)) {
        guard (0..<Self.maxDevices).contains(device), time.isFinite, (0...Self.maxTouches).contains(count) else { return nil }
        var read: [Touch] = []
        read.reserveCapacity(count)
        for index in 0..<count {
            let record = touch(index)
            guard Self.positionRange.contains(record.x), Self.positionRange.contains(record.y), Self.stateRange.contains(record.state)
            else { return nil }
            read.append(Touch(x: record.x, y: record.y, isDown: record.state == Self.touchingState))
        }
        self.device = device
        self.time = time
        touches = read
    }

    var down: [Touch] { touches.filter(\.isDown) }
}

/// Counts refused frames in a row; a good one clears the count. A pad that sends a few bad frames is noise, one that sends
/// only bad ones is a layout that is not the one assumed, and the watch stands down (`standDown`).
struct FrameTrust: Equatable, Sendable {
    /// About a third of a second of one pad's frames.
    static let limit = 30
    private(set) var refused = 0

    /// True once, when this refusal is the one that reaches the limit.
    mutating func note(accepted: Bool) -> Bool {
        if accepted { refused = 0; return false }
        refused += 1
        return refused == Self.limit
    }
}
