// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The state every VPN surface draws, and the one declaration of it.
///
/// Out of `VPNEngine` and still `VPNEngine.StatePayload`, the way
/// `KeepAwakeEngine.StatePayload` already sits beside its engine: an extension
/// keeps the name every reader spells while taking a wire type with a
/// hand-written decoder out of the middle of the connect logic. The name is the
/// point — the same type, not a copy — because a payload declared twice is
/// matched by field name across a JSON hop with no compiler in between.
extension VPNEngine {
    /// Public because the page decodes it — see the note on KeepAwake's.
    /// `Equatable` because the engine refuses to emit a payload equal to the
    /// last one it sent (`emitState`): the poll re-reads up to 26 times behind
    /// one connect, and every field-for-field duplicate it produced re-rendered
    /// every mounted page to learn nothing.
    public struct StatePayload: Codable, Equatable {
        public let connections: [VPNConnection]
        public let autoConnected: [String]
        public let defaultName: String?
        /// The last firing Helm caused, if any. Optional, so the synthesized
        /// decoder reads it with `decodeIfPresent` and a payload written before
        /// this field existed still decodes — a throw here would cost the page
        /// its whole state for the sake of one field.
        /// `VPNAutomationRecordingTests` holds a payload without it.
        public let lastAutomation: VPNAutomation?
        /// Optional for the same reason as the field above: a payload written
        /// before it existed still decodes, and a throw here would cost the
        /// page its whole state for the sake of one field.
        public var lastFailure: VPNFailure?
        /// Configurations Helm has a secret for and may not read unattended —
        /// `VPNSecretBook`. Sorted by the engine, so the page draws in one order.
        ///
        /// **Not an `Optional`, so this payload needed a decoder of its own.** The
        /// three fields above are optional and Swift's synthesised `Decodable`
        /// reads those with `decodeIfPresent`; a non-optional array with a stored
        /// default is still a required key, and a document missing it throws —
        /// taking every connection the page draws with it (CLAUDE.md § a
        /// `defaulted` property on a `Codable` payload).
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
        /// empty. Non-optional, and therefore one more reason the decoder below
        /// is hand-written.
        public var tunnels: [VPNTunnelState] = []

        init(connections: [VPNConnection], autoConnected: [String], defaultName: String?,
             lastAutomation: VPNAutomation?, lastFailure: VPNFailure? = nil,
             secretsBehindAPrompt: [String] = [], tunnels: [VPNTunnelState] = []) {
            self.connections = connections
            self.autoConnected = autoConnected
            self.defaultName = defaultName
            self.lastAutomation = lastAutomation
            self.lastFailure = lastFailure
            self.secretsBehindAPrompt = secretsBehindAPrompt
            self.tunnels = tunnels
        }

        public init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            connections = try box.decode([VPNConnection].self, forKey: .connections)
            autoConnected = try box.decode([String].self, forKey: .autoConnected)
            defaultName = try box.decodeIfPresent(String.self, forKey: .defaultName)
            lastAutomation = try box.decodeIfPresent(VPNAutomation.self, forKey: .lastAutomation)
            lastFailure = try box.decodeIfPresent(VPNFailure.self, forKey: .lastFailure)
            secretsBehindAPrompt = try box.decodeIfPresent([String].self,
                                                           forKey: .secretsBehindAPrompt) ?? []
            // **The key this payload used to carry, read as a one-element
            // list.** A document written by the build before the switcher names
            // `facts` and no `tunnels` at all, and a decoder that only asked for
            // the new key would answer «nothing is up» on the first launch after
            // an update — for a Mac with a tunnel up and a strip that should be
            // on the screen. Neither key is a Mac from before the strip existed.
            if let listed = try box.decodeIfPresent([VPNTunnelState].self, forKey: .tunnels) {
                tunnels = listed
            } else {
                let older = try decoder.container(keyedBy: OlderPayloadKeys.self)
                tunnels = try older.decodeIfPresent(VPNTunnelState.self, forKey: .facts)
                    .map { [$0] } ?? []
            }
        }
    }
}

/// The one key `StatePayload` used to carry and no longer has a property for.
///
/// **Its own enum, not a case added to `CodingKeys`**: those are synthesised
/// from the properties and drive `encode` as well, so a case with nothing behind
/// it costs the type its `Encodable` conformance outright — measured, not
/// guessed. At file scope rather than nested, which is one level too deep here.
/// Read, never written.
private enum OlderPayloadKeys: String, CodingKey { case facts }

/// What the page's tile strip draws, as one value on the wire.
///
/// Its own type rather than six loose fields on the payload: they are true of
/// *one* tunnel — the one holding the default route — and six optionals side by
/// side invite a reader to mix a name from one refresh with a byte count from
/// the next.
public struct VPNTunnelState: Codable, Equatable, Sendable {
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
    /// on the wire for the same reason. `.none` is «excludes nothing», which is
    /// a real answer — a status read that failed produces no tunnel at all.
    public let excluded: VPNExcludedRoutes.Summary
    /// Whole kilobytes, not bytes — see `VPNInterfaceCounters.onTheWire` for
    /// what a raw counter costs a page that redraws on every payload. Nil when
    /// the kernel had no counters for the interface, which is not the same news
    /// as a tunnel that has carried nothing (`VPNTunnelFacts`).
    public let bytesIn: UInt64?
    public let bytesOut: UInt64?
    /// Where the traffic actually leaves from. `.unknown` until the first check
    /// answers.
    public let exit: VPNExitVerdict
    public let speed: VPNSpeedReading?
    /// **Whether a measurement is in flight, as the engine's own answer.**
    ///
    /// It began as a `@Published` flag on the view model, set on the press and
    /// cleared by the arrival of any state — a local boolean standing in for a
    /// live fact somebody else owns, which is the family CLAUDE.md names in
    /// § Anything that can stop being true on its own owns a channel to say so.
    /// It could be wrong in three ways at once: a page opened while a run was
    /// going knew nothing about it, a run outliving the page that started it
    /// spun a spinner nobody would clear, and — the one that shipped — a run the
    /// tool refused over a quiet tunnel changed no other field, so `emitState`
    /// withheld the payload as a duplicate and the arrival that was supposed to
    /// clear the spinner never came.
    ///
    /// On the wire it fixes that by construction rather than by a rule anybody
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

    /// Hand-written for the field above: a stored default does **not** make a
    /// document without the key decode — Swift's synthesised `Decodable` wants
    /// it regardless and `JSONDecoder` then gives up on the whole payload, which
    /// here is every tile the strip draws (CLAUDE.md § a `defaulted` property on
    /// a `Codable` payload). False is what a build from before this field meant:
    /// it had no way to start a run that outlived its own answer.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decode(String.self, forKey: .name)
        interface = try box.decode(String.self, forKey: .interface)
        since = try box.decodeIfPresent(Date.self, forKey: .since)
        bytesIn = try box.decodeIfPresent(UInt64.self, forKey: .bytesIn)
        bytesOut = try box.decodeIfPresent(UInt64.self, forKey: .bytesOut)
        exit = try box.decode(VPNExitVerdict.self, forKey: .exit)
        speed = try box.decodeIfPresent(VPNSpeedReading.self, forKey: .speed)
        measuring = try box.decodeIfPresent(Bool.self, forKey: .measuring) ?? false
        // The same repair as the field above, for the same reason: a payload
        // written before this field existed has no key for it, and Swift's
        // synthesised `Decodable` wants one regardless — `JSONDecoder` then
        // gives up on the whole document rather than on the field, which here is
        // every tile the hero draws. `.none` is what a build from before this
        // meant: it had no way to know what a tunnel excluded.
        excluded = try box.decodeIfPresent(VPNExcludedRoutes.Summary.self,
                                           forKey: .excluded) ?? .none
    }
}

extension VPNTunnelState {
    /// One tunnel's reading, assembled from what the engine remembers about it.
    ///
    /// **Here rather than at the engine's call site**, which is where it was: it
    /// is the construction of a wire value out of seven remembered facts, and
    /// putting it beside the value keeps `VPNEngine.tunnelStates` to the two
    /// questions that are actually the engine's — which tunnels, and in what
    /// order. The counters reach the wire as whole kilobytes for the reason
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
