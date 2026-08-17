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
public struct VPNTunnelFacts: Equatable, Sendable {
    /// How long the tunnel has been up, or nil when the moment was not seen.
    public let uptime: TimeInterval?
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    /// The last measurement, whenever it was taken.
    public let speed: VPNSpeedReading?
    /// How old that measurement is, in seconds.
    public let speedAge: TimeInterval?
    /// Whether the figure on screen is old enough that it must carry its age.
    /// True with no measurement at all, so the tile never draws a bare dash and
    /// leaves the reader to guess.
    public var speedIsStale: Bool { speed == nil || (speedAge ?? 0) > 0 }

    public init(since: Date?, bytesIn: UInt64, bytesOut: UInt64,
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
