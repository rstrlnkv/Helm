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
        for line in records(in: output) {
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
                  !quoted.name.trimmingCharacters(in: .whitespaces).isEmpty,
                  // **A name that spans a line break wrote a row of this
                  // format, and no row of this format is a configuration.** The
                  // Service Name field is free text and takes a newline, and
                  // this output is line-oriented: one such name printed two
                  // rows, the second of which said `(Connected)` — the header
                  // badge, the tile's dot and the 1×1 widget all lit for a
                  // tunnel that does not exist, which is the false assurance
                  // `VPNAutomation.Kind.dropped` exists to warn about,
                  // manufactured here. Measured with this parser.
                  //
                  // The row is dropped rather than repaired: `records(in:)`
                  // above has already refused to read the forged half as a
                  // configuration of its own, and what is left is a name this
                  // module cannot draw on one line or put in front of a person
                  // to confirm.
                  !quoted.name.contains(where: \.isNewline) else { continue }
            // Falling back to the name makes two rows one `Identifiable` id
            // whenever macOS has two configurations of one name, which it
            // allows — undefined in a `ForEach`, and this engine keys its memory
            // of what it raised by id.
            //
            // **The tie is broken by how many rows of that name came before, not
            // by how many rows came before.** The row's place in the list was the
            // first thing to hand and it is not a fact about the configuration:
            // `_cameUp` reads an id to tell «this came up and then went» from
            // «this is not up yet», so a list printed in another order changed
            // the identity of a stationary tunnel and the module announced a
            // drop — the one event it interrupts somebody for — for a tunnel
            // that never went. Counting namesakes keeps the ids unique, which is
            // the other half of the question, and leaves them alone when nothing
            // but the order moved.
            let sameName = result.count { $0.name == quoted.name }
            let id = uuidLike(in: line) ?? "\(quoted.name)#\(sameName)"
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
        // **A lookup key, never a command.** The name comes out of an unsealed
        // plist any process running as this user can rewrite, and the bound —
        // that it can only nominate a configuration this Mac already has — is the
        // whole of what stands between a forged value and the tool being handed a
        // name nobody configured. `AForgedLastUsedNameIsBoundedTests` holds it
        // from both ends, and says there why sealing the value is refused.
        if let lastUsedName, let match = connections.first(where: { $0.name == lastUsedName }) {
            return match
        }
        return connections.first
    }

    /// The rows of the output, which is **not** the same as its lines.
    ///
    /// A row's name is printed between two quote delimiters, so a fragment
    /// holding exactly one quote cannot be a row: it is the front half of a name
    /// that carried a line break, and the rest of that name — including anything
    /// shaped like a row of this format — belongs to it. Joining the halves back
    /// together is what lets the name guard in `parseList` see the newline;
    /// splitting on `\n` first destroys the evidence, and a forged row is
    /// byte-identical to a real one, so there is nothing local to it left to
    /// check.
    ///
    /// **Exactly one**, not "an odd number": a name may legitimately carry an
    /// unbalanced quotation mark, which prints three on a perfectly whole row —
    /// `quotedName` reads first-to-last quote precisely so that «Office "B» can
    /// be spelled back to the tool. Counting parity instead swallowed the row
    /// after that one.
    private static func records(in output: String) -> [String] {
        var records: [String] = []
        var pending: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let joined = pending.map { $0 + "\n" + line } ?? String(line)
            if joined.count(where: { $0 == "\"" }) == 1 {
                pending = joined
            } else {
                records.append(joined)
                pending = nil
            }
        }
        // Whatever never closed. Kept rather than dropped so that a name broken
        // by the last line of the output is still a row the guards above judge,
        // instead of a configuration that quietly vanishes for a different
        // reason than the one this module would report.
        if let pending { records.append(pending) }
        return records
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
