// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// **When to ask the outside world where this Mac appears to be.**
///
/// The check used to be tied to one event — Helm watching a tunnel go from down
/// to up — and an event is not a state. A tunnel that was already up when the
/// app launched was never watched coming up (`VPNEngine.wasDown` says why the
/// stamp cannot be invented), so it never had a country: the verdict line drew
/// «Traffic goes through the tunnel» with the half that names a place simply
/// missing, on the most ordinary Mac there is — one whose VPN is raised at login
/// and whose menu bar app is started after it. The same hole swallowed a probe
/// that failed: one timeout and the country was gone until the next time a
/// tunnel happened to come up.
///
/// So the question this answers is a state — «is there a tunnel up that has no
/// country» — and the answer is a decision rather than a poll. Three things
/// hold it back, and each is a different kind of no:
///
/// * nothing is up, or a country is already on record: there is nothing to ask.
/// * a request is already in flight: `VPNExitPort` waits up to eight seconds,
///   and every refresh behind one connect would otherwise start another. The
///   poll re-reads up to 26 times (`VPNEngine.poll`).
/// * the last attempt came back empty a moment ago: this is the app's one
///   request to a server that is not the update feed, and a refresh loop over a
///   blocked host would turn it into traffic somebody could watch.
///
/// Pure, because every one of those is a rule and none of them is a rendering —
/// and because the alternative is four conditions spelled inside a method that
/// also starts a `Task`, which is where the original defect lived.
public enum VPNExitAsk {

    /// How long an empty answer stands before the question may be asked again.
    ///
    /// A minute, and the number is chosen against what actually fails: the probe
    /// is refused in one go by a blocked host and takes its full eight-second
    /// timeout on a dead one, so the cost of retrying too eagerly is measured in
    /// requests per minute rather than in seconds of waiting. A person who wants
    /// the answer sooner than that has raised or dropped a tunnel, which is an
    /// event and goes round this gate (`VPNEngine.checkExit(force:)`).
    public static let quietPeriod: TimeInterval = 60

    /// Whether to make the request now.
    ///
    /// `lastAsked` is when the last attempt that came back **empty** was
    /// started. An attempt that answered leaves no mark at all: its code closes
    /// the question by itself, and what reopens it is the route moving — so a
    /// clock kept through a good answer would refuse the re-read the move
    /// exists to ask for.
    public static func should(tunnelIsUp: Bool, region: String?, asking: Bool,
                              lastAsked: Date?, now: Date) -> Bool {
        guard tunnelIsUp, region == nil, !asking else { return false }
        guard let lastAsked else { return true }
        // `>=` rather than `>`: the quiet period is how long the answer stands,
        // and a period that has elapsed exactly has elapsed.
        return now.timeIntervalSince(lastAsked) >= quietPeriod
    }

    /// Whether the country on record still belongs to the route it was read for.
    ///
    /// **A country is a fact about where the traffic leaves, so it belongs to the
    /// interface carrying the default route rather than to any tunnel.** Dropping
    /// it only when a tunnel falls was right about one way the exit moves and
    /// blind to the rest: Wi-Fi to Ethernet, a second tunnel taking the route
    /// from the first, a captive network coming and going — the route moves and
    /// the country goes on being drawn beside a tunnel it is no longer true of.
    /// Which is the worse of the two failures the gate above exists for: an
    /// absent country reads as «not known», a stale one reads as an answer.
    ///
    /// Nil on either side is not a move. The store answers nil for a Mac with no
    /// network at all *and* for a read that failed (`VPNInterfacePort`), and
    /// treating a failed read as a route change would drop a good answer every
    /// time the dynamic store hiccupped.
    public static func routeMoved(from previous: String?, to current: String?) -> Bool {
        guard let previous, let current else { return false }
        return previous != current
    }
}
