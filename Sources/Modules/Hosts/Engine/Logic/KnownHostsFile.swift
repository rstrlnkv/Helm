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
        /// The line exactly as it was written.
        ///
        /// Held on the value rather than rebuilt from the fields, because
        /// rendering must be the file's own bytes: a line here carries somebody
        /// else's public key and this app has no business re-spelling it.
        public let raw: String

        public var id: Int { index }

        public init(index: Int, marker: String, hosts: [String], isHashed: Bool,
                    keyType: String, key: String, comment: String, raw: String) {
            self.index = index
            self.marker = marker
            self.hosts = hosts
            self.isHashed = isHashed
            self.keyType = keyType
            self.key = key
            self.comment = comment
            self.raw = raw
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

        var raw: String {
            switch self {
            case .verbatim(let text): return text
            case .entry(let entry): return entry.raw
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
        // `omittingEmptySubsequences: false` keeps a blank line as a line, and
        // the trailing empty piece after a final newline keeps the file's own
        // ending — both are bytes this type promises to give back.
        let raws = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines: [Line] = []
        for (index, raw) in raws.enumerated() {
            lines.append(entry(from: raw, at: index).map(Line.entry) ?? .verbatim(raw))
        }
        return Document(lines: lines)
    }

    public static func render(_ document: Document) -> String {
        document.lines.map(\.raw).joined(separator: "\n")
    }

    /// The document without that line. The only edit this file has.
    public static func forget(_ index: Int, in document: Document) -> Document {
        Document(lines: document.lines.filter {
            if case .entry(let entry) = $0 { return entry.index != index }
            return true
        })
    }

    private static func entry(from raw: String, at index: Int) -> Entry? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        var fields = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
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
                     raw: raw)
    }
}
