// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What `scutil --nc status "<name>"` says about the tunnel a connection has
/// raised: which interface it is on, and whether the machine's traffic leaves
/// through it.
///
/// **Asked of the tool, by name, because the store cannot be asked by id.**
/// `State:/Network/Service/<id>/IPv4` wants the identifier of a *network
/// service*, and `scutil --nc list` answers with the identifier of a
/// *configuration* — the same string only for classic PPP/IPSec. Measured on a
/// live NetworkExtension tunnel, 2026-08-18: the list named
/// `02196763-19A0-40A0-B369-D9EA68F7F65D`, the routing entry was under
/// `B8689BB0-071F-4E35-906E-FBC1F66D195C`, and the lookup answered nil for
/// every tunnel this app can raise. The module already speaks `scutil` through
/// `VPNRunnerPort`, and the tool answers by the same name `--nc start` takes.
enum VPNStatusParser {

    /// What one status read found. Only ever built with an interface: a
    /// connection that is down, or one whose tunnel has not come up yet, names
    /// none — and `nil` is that state rather than an empty string.
    struct Reading: Equatable, Sendable {
        let interface: String
        /// `IsPrimaryInterface` as the tool answers it, or nil when it did not.
        /// The routing verdict prefers the dynamic store's global entry — that
        /// is the routing table's own answer — and falls back to this, which is
        /// the same question asked of the connection (`VPNExitVerdict.of`).
        let isPrimaryInterface: Bool?
        /// **When the tunnel last changed state, as the tool says it.**
        ///
        /// `VPNEngine.stampWhatCameUp` carried the sentence «`scutil` cannot
        /// answer «since when»» for several releases, and it is not true: every
        /// status read this parser is handed ends with
        /// `LastStatusChangeTime : 08/19/2026 14:57:22`, and that line was
        /// already sitting in this parser's own fixture, being walked past. The
        /// cost of the mistake was a hole in the first column of the page on the
        /// most ordinary Mac there is — a VPN raised at login, the menu bar app
        /// started after it — because Helm's own observation was the only source
        /// and it had not been watching.
        ///
        /// Nil when the line is absent or does not parse, and the engine falls
        /// back to what it saw itself. So this can only ever add a duration.
        let since: Date?
        /// What the configuration carries around the tunnel rather than through
        /// it — the lines this parser calls decoys, kept instead of only
        /// stepped over (`VPNExcludedRoutes`).
        let excludedRoutes: [VPNExcludedRoutes.Route]

        init(interface: String, isPrimaryInterface: Bool?,
                    since: Date? = nil,
                    excludedRoutes: [VPNExcludedRoutes.Route] = []) {
            self.interface = interface
            self.isPrimaryInterface = isPrimaryInterface
            self.since = since
            self.excludedRoutes = excludedRoutes
        }
    }

    /// **`en_US_POSIX`, and the format written out.**
    ///
    /// `scutil` writes `MM/dd/yyyy HH:mm:ss` — measured on a Mac whose
    /// languages are `("ru-RU", "en-US")`, so the tool is not writing the
    /// reader's format and a formatter built on the user's locale would fail to
    /// read it. A fixed formatter that answers nil is the safe direction: the
    /// engine's own observation is still there behind it.
    ///
    /// Local time, because the stamp is: the value above matched this app's own
    /// log line for the same event to three seconds.
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        return formatter
    }()

    /// **The tunnel's own `InterfaceName` is the one inside the `IPv4`
    /// dictionary, and nothing else is an answer.**
    ///
    /// A connected tunnel's Extended Status carries the excluded routes it was
    /// configured with, each a dictionary naming the interface the traffic
    /// leaves *around* the tunnel by — seven `InterfaceName : en0` lines on the
    /// machine this was measured on, all of them before the tunnel's own. A
    /// parser taking the first match answers `en0`, the verdict then compares
    /// `en0` against a primary interface of `utun8` and the page says «traffic
    /// is not going through the tunnel» on a Mac where it is: a false alarm in
    /// the one sentence this feature exists to get right.
    ///
    /// This was «the shallowest `InterfaceName` seen» for one release, which is
    /// the same rule only while the tunnel's own line is present. `scutil`
    /// prints a dictionary's keys in order — `Addresses`, `ExcludedRoutes`,
    /// `InterfaceName`, `Router`, `ServerAddress` — so the decoys come *before*
    /// the line that overrules them, and any output stopping between the two
    /// leaves a decoy as the shallowest candidate there is: a tunnel a moment
    /// past `Connected`, or a read cut short inside `ExcludedRoutes`. The
    /// caller then caches that reading for the life of the tunnel
    /// (`VPNEngine.readInterfaces`), so one transient read draws `en0`'s
    /// since-boot counters under a green tick. Nil is the answer, and the
    /// caller is already written for it.
    ///
    /// So the anchor is the `IPv4` dictionary's own indent: the tunnel's line
    /// is its direct child, the decoys sit two levels deeper inside
    /// `ExcludedRoutes` — and `scutil` indents two spaces per level, always.
    static func reading(in output: String) -> Reading? {
        /// The indent of the `IPv4 : <dictionary> {` line, once it has been
        /// seen. Its direct children are two spaces further in.
        var ipv4Indent: Int?
        var tunnelInterface: String?
        var isPrimary: Bool?
        var since: Date?
        // One exclusion is three lines — destination, interface, mask — and the
        // pair is completed by the mask, which is the last of the three. A
        // destination with no mask after it is a dictionary the tool cut short,
        // and it is dropped rather than half-read.
        var pendingDestination: String?
        var excluded: [VPNExcludedRoutes.Route] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix { $0 == " " }.count
            let text = line.trimmingCharacters(in: .whitespaces)
            if ipv4Indent == nil, let opened = value(of: "IPv4", in: text), opened.hasSuffix("{") {
                ipv4Indent = indent
            }
            if let value = value(of: "InterfaceName", in: text), !value.isEmpty,
               tunnelInterface == nil, let ipv4Indent, indent == ipv4Indent + 2 {
                tunnelInterface = value
            }
            if let flag = value(of: "IsPrimaryInterface", in: text) {
                isPrimary = flag == "1"
            }
            if let written = value(of: "LastStatusChangeTime", in: text) {
                since = stamp.date(from: written)
            }
            if let destination = value(of: "DestinationAddress", in: text) {
                pendingDestination = destination
            }
            if let mask = value(of: "SubnetMask", in: text), let destination = pendingDestination {
                excluded.append(VPNExcludedRoutes.Route(destination: destination, mask: mask))
                pendingDestination = nil
            }
        }
        guard let tunnelInterface else { return nil }
        return Reading(interface: tunnelInterface, isPrimaryInterface: isPrimary,
                       since: since, excludedRoutes: excluded)
    }

    /// The value of a `Field : value` line, or nil when this is not that field.
    /// `scutil` writes the separator with spaces around it and `KeychainCredentials`
    /// reads its own fields the same way; this is the one that has to be sure it
    /// matched the whole key, since `InterfaceName` is a prefix of nothing here
    /// but a looser match is how the next field with a common stem gets read.
    private static func value(of field: String, in text: String) -> String? {
        guard text.hasPrefix(field) else { return nil }
        let rest = text.dropFirst(field.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix(":") else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
