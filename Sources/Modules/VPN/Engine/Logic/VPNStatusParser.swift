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
public enum VPNStatusParser {

    /// What one status read found. Only ever built with an interface: a
    /// connection that is down, or one whose tunnel has not come up yet, names
    /// none — and `nil` is that state rather than an empty string.
    public struct Reading: Equatable, Sendable {
        public let interface: String
        /// `IsPrimaryInterface` as the tool answers it, or nil when it did not.
        /// The routing verdict prefers the dynamic store's global entry — that
        /// is the routing table's own answer — and falls back to this, which is
        /// the same question asked of the connection (`VPNExitVerdict.of`).
        public let isPrimaryInterface: Bool?

        public init(interface: String, isPrimaryInterface: Bool?) {
            self.interface = interface
            self.isPrimaryInterface = isPrimaryInterface
        }
    }

    /// **The outermost `InterfaceName` wins, and that is the whole trick.**
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
    /// The tunnel's own line sits in the `IPv4` dictionary itself, the decoys
    /// two levels deeper inside its `ExcludedRoutes`, so indentation is what
    /// separates them — and `scutil` indents two spaces per level, always.
    public static func reading(in output: String) -> Reading? {
        var shallowest: (indent: Int, value: String)?
        var isPrimary: Bool?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix { $0 == " " }.count
            let text = line.trimmingCharacters(in: .whitespaces)
            if let value = value(of: "InterfaceName", in: text), !value.isEmpty,
               indent < (shallowest?.indent ?? .max) {
                shallowest = (indent, value)
            }
            if let flag = value(of: "IsPrimaryInterface", in: text) {
                isPrimary = flag == "1"
            }
        }
        guard let shallowest else { return nil }
        return Reading(interface: shallowest.value, isPrimaryInterface: isPrimary)
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
