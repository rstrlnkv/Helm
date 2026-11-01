// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The state every VPN surface draws, and the one declaration of it.
///
/// Out of `VPNEngine` and still `VPNEngine.StatePayload`, the way
/// `KeepAwakeEngine.StatePayload` already sits beside its engine: an extension
/// keeps the name every reader spells while taking the payload out of the middle
/// of the connect logic. The name is the point — the same type, not a copy —
/// because a payload declared twice is two declarations of one fact.
extension VPNEngine {
    /// Public because the model reads it from `stream()` — see the note on KeepAwake's.
    /// `Equatable` because the engine refuses to emit a payload equal to the
    /// last one it sent (`emitState`): the poll re-reads up to 26 times behind
    /// one connect, and every field-for-field duplicate it produced re-rendered
    /// every mounted page to learn nothing.
    public struct StatePayload: Equatable, Sendable {
        public let connections: [VPNConnection]
        public let autoConnected: [String]
        /// The last firing Helm caused, if any.
        public let lastAutomation: VPNAutomation?
        public var lastFailure: VPNFailure?
        /// Configurations Helm has a secret for and may not read unattended —
        /// `VPNSecretBook`. Sorted by the engine, so the page draws in one order.
        public var secretsBehindAPrompt: [String] = []
        /// Every connected tunnel that has an interface reading, the one
        /// carrying the default route first.
        ///
        /// It was one `VPNTunnelState?` — the routed tunnel, or the first that
        /// was up — so a Mac with two tunnels up drew one of them and offered no
        /// way to reach the other. The order is what «the first» rests on
        /// (`VPNTunnelChoice.primaryFirst`): the page opens on it, and a
        /// selection naming a tunnel that has gone falls back to it.
        ///
        /// Empty when nothing is up — the strip is absent then, rather than
        /// empty.
        public var tunnels: [VPNTunnelState] = []

        init(connections: [VPNConnection], autoConnected: [String],
             lastAutomation: VPNAutomation?, lastFailure: VPNFailure? = nil,
             secretsBehindAPrompt: [String] = [], tunnels: [VPNTunnelState] = []) {
            self.connections = connections
            self.autoConnected = autoConnected
            self.lastAutomation = lastAutomation
            self.lastFailure = lastFailure
            self.secretsBehindAPrompt = secretsBehindAPrompt
            self.tunnels = tunnels
        }

    }
}

/// What the page's tile strip draws, as one value.
///
/// Its own type rather than six loose fields on the payload: each value is true of
/// *one* tunnel — the engine builds one for each connected tunnel the tool has
/// named an interface for, and `StatePayload.tunnels` lists them — and six
/// optionals side by side invite a reader to mix a name from one refresh with a
/// byte count from the next.
public struct VPNTunnelState: Equatable, Sendable {
    public let name: String
    public let interface: String
    /// When the tunnel came up.
    ///
    /// **The tool's own answer first, Helm's observation behind it.** This said
    /// «when Helm saw it come up, or nil when it was already up at launch», and
    /// that nil was on screen as a missing column on every Mac whose VPN starts
    /// before the menu bar app does — while `scutil` had been writing
    /// `LastStatusChangeTime` at the end of every status read the engine already
    /// performs (`VPNStatusParser.Reading.since`). Helm's own stamp is still
    /// there for the tool that does not answer.
    public let since: Date?
    /// What this configuration carries **around** the tunnel: the local network,
    /// Apple's own, anything else counted (`VPNExcludedRoutes`).
    ///
    /// The summary rather than the ranges, because a range is a fact about
    /// somebody's network and this module already refuses to put an exit address
    /// in the published state for the same reason. `.none` is «excludes nothing», which is
    /// a real answer — a status read that failed produces no tunnel at all.
    public let excluded: VPNExcludedRoutes.Summary
    /// Whole kilobytes, not bytes — see `VPNInterfaceCounters.onTheWire` for
    /// what a raw counter costs a page that redraws on every payload. Nil when
    /// the kernel had no counters for the interface, which is not the same news
    /// as a tunnel that has carried nothing (`VPNTunnelFacts`).
    public let bytesIn: UInt64?
    public let bytesOut: UInt64?
    /// Where the traffic actually leaves from. `.unknown` when a reading it
    /// needs is missing (`VPNExitVerdict.of`).
    public let exit: VPNExitVerdict
    public let speed: VPNSpeedReading?
    /// **Whether a measurement is in flight, as the engine's own answer.**
    ///
    /// It began as a `@Published` flag on the view model, set on the press and
    /// cleared by the arrival of any state — a local boolean standing in for a
    /// live fact somebody else owns, which is the family ARCHITECTURE.md
    /// § Module pattern names: a port that can change under the app has a reverse
    /// channel.
    /// It could be wrong in three ways at once: a page opened while a run was
    /// going knew nothing about it, a run outliving the page that started it
    /// spun a spinner nobody would clear, and — the one that shipped — a run the
    /// tool refused over a quiet tunnel changed no other field, so `emitState`
    /// withheld the payload as a duplicate and the arrival that was supposed to
    /// clear the spinner never came.
    ///
    /// In the published state it fixes that by construction rather than by a rule anybody
    /// has to keep: the start and the end of a run are both changes, so neither
    /// can be withheld.
    public let measuring: Bool

    public init(name: String, interface: String, since: Date?, bytesIn: UInt64?,
                bytesOut: UInt64?, exit: VPNExitVerdict, speed: VPNSpeedReading?,
                measuring: Bool = false,
                excluded: VPNExcludedRoutes.Summary = .none) {
        self.name = name
        self.interface = interface
        self.since = since
        self.excluded = excluded
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.exit = exit
        self.speed = speed
        self.measuring = measuring
    }
}

extension VPNTunnelState {
    /// One tunnel's reading, assembled from what the engine remembers about it.
    ///
    /// **Here rather than at the engine's call site**, which is where it was: it
    /// is the construction of a published value out of seven remembered facts, and
    /// putting it beside the value keeps `VPNEngine.tunnelStates` to the two
    /// questions that are actually the engine's — which tunnels, and in what
    /// order. The counters reach the state as whole kilobytes for the reason
    /// `VPNInterfaceCounters.onTheWire` gives, and nil stays nil: an interface
    /// the kernel has no counters for is not a tunnel that has carried nothing.
    /// `since` is Helm's **own** observation, and it is the fallback: the tool's
    /// stamp is preferred where there is one. Written the other way round the
    /// change would be invisible on the machine it was made for — Helm has no
    /// observation there, which is the whole defect.
    init(_ connection: VPNConnection, on reading: VPNStatusParser.Reading,
         primary: String?, since: Date?, carried: (in: UInt64, out: UInt64)?,
         speed: VPNSpeedReading?, region: String?, measuring: Bool) {
        self.init(name: connection.name,
                  interface: reading.interface,
                  since: reading.since ?? since,
                  bytesIn: carried.map { VPNInterfaceCounters.onTheWire($0.in) },
                  bytesOut: carried.map { VPNInterfaceCounters.onTheWire($0.out) },
                  exit: VPNExitVerdict.of(tunnelInterface: reading.interface,
                                          primaryInterface: primary,
                                          tunnelIsPrimary: reading.isPrimaryInterface,
                                          countryCode: region),
                  speed: speed,
                  measuring: measuring,
                  excluded: VPNExcludedRoutes.summarize(reading.excludedRoutes))
    }
}
