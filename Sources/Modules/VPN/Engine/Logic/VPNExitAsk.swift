// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// **When to ask the outside world where this Mac appears to be.**
///
/// The question is a state — «is there a tunnel up that has no country» — not
/// an event. A tunnel already up when Helm launched was never watched coming up
/// (`VPNEngine.wasDown`), and a probe that failed leaves no country either; both
/// still get asked. The answer is a decision rather than a poll. Three things
/// hold it back, and each is a different kind of no:
///
/// * nothing is up, or a country is already on record: there is nothing to ask.
/// * a request is already in flight: `VPNExitPort` waits up to eight seconds,
///   and every refresh of the connect poll (`VPNEngine.poll`) would otherwise
///   start another.
/// * the last attempt came back empty a moment ago: this is a
///   request to a server that is not the update feed, and a refresh loop over a
///   blocked host would turn it into traffic somebody could watch.
///
/// Pure, because every one of those is a rule and none of them is a rendering,
/// and four conditions inside a method that also starts a `Task` hide their bugs.
enum VPNExitAsk {

    /// How long after the start of an attempt that came back empty the question
    /// may not be asked again.
    ///
    /// A minute: the probe is refused at once by a blocked host and takes its
    /// full eight-second timeout on a dead one, so retrying too eagerly costs
    /// requests per minute rather than seconds of waiting. A person who wants
    /// the answer sooner than that has raised or dropped a tunnel, which is an
    /// event and goes round this gate (`VPNEngine.checkExit(force:)`).
    static let quietPeriod: TimeInterval = 60

    /// Whether to make the request now.
    ///
    /// `lastAsked` is when the last attempt that came back **empty** was
    /// started. An attempt that answered leaves no mark at all: its code closes
    /// the question by itself, and what reopens it is the route moving — so a
    /// clock kept through a good answer would refuse the re-read the move
    /// exists to ask for.
    static func should(tunnelIsUp: Bool, region: String?, asking: Bool,
                              lastAsked: Date?, now: Date) -> Bool {
        guard tunnelIsUp, region == nil, !asking else { return false }
        guard let lastAsked else { return true }
        // `>=` rather than `>`: the quiet period runs from the start of the empty
        // attempt, and a period that has elapsed exactly has elapsed.
        return now.timeIntervalSince(lastAsked) >= quietPeriod
    }

    /// Whether the country on record still belongs to the route it was read for.
    ///
    /// **A country is a fact about where the traffic leaves, so it belongs to the
    /// interface carrying the default route rather than to any tunnel.** The exit
    /// also moves from Wi-Fi to Ethernet, from one tunnel to a second, or with a
    /// captive network. A stale country is worse than an absent one: an absent
    /// one reads as «not known», a stale one reads as an answer.
    ///
    /// Nil on either side is not a move. The store answers nil for a Mac with no
    /// network at all *and* for a read that failed (`VPNInterfacePort`), and
    /// treating a failed read as a route change would drop a good answer every
    /// time the dynamic store hiccupped.
    static func routeMoved(from previous: String?, to current: String?) -> Bool {
        guard let previous, let current else { return false }
        return previous != current
    }
}
