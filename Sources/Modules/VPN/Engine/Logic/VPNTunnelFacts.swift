// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The four readings the tile strip draws, and which of them are absent.
///
/// **Absent is a state, not a zero.** Helm can be launched after a tunnel came
/// up, in which case nobody saw the moment and there is no duration to show; the
/// tile is removed rather than drawn as «—», which would read as a measurement
/// of nothing. All four readings can be absent, the counters included: an
/// unreadable counter passed as `0` would draw as a tunnel that carried nothing.
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
    let speedAge: TimeInterval?

    /// After this long a reading is no longer offered as live: the link it
    /// measured is a minute of somebody's traffic away from the one on screen.
    ///
    /// Named because the test that proves the rule has to read the same number
    /// the rule does.
    static let speedGoesStaleAfter: TimeInterval = 60

    /// Whether the figure on screen may no longer stand as the link's speed now.
    /// True with no measurement at all, so the tile never draws a bare dash and
    /// leaves the reader to guess — and true for a negative age, the clock-skew
    /// case `init` already refuses for `since`. Whether an age can be drawn is
    /// `speedShowsItsAge`.
    var speedIsStale: Bool {
        guard let speedAge else { return true }
        return speedAge < 0 || speedAge > Self.speedGoesStaleAfter
    }

    /// Whether the figure has an age that can be *drawn* beside it — which is
    /// not the same question as `speedIsStale`. A stamp ahead of the clock is
    /// stale too, and drawing its age would print a time still to come, "in
    /// 5 min.", under a figure taken in the past.
    ///
    /// Nothing is drawn for that reading rather than something invented, which
    /// is what `HelmExpectedWait.Claim.at` does with the same input: «a negative
    /// elapsed time … is evidence that the stamp cannot be trusted». The unit
    /// stands alone, claiming no age at all.
    public var speedShowsItsAge: Bool {
        guard let speedAge, speedAge >= 0 else { return false }
        return speedIsStale
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
