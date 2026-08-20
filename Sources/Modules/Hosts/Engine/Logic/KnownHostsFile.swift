import CryptoKit
import Foundation

/// `~/.ssh/known_hosts`: the hosts this Mac has already trusted.
///
/// **This file is read and pruned, never rewritten.** The one job people come
/// to it for is forgetting a host whose key changed — `ssh` refuses to connect
/// and prints a wall of text about a possible attack, with `ssh-keygen -R` at
/// the bottom that nobody remembers. So the document keeps every line exactly
/// as it was written and `render` returns those bytes; the only edit is
/// dropping a line whole. That makes `render(parse(x)) == x` true by
/// construction rather than by a round-trip test's mercy — and it is the honest
/// design, because a line here carries a public key this app has no business
/// re-spelling.
///
/// **A hashed file is an ordinary file, not an error.** With
/// `HashKnownHosts yes` — which macOS ships on — a line names `|1|salt|hash`
/// instead of a host, and no amount of parsing recovers the name. The row says
/// so and its button still works: forgetting is by line, and a line is
/// something this file can always identify.
public enum KnownHostsFile {

    /// One trusted host, as its line says it.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// Position in the document. The identity, because two lines can carry
        /// the same host and a different key.
        public let index: Int
        /// `@cert-authority` or `@revoked`, or empty. Kept because a row that
        /// dropped it would offer to forget a revocation as though it were a
        /// trust.
        public let marker: String
        /// The host patterns, comma-separated in the file. Empty when the line
        /// is hashed — and that is a fact about the file, not a parse failure.
        public let hosts: [String]
        public let isHashed: Bool
        public let keyType: String
        /// The key itself, base64 as written. Public by definition.
        public let key: String
        public let comment: String
        /// The line exactly as it was written, **without its ending.**
        ///
        /// Held on the value rather than rebuilt from the fields, because
        /// rendering must be the file's own bytes: a line here carries somebody
        /// else's public key and this app has no business re-spelling it.
        ///
        /// The ending sits beside it rather than inside it because this is the
        /// value `forget(line:)` matches on, and it travels to the engine
        /// through a command: a line named by a page that read a CRLF file
        /// would otherwise have to carry the `\r` back for the match to hold.
        public let raw: String
        /// The ending this line had — `"\n"`, `"\r\n"`, `"\r"`, or `""` for a
        /// last line that ended without one.
        ///
        /// Kept per line, not per file: a file with mixed endings keeps each
        /// line's own, and a file Helm only read comes back byte for byte
        /// whichever machine wrote it.
        public let ending: String

        public var id: Int { index }

        public init(index: Int, marker: String, hosts: [String], isHashed: Bool,
                    keyType: String, key: String, comment: String,
                    raw: String, ending: String) {
            self.index = index
            self.marker = marker
            self.hosts = hosts
            self.isHashed = isHashed
            self.keyType = keyType
            self.key = key
            self.comment = comment
            self.raw = raw
            self.ending = ending
        }

        /// The SHA-256 fingerprint `ssh` prints, or nil for a key whose base64
        /// this build cannot decode.
        ///
        /// Nil rather than an empty string: a fingerprint column that is blank
        /// because the line is unreadable and one that is blank because there
        /// is no key are different facts, and only one of them is worth a
        /// person's attention.
        public var fingerprint: String? {
            guard let data = Data(base64Encoded: key), !data.isEmpty else { return nil }
            let digest = SHA256.hash(data: data)
            let encoded = Data(digest).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            return "SHA256:" + encoded
        }
    }

    /// A line is either an entry or bytes this type does not model.
    ///
    /// Comments, blank lines and anything that does not parse are `verbatim`
    /// and come back untouched. There is no third case for «malformed»: a line
    /// this build cannot read is a line somebody else wrote, and the answer is
    /// to leave it alone.
    public enum Line: Equatable, Sendable {
        case entry(Entry)
        case verbatim(String)

        /// The bytes this line puts back into the file, ending included —
        /// which for an entry is `raw` and the ending held beside it.
        var rendered: String {
            switch self {
            case .verbatim(let text): return text
            case .entry(let entry): return entry.raw + entry.ending
            }
        }
    }

    public struct Document: Equatable, Sendable {
        public var lines: [Line]
        public var entries: [Entry] {
            lines.compactMap { if case .entry(let e) = $0 { return e } else { return nil } }
        }
        public init(lines: [Line]) { self.lines = lines }
    }

    public static func parse(_ text: String) -> Document {
        // Split by the ending each line actually had, never by `"\n"` alone:
        // Swift makes `"\r\n"` one `Character`, so a file written on another
        // machine has no `"\n"` to split on and comes back as a single line —
        // every trust in it one row, and forgetting that row an empty file.
        var lines: [Line] = []
        for (index, raw) in LineEndings.split(text).enumerated() {
            lines.append(entry(from: raw.body, at: index, ending: raw.ending).map(Line.entry)
                         ?? .verbatim(raw.body + raw.ending))
        }
        return Document(lines: lines)
    }

    public static func render(_ document: Document) -> String {
        document.lines.map(\.rendered).joined()
    }

    /// The document without the line that reads exactly this. The only edit
    /// this file has.
    ///
    /// **By the line's own bytes, never by its position.** A position is a fact
    /// about the reading it came from, and this is the one file in the module
    /// that grows under the app: `ssh` appends to it from any terminal the
    /// moment somebody trusts a new machine, so the index a page took minutes
    /// ago names a different line by the time Forget is pressed. The bytes name
    /// the same trust in any reading of the file — and `ssh` only ever appends,
    /// so a line that was there is there unchanged or is gone.
    ///
    /// Every copy goes, because two identical lines are one trust written
    /// twice, and leaving the second would make Forget look inert.
    public static func forget(line raw: String, in document: Document) -> Document {
        Document(lines: document.lines.filter {
            if case .entry(let entry) = $0 { return entry.raw != raw }
            return true
        })
    }

    private static func entry(from raw: String, at index: Int, ending: String) -> Entry? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        // Space **or tab**: `ssh` walks a field to the first of either, so a
        // tab-separated line is an ordinary trust it honours. Read on spaces
        // alone it came back as one field, failed the guard below and drew no
        // row — a trust nobody could see, and so nobody could forget.
        var fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var marker = ""
        if let first = fields.first, first.hasPrefix("@") {
            marker = first
            fields.removeFirst()
        }
        // Host, key type, key: three fields at minimum. Fewer is a line this
        // type does not model, and an unmodelled line is left alone.
        guard fields.count >= 3 else { return nil }
        let hostField = fields[0]
        let hashed = hostField.hasPrefix("|")
        return Entry(index: index,
                     marker: marker,
                     hosts: hashed ? [] : hostField.split(separator: ",").map(String.init),
                     isHashed: hashed,
                     keyType: fields[1],
                     key: fields[2],
                     comment: fields.dropFirst(3).joined(separator: " "),
                     raw: raw,
                     ending: ending)
    }
}
