// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Pure parsing of `scutil --nc list` / `scutil --nc status` output and the
/// "which VPN does a one-click toggle act on" resolution.
enum VPNListParser {
    static func parseStatus(_ token: String) -> VPNStatus {
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
    static func isReadable(_ output: String) -> Bool {
        if output.contains(listHeader) { return true }
        return !parseList(output).isEmpty
    }

    static func parseList(_ output: String) -> [VPNConnection] {
        var result: [VPNConnection] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let statusToken = between(line, "(", ")"),
                  let quoted = quotedName(line),
                  // An empty quoted name parses fine and then becomes a row with
                  // no label, whose id falls back to that same empty string —
                  // a toggle that acts on nothing, or on the wrong connection.
                  // A name of nothing but spaces is the same row with the same
                  // button, one character away from the guard written for it:
                  // `--nc start "   "` can only fail, and the card's label is
                  // blank either way. The name itself is never trimmed — it is
                  // the command, and a configuration whose name really does end
                  // in a space has to be spelled the way it was stored.
                  !quoted.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            // Falling back to the name makes two rows one `Identifiable` id
            // whenever macOS has two configurations of one name, which it
            // allows — undefined in a `ForEach`, and this engine now keys its
            // memory of what it raised by id. The row's own place in the list
            // is the only other thing a line without a service id carries.
            let id = uuidLike(in: line) ?? "\(quoted.name)#\(result.count)"
            // The kind comes from after the name, not from anywhere on the line:
            // `scutil` writes the protocol in brackets *following* the quoted
            // name, and searching the whole line found a connection called
            // `Office [old]` first — so the row reported its protocol as "old".
            // Where the name ends is `quotedName`'s answer rather than a second
            // search for the same closing quote, so the two cannot disagree.
            let kind = between(quoted.after, "[", "]") ?? kindBeforeQuote(line)
            result.append(VPNConnection(id: id, name: quoted.name,
                                        status: parseStatus(statusToken), kind: kind))
        }
        return result
    }

    /// The VPN a one-click toggle acts on: the sole configured one, else the
    /// last-used (if still present), else the first.
    static func defaultConnection(from connections: [VPNConnection],
                                  lastUsedName: String?) -> VPNConnection? {
        if connections.count == 1 { return connections.first }
        if let lastUsedName, let match = connections.first(where: { $0.name == lastUsedName }) {
            return match
        }
        return connections.first
    }

    /// The whole quoted run — first quote to **last** — rather than the first
    /// quoted pair, and what is left of the line after it.
    ///
    /// The Service Name field in Network Settings is free text and takes a
    /// quotation mark, and `between(line, "\"", "\"")` stopped at the first
    /// closing one: «Office "B"» came back as «Office ». Every command this
    /// module sends is spelled with that string, so the button on that card
    /// could only ever be answered `No service` — and the neighbouring
    /// «Office "A"» came back as «Office » too, which is two cards under one
    /// name, one tag in the rule picker, and one key in both of the engine's
    /// books.
    ///
    /// The remainder comes back with it because the protocol is read from there:
    /// one answer to «where does the name end», rather than the same `.backwards`
    /// search written twice with nothing keeping the two in step.
    private static func quotedName(_ line: String) -> (name: String, after: String)? {
        guard let first = line.firstIndex(of: "\""),
              let last = line.range(of: "\"", options: .backwards)?.lowerBound,
              first < last else { return nil }
        return (String(line[line.index(after: first)..<last]),
                String(line[line.index(after: last)...]))
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
