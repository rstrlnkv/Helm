// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The four readings the tile strip draws, and which of them are absent.
///
/// **Absent is a state, not a zero.** Helm can be launched after a tunnel came
/// up, in which case nobody saw the moment and there is no duration to show; the
/// tile is removed rather than drawn as «—», which would read as a measurement
/// of nothing. The same distinction the credential read makes one file over
/// (`VPNCredentialRead`): a nil that means two things is a nil that says nothing.
///
/// That held for two of the four and not for the counters, which were
/// non-optional — so an interface the kernel had no counters for could only be
/// passed as `0`, and «nobody could read this» drew as a tunnel that has carried
/// nothing. A header claiming a state the type cannot hold is the shape this
/// repository keeps finding; all four can be absent now.
public struct VPNTunnelFacts: Equatable, Sendable {
    /// How long the tunnel has been up, or nil when the moment was not seen.
    public let uptime: TimeInterval?
    /// What the tunnel's interface has carried, or nil when the kernel had no
    /// counters for it. **Zero is a measurement here** — a tunnel raised a
    /// second ago has genuinely carried nothing — which is exactly why the
    /// unreadable case needs its own value.
    public let bytesIn: UInt64?
    public let bytesOut: UInt64?
    /// The last measurement, whenever it was taken.
    public let speed: VPNSpeedReading?
    /// How old that measurement is, in seconds.
    public let speedAge: TimeInterval?

    /// After this long a reading is no longer offered as live: the link it
    /// measured is a minute of somebody's traffic away from the one on screen.
    ///
    /// A named threshold because the test that proves the rule has to read the
    /// same number the rule does, and because the rule it replaced could not
    /// fail: `speedAge` is non-nil whenever `speed` is, so `(speedAge ?? 0) > 0`
    /// called a reading taken a microsecond ago stale and
    /// `var speedIsStale: Bool { true }` passed the whole suite.
    public static let speedGoesStaleAfter: TimeInterval = 60

    /// Whether the figure on screen must carry its age rather than stand as the
    /// link's speed now. True with no measurement at all, so the tile never
    /// draws a bare dash and leaves the reader to guess — and true for a
    /// negative age, which is the clock-skew case `init` already refuses for
    /// `since`: a figure stamped in the future has no age to show.
    public var speedIsStale: Bool {
        guard let speedAge else { return true }
        return speedAge < 0 || speedAge > Self.speedGoesStaleAfter
    }

    public init(since: Date?, bytesIn: UInt64?, bytesOut: UInt64?,
                speed: VPNSpeedReading?, now: Date) {
        if let since, since <= now {
            uptime = now.timeIntervalSince(since)
        } else {
            uptime = nil
        }
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.speed = speed
        speedAge = speed.map { now.timeIntervalSince($0.at) }
    }
}
