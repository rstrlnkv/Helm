// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What each configuration was told about how loudly to speak — and nothing
/// about the ones nobody has told.
///
/// **Absence means inherit.** The three settings this sits over — the rules'
/// notice, a drop's notice, the ring — are single values an installed build
/// already holds, and every card reads them until somebody changes that card.
/// Moving them into per-connection records would take a one-time migration
/// keyed to whichever configuration happened to be first, and this repository
/// has paid for one-time writes before: they run twice, or never, and the
/// evidence arrives weeks later. There is nothing to migrate here, so nothing
/// can go wrong in the migration.
///
/// **Keyed by the configuration's id, never its name.** The module learned this
/// the expensive way on the rules: a name is what somebody types in System
/// Settings and can retype, and `VPNRules.orphaned` exists because of it.
/// `scutil --nc list` gives each service a UUID, `VPNConnection.id` carries it,
/// and a rename costs nothing here.
///
/// **Nothing prunes it.** `scutil` can answer with a short list or none at all —
/// a refusal, a Mac mid-boot — and dropping every entry that did not match the
/// current answer would throw away a person's choices on the strength of one bad
/// read. `EachTunnelKeepsItsOwnVoiceTests` holds that.
public struct VPNNoticeBook: Equatable, Codable {

    /// One configuration's overrides. Every field is optional, and `nil` is the
    /// whole mechanism: it means «this one was never set, use what the app
    /// says».
    public struct Entry: Equatable, Codable {
        public var notice: VPNNotice?
        public var drop: VPNNotice?
        public var spin: Bool?
        /// The colour the ring turns for a tunnel going **up**, and for one
        /// going down. Two fields for three kinds, the same arithmetic
        /// `VPNSettings.spinTint` does with its two keys: the ring says which
        /// way the tunnel went, and there are two ways.
        public var tintUp: String?
        public var tintDown: String?

        /// **Every field optional is the mechanism, and it is also what lets an
        /// older document decode.** Swift synthesises `decodeIfPresent` for an
        /// optional property, so a book written before these two fields existed
        /// reads back with them `nil` — which means inherit. A non-optional
        /// field with a default would have thrown instead, and `JSONDecoder`
        /// gives up on the whole document rather than the one key (CLAUDE.md).
        var isEmpty: Bool {
            notice == nil && drop == nil && spin == nil
                && tintUp == nil && tintDown == nil
        }
    }

    private var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    /// For the tests, and for a screen that wants to say «3 of your
    /// configurations speak differently».
    public var entryCount: Int { entries.count }

    // MARK: - Reading

    /// How loudly this configuration announces a firing of `kind`.
    ///
    /// The kind→setting question stays `VPNNotice.mode`'s, so a teardown Helm
    /// performed and a tunnel that fell over cannot come to mean different
    /// things here than they do everywhere else.
    public func notice(for id: String, kind: VPNAutomation.Kind,
                       rules: VPNNotice, drop: VPNNotice) -> VPNNotice {
        let entry = entries[id]
        return VPNNotice.mode(for: kind,
                              rules: entry?.notice ?? rules,
                              drop: entry?.drop ?? drop)
    }

    /// What the page draws in the two picture questions: the override if there
    /// is one, otherwise what is inherited.
    public func shown(for id: String, rules: VPNNotice, drop: VPNNotice)
        -> (rules: VPNNotice, drop: VPNNotice) {
        (entries[id]?.notice ?? rules, entries[id]?.drop ?? drop)
    }

    public func spin(for id: String, fallback: Bool) -> Bool {
        entries[id]?.spin ?? fallback
    }

    /// What colour this configuration turns the ring for a firing of `kind`.
    ///
    /// The kind→field question is `VPNAutomation.Kind.goingUp`'s, so a tunnel
    /// that fell over and one Helm took down cannot come to mean different
    /// colours here than they do in the store.
    public func tint(for id: String, kind: VPNAutomation.Kind, fallback: String) -> String {
        let entry = entries[id]
        return (kind.goingUp ? entry?.tintUp : entry?.tintDown) ?? fallback
    }

    // MARK: - Writing

    /// Sets one field and leaves the rest inherited. Immutable, so a caller
    /// cannot half-apply a change.
    public func setting(_ id: String,
                        notice: VPNNotice? = nil,
                        drop: VPNNotice? = nil,
                        spin: Bool? = nil,
                        tintUp: String? = nil,
                        tintDown: String? = nil) -> VPNNoticeBook {
        var copy = self
        var entry = copy.entries[id] ?? Entry()
        if let notice { entry.notice = notice }
        if let drop { entry.drop = drop }
        if let spin { entry.spin = spin }
        if let tintUp { entry.tintUp = tintUp }
        if let tintDown { entry.tintDown = tintDown }
        copy.entries[id] = entry
        return copy
    }

    /// One call for the colour, so no caller has to know which of the two
    /// fields a kind writes.
    public func setting(_ id: String, tint token: String,
                        for kind: VPNAutomation.Kind) -> VPNNoticeBook {
        kind.goingUp ? setting(id, tintUp: token) : setting(id, tintDown: token)
    }

    /// Back to inheriting. Removes the record rather than storing agreement with
    /// today's default — a book that grows an entry per glance pins that default
    /// for ever.
    public func clearing(_ id: String) -> VPNNoticeBook {
        var copy = self
        copy.entries[id] = nil
        return copy
    }

    // MARK: - The store

    public static func encode(_ book: VPNNoticeBook) -> String {
        guard let data = try? JSONEncoder().encode(book.entries.filter { !$0.value.isEmpty }),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// Anything that is not a book reads as an empty one, which **inherits**.
    /// The dangerous failure would be reading rubbish as silence: a person whose
    /// store was hand-edited would stop being told their tunnel fell over.
    public static func decode(_ text: String) -> VPNNoticeBook {
        guard let data = text.data(using: .utf8),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return VPNNoticeBook() }
        return VPNNoticeBook(entries: entries.filter { !$0.value.isEmpty })
    }
}
