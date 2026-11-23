// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// One `networkQuality` run: what came down and what went up, with the moment
/// it was taken, because a figure without its age is read as live.
public struct VPNSpeedReading: Equatable, Sendable {
    /// Megabits per second, rounded. The tool answers in bits.
    public let down: Int
    public let up: Int
    public let at: Date
    /// **How long the run that produced this took**, or nil when nobody timed
    /// it.
    ///
    /// The page draws an arc against an expected length while a measurement is
    /// in flight, and that length was a constant in a view: 22 s, measured on
    /// one Mac, on one link, on one afternoon. The tool times itself
    /// (`NetworkQualitySpeed.measure` runs inside `HelmActivity.phase`), so the
    /// number the arc is drawn against can be a fact about *this* link — which
    /// is what the reading already is.
    ///
    /// **Still not a stage.** The engine knows whether a run is in flight and
    /// nothing else; this publishes a *length*, so the arc goes on claiming the
    /// clock rather than the work (`HelmExpectedWait`).
    ///
    /// Optional: nil is what a run of no measurable length means, which is every
    /// reading a test's fixed clock produces.
    public let took: TimeInterval?

    init(down: Int, up: Int, at: Date, took: TimeInterval? = nil) {
        self.down = down
        self.up = up
        self.at = at
        self.took = took
    }

    /// **Both throughput figures or nothing.** A run that was killed at its deadline prints
    /// part of its JSON, and a reading built out of the half that arrived claims
    /// the link is 0 Mbit/s in the direction nobody measured.
    ///
    /// Which is also why every number goes through `whole`: this function exists
    /// because the tool's output cannot be trusted, and `Int(_: Double)` **traps**
    /// on a value outside `Int`'s range — refusing the document is the difference
    /// between a nil and the app going down on a line of JSON.
    static func parse(_ output: String, at: Date,
                             took: TimeInterval? = nil) -> VPNSpeedReading? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = json["dl_throughput"] as? Double,
              let up = json["ul_throughput"] as? Double,
              let downMbit = whole(down / 1_000_000),
              let upMbit = whole(up / 1_000_000)
        else { return nil }
        return VPNSpeedReading(down: downMbit, up: upMbit, at: at, took: took)
    }

    /// A figure the tool printed as a whole number this app can hold, or nil for
    /// one it cannot — out of range, not a number, or negative, which is not a
    /// link anybody measured.
    private static func whole(_ value: Double) -> Int? {
        guard value >= 0 else { return nil }
        return Int(exactly: value.rounded())
    }
}
