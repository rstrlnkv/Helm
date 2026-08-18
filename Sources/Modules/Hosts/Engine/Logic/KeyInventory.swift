import Foundation

/// What in `~/.ssh` is a key pair, and what is furniture.
///
/// The directory holds four kinds of thing and only one of them is a key: the
/// pairs themselves, the files `ssh` keeps beside them (`config`,
/// `known_hosts`, `authorized_keys`), whatever a person has parked there, and
/// the directories some tools make. A list that counted `known_hosts` as a key
/// would offer to load it into the agent and to `chmod` it; a list that dropped
/// a private key because its `.pub` had been deleted would hide the one file
/// that matters.
///
/// **The private half is never read.** Everything a row shows comes from the
/// `.pub` file, from `stat`, or from `ssh-keygen -l`. This type only decides
/// what the names mean.
public enum KeyInventory {

    /// One pair, as the names say it is.
    public struct Pair: Equatable, Sendable {
        /// The private half's file name — `id_ed25519`. The row is named by it
        /// because that is the name `IdentityFile` uses.
        public let name: String
        /// Whether a `.pub` sits beside it. **A pair with no public half is
        /// still a pair**: `ssh-keygen -y` can regenerate the public half from
        /// the private one, and hiding the row would hide a key somebody has.
        public let hasPublicHalf: Bool

        public init(name: String, hasPublicHalf: Bool) {
            self.name = name
            self.hasPublicHalf = hasPublicHalf
        }
    }

    /// The names `ssh` keeps in that directory that are not keys, whatever they
    /// look like. `environment` and `rc` are in the list because `ssh` reads
    /// them and a person may well have them.
    static let furniture: Set<String> = [
        "config", "known_hosts", "known_hosts2", "known_hosts.old",
        "authorized_keys", "authorized_keys2", "environment", "rc", "agent.sock",
    ]

    /// The pairs among these file names, sorted by name so the table draws in
    /// one order on every read.
    ///
    /// An orphan `.pub` — a public half whose private key is gone — is **not** a
    /// pair: there is nothing to load into an agent and nothing to `chmod`, and
    /// a row for it would offer both.
    public static func pairs(in names: [String]) -> [Pair] {
        let all = Set(names)
        let publics = Set(names.filter { $0.hasSuffix(".pub") })
        let privates = all.subtracting(publics)
            .filter { !furniture.contains($0) }
            // A backup or an editor's leftover is not a key. `.old` and `~`
            // are what the tools in this area actually leave behind.
            .filter { !$0.hasSuffix(".old") && !$0.hasSuffix("~") }
            // A dotfile in `~/.ssh` is configuration, not a key: `ssh` itself
            // writes none, and `.DS_Store` is the one everybody has.
            .filter { !$0.hasPrefix(".") }
        return privates.sorted().map {
            Pair(name: $0, hasPublicHalf: publics.contains($0 + ".pub"))
        }
    }

    /// One `ssh-keygen -l` line: `256 SHA256:abc… comment (ED25519)`.
    ///
    /// Refuses rather than guesses. A line this cannot read is a line whose
    /// fields would otherwise be assigned in the wrong order — a fingerprint in
    /// the comment column is what an over-eager parser produces, and it is
    /// worse than an empty column because a person reads it as fact.
    public static func described(_ line: String) -> Description? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, let bits = Int(parts[0]),
              parts[1].hasPrefix("SHA256:") || parts[1].hasPrefix("MD5:") else { return nil }
        // The type is the last field, in brackets. The comment is everything
        // between the fingerprint and it — comments hold spaces, which is why
        // this is taken as a span rather than as a field.
        guard let last = parts.last, last.hasPrefix("("), last.hasSuffix(")") else { return nil }
        let type = String(last.dropFirst().dropLast())
        let comment = parts.dropFirst(2).dropLast().joined(separator: " ")
        return Description(bits: bits, fingerprint: parts[1], comment: comment, type: type)
    }

    /// What `ssh-keygen -l` says about a key.
    /// `Codable` because it travels in the state: the row on the page is the
    /// row the engine read, rather than a second parse of the same line on the
    /// other side of the wire — a contract with no compiler between its halves
    /// is what cost this app a `force: Bool?` against a `force: Bool`.
    public struct Description: Codable, Equatable, Sendable {
        public let bits: Int
        public let fingerprint: String
        /// May be empty: a key generated with `-C ''` has no comment, and an
        /// empty column is the honest way to draw that.
        public let comment: String
        public let type: String

        public init(bits: Int, fingerprint: String, comment: String, type: String) {
            self.bits = bits
            self.fingerprint = fingerprint
            self.comment = comment
            self.type = type
        }
    }
}
