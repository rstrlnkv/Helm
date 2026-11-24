// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The state every VPN surface draws, and the one declaration of it.
///
/// Out of `VPNEngine`'s file and still `VPNEngine.StatePayload`, as
/// `KeepAwakeEngine.StatePayload` sits beside its engine: the same type, not a
/// copy, because a payload declared twice is two declarations of one fact.
extension VPNEngine {
    /// Public because the model reads it from `stream()` — see the note on KeepAwake's.
    /// `Equatable` because the engine refuses to emit a payload equal to the
    /// last one it sent (`emitState`): the poll re-reads many times behind one
    /// connect, and a duplicate would re-render every mounted page.
    public struct StatePayload: Equatable, Sendable {
        public let connections: [VPNConnection]
        public let autoConnected: [String]
        /// The last firing Helm caused, if any.
        public let lastAutomation: VPNAutomation?
        public var lastFailure: VPNFailure?
        /// Configurations Helm has a secret for and may not read unattended —
        /// `VPNSecretBook`. Sorted by the engine, so the page draws in one order.
        public var secretsBehindAPrompt: [String] = []
        /// Rules that will not fire, by bundle identifier, and the engine's own
        /// reason (`VPNRuleTrust.refusal(of:)`). A trusted rule has no entry.
        public var ruleRefusals: [String: VPNRuleTrust.Verdict] = [:]
        /// Every connected tunnel that has an interface reading, the one
        /// carrying the default route first.
        ///
        /// A list, so a Mac with two tunnels up can reach both. The order is what
        /// «the first» rests on (`VPNTunnelChoice.primaryFirst`): the page opens
        /// on it, and a selection naming a tunnel that has gone falls back to it.
        ///
        /// Empty when nothing is up — the strip is absent then, rather than
        /// empty.
        public var tunnels: [VPNTunnelState] = []
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
    /// **The tool's own answer first, Helm's observation behind it.** `scutil`
    /// writes `LastStatusChangeTime` at the end of every status read
    /// (`VPNStatusParser.Reading.since`), which also covers a VPN that started
    /// before Helm did. Helm's own stamp is there for a tool that does not answer.
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
    /// **Whether a measurement is in flight, as the engine's own answer**, not a
    /// flag the page sets on a press: a live fact somebody else owns needs a
    /// reverse channel (Architecture/ModulePattern.md § Module pattern). A page
    /// flag would miss a run started before the page opened, spin for a run that
    /// outlived its page, and never clear for a refused run that changed no other
    /// field. In the published state the start and the end of a run are both
    /// changes, so neither can be withheld.
    public let measuring: Bool

    init(name: String, interface: String, since: Date?, bytesIn: UInt64?,
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
    /// **Beside the value rather than at the engine's call site**, so
    /// `VPNEngine.tunnelStates` keeps to the engine's two questions: which
    /// tunnels, and in what order. The counters reach the state as whole
    /// kilobytes (`VPNInterfaceCounters.onTheWire`), and nil stays nil: an
    /// interface the kernel has no counters for is not a tunnel that has carried
    /// nothing. `since` is Helm's **own** observation and only the fallback: the
    /// tool's stamp is preferred, since Helm has none for a tunnel up before it.
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
