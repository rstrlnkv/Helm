// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Pure parsing of `scutil --nc list` / `scutil --nc status` output and the
/// "which VPN does a one-click toggle act on" resolution.
public enum VPNListParser {
    public static func parseStatus(_ token: String) -> VPNStatus {
        switch token.trimmingCharacters(in: .whitespaces).lowercased() {
        case "connected": return .connected
        case "connecting": return .connecting
        case "disconnecting": return .disconnecting
        case "disconnected": return .disconnected
        default: return .unknown
        }
    }

    /// Parse the multi-line `scutil --nc list` output. Lines that don't match the
    /// expected shape (status in parens + a quoted name) are skipped.
    /// The header `scutil --nc list` prints before it enumerates anything. It is
    /// there on a machine with no VPN configured at all, which is what makes it
    /// a usable sign of "the tool spoke".
    private static let listHeader = "Available network connection services"

    /// Whether this output is an answer at all.
    ///
    /// `ScutilRunner` hands back the tool's stdout and drops its exit status, so
    /// a read that failed arrives here as an empty string — and an empty string
    /// parses, perfectly happily, into "this Mac has no VPNs". The two are not
    /// the same fact and the caller must not confuse them: the page told a user
    /// their connections were gone while both were up, and the drop detection,
    /// which asks what is no longer in this list, concluded that everything Helm
    /// had raised had fallen over at once.
    ///
    /// An answer carries the header, or at least one row we could read. Anything
    /// else — silence, or a complaint from the tool — is not an answer.
    public static func isReadable(_ output: String) -> Bool {
        if output.contains(listHeader) { return true }
        return !parseList(output).isEmpty
    }

    public static func parseList(_ output: String) -> [VPNConnection] {
        var result: [VPNConnection] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let statusToken = between(line, "(", ")"),
                  let name = between(line, "\"", "\""),
                  // An empty quoted name parses fine and then becomes a row with
                  // no label, whose id falls back to that same empty string —
                  // a toggle that acts on nothing, or on the wrong connection.
                  !name.isEmpty else { continue }
            let id = uuidLike(in: line) ?? name
            // After the name, not anywhere on the line. `scutil` writes the
            // protocol in brackets *following* the quoted name, and searching
            // the whole line found a connection called `Office [old]` first —
            // so the row reported its protocol as "old".
            let afterName = line.range(of: "\"", options: .backwards)
                .map { String(line[$0.upperBound...]) } ?? line
            let kind = between(afterName, "[", "]") ?? kindBeforeQuote(line)
            result.append(VPNConnection(id: id, name: name,
                                        status: parseStatus(statusToken), kind: kind))
        }
        return result
    }

    /// The VPN a one-click toggle acts on: the sole configured one, else the
    /// last-used (if still present), else the first.
    public static func defaultConnection(from connections: [VPNConnection],
                                  lastUsedName: String?) -> VPNConnection? {
        if connections.count == 1 { return connections.first }
        if let lastUsedName, let match = connections.first(where: { $0.name == lastUsedName }) {
            return match
        }
        return connections.first
    }

    private static func between(_ s: String, _ open: Character, _ close: Character) -> String? {
        guard let a = s.firstIndex(of: open) else { return nil }
        let afterA = s.index(after: a)
        guard afterA < s.endIndex, let b = s[afterA...].firstIndex(of: close) else { return nil }
        return String(s[afterA..<b])
    }

    /// The first UUID-shaped token on the line, if any.
    private static func uuidLike(in s: String) -> String? {
        for token in s.split(separator: " ") where token.count == 36 && token.contains("-") {
            return String(token)
        }
        return nil
    }

    /// The word right before the quoted name (the "--> IKEv2" token), a fallback
    /// when there is no bracketed kind.
    private static func kindBeforeQuote(_ s: String) -> String? {
        guard let q = s.firstIndex(of: "\"") else { return nil }
        let head = s[..<q].split(separator: " ").map(String.init)
        return head.last
    }
}
