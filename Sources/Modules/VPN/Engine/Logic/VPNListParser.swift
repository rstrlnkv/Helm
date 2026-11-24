// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Pure parsing of `scutil --nc list` / `scutil --nc status` output.
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

    /// The header `scutil --nc list` prints before it enumerates anything. It is
    /// there on a machine with no VPN configured at all, which is what makes it
    /// a usable sign of "the tool spoke".
    private static let listHeader = "Available network connection services"

    /// Whether this output is an answer at all.
    ///
    /// Callers hand this only the stdout of the result `ScutilRunner` returns,
    /// so a read that failed arrives here as an empty string — and an empty
    /// string parses into "this Mac has no VPNs". The two are not the same fact:
    /// confused, the page says the connections are gone while they are up, and
    /// the drop detection announces everything Helm raised as fallen at once.
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
                  // **A name that spans a line break is not a configuration.**
                  // The Service Name field is free text and takes a newline,
                  // and this output is line-oriented: such a name can forge a
                  // second row saying `(Connected)` for a tunnel that does not
                  // exist.
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
            // by how many rows came before.** The row's place in the list is not
            // a fact about the configuration: `_cameUp` reads an id to tell «this
            // came up and then went» from «this is not up yet», so an id that
            // moved with the order would announce a drop for a tunnel that never
            // went. Counting namesakes keeps the ids unique and stable.
            let sameName = result.count { $0.name == quoted.name }
            let id = uuidLike(in: line) ?? "\(quoted.name)#\(sameName)"
            // The kind comes from after the name, not from anywhere on the line:
            // `scutil` writes the protocol in brackets *following* the quoted
            // name, and a name such as `Office [old]` carries brackets of its own.
            // Where the name ends is `quotedName`'s answer, so the two cannot disagree.
            let kind = between(quoted.after, "[", "]") ?? kindBeforeQuote(line)
            result.append(VPNConnection(id: id, name: quoted.name,
                                        status: parseStatus(statusToken), kind: kind))
        }
        return result
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
    /// be spelled back to the tool. Counting parity would swallow the next row.
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
    /// quotation mark. Stopping at the first closing one would read «Office "B"»
    /// as «Office », and every command this module sends is spelled with that
    /// string: the card's button could only be answered `No service`, and
    /// «Office "A"» would share its name and its keys.
    ///
    /// The remainder comes back with it because the protocol is read from there:
    /// one answer to «where does the name end».
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
