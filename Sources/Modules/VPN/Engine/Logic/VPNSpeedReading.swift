// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// One `networkQuality` run: what came down, what went up, and how responsive
/// the link was while it did — with the moment it was taken, because a figure
/// without its age is read as live.
public struct VPNSpeedReading: Codable, Equatable, Sendable {
    /// Megabits per second, rounded. The tool answers in bits.
    public let down: Int
    public let up: Int
    /// Apple's responsiveness figure, in round trips per minute.
    public let rpm: Int
    public let at: Date

    public init(down: Int, up: Int, rpm: Int, at: Date) {
        self.down = down
        self.up = up
        self.rpm = rpm
        self.at = at
    }

    /// **Every field or nothing.** A run that was killed at its deadline prints
    /// part of its JSON, and a reading built out of the half that arrived claims
    /// the link is 0 Mbit/s in the direction nobody measured.
    public static func parse(_ output: String, at: Date) -> VPNSpeedReading? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = json["dl_throughput"] as? Double,
              let up = json["ul_throughput"] as? Double
        else { return nil }
        // Responsiveness is the one figure the tool omits on a link it could not
        // characterise; zero is its own honest answer there.
        let rpm = (json["responsiveness"] as? Double) ?? 0
        return VPNSpeedReading(down: Int((down / 1_000_000).rounded()),
                               up: Int((up / 1_000_000).rounded()),
                               rpm: Int(rpm.rounded()),
                               at: at)
    }
}
