// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// **Whether a tunnel that is not up has actually been lost.**
///
/// The drop notice is this module's only interrupting signal — its own comment
/// says why: «the person is now sending everything in clear having last been
/// told they were behind a tunnel». It was fired the moment one `scutil --nc
/// list` read showed a watched tunnel not up, and a NetworkExtension tunnel
/// re-handshaking on a Wi-Fi change or a wake does exactly that for a few
/// seconds.
///
/// Measured on the owner's machine, in the log and in the tool in the same
/// breath: `automatic connection dropped` at 14:57:19, and `scutil --nc status`
/// reporting `LastStatusChangeTime : 14:57:22` — back three seconds later. Twice
/// in the two days of log there was to read. A signal that cries wolf on a
/// three-second blip is a signal people switch off, and then the real drop is
/// silent too.
///
/// **A clock, not a timer.** The engine already takes its own `now`, and the
/// verdict is asked at each refresh; a deferred block would have been the
/// obvious shape and is untestable here, because `VPNWorkQueue.inline` runs a
/// delayed block immediately — the poll loop depends on that — so the wait would
/// be over before a test could say what happened during it (CLAUDE.md § a fake
/// that finishes instantly makes a test of a wait vacuous).
public enum VPNDropSettle {

    /// How long a tunnel has to stay down before its loss is announced.
    ///
    /// Five seconds, and the number is chosen against what was measured rather
    /// than picked: the blips in the log healed in three. It is also the whole
    /// cost of the change to somebody whose tunnel really has gone — five
    /// seconds later than before, on a notice they will act on for minutes.
    public static let window: TimeInterval = 5

    /// What to do with a tunnel that was seen falling.
    public enum Verdict: Equatable, Sendable {
        /// It is up again. Nothing was lost and nothing is said.
        case healed
        /// Still down, but not for long enough to be sure.
        case waiting
        /// Still down past the window: this is the drop the notice exists for.
        case announce
    }

    /// **Up wins over the clock, at any age.** A tunnel that is up is not a
    /// tunnel that was lost, however long it took to come back — announcing one
    /// that has returned is the false alarm this whole type exists to remove.
    ///
    /// A clock that went backwards — somebody setting the date, or NTP stepping
    /// it — leaves the verdict `waiting` rather than announcing, because a
    /// negative interval is not five seconds having passed. The drop is then
    /// announced at the first refresh after the clock is ahead of the stamp
    /// again, which is the safe direction: late news rather than invented news.
    public static func verdict(fellAt: Date, isUpNow: Bool, now: Date) -> Verdict {
        if isUpNow { return .healed }
        return now.timeIntervalSince(fellAt) >= window ? .announce : .waiting
    }
}
