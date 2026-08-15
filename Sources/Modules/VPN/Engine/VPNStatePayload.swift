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

        init(connections: [VPNConnection], autoConnected: [String], defaultName: String?,
             lastAutomation: VPNAutomation?, lastFailure: VPNFailure? = nil,
             secretsBehindAPrompt: [String] = []) {
            self.connections = connections
            self.autoConnected = autoConnected
            self.defaultName = defaultName
            self.lastAutomation = lastAutomation
            self.lastFailure = lastFailure
            self.secretsBehindAPrompt = secretsBehindAPrompt
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
        }
    }
}
