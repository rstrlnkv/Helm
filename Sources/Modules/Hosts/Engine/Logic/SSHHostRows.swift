import Foundation

/// Tab 2, assembled: one row per `Host` block, with the key it uses and the
/// fingerprints already trusted for it.
///
/// **Three files meet here and they meet once.** The config's blocks, the key
/// names in `~/.ssh` and the lines of `known_hosts` are read into one table for
/// the whole tab — never per row, and never per redraw. A row that computed its
/// own share of this join would be the shape `ScanCoordinator.Conditions`
/// exists to stop, where one tick judged three modules against three different
/// readings of the same world.
///
/// The join itself is `KeyUsage`'s and is called, not restated: `IdentityFile`
/// is spelled five ways `ssh` reads identically, and a second implementation of
/// that would drift from the first the day either was touched.
public enum SSHHostRows {

    /// One block, as the tab draws it.
    public struct Row: Equatable, Sendable, Identifiable {
        /// The block's index in the document, which is what an edit names.
        public let index: Int
        /// The patterns as written — `build`, or `gate *.example`. The row's
        /// title, because it is what a person types after `ssh`.
        public let patterns: String
        /// `user@hostname:port`, with each part left out when the block does
        /// not set it, and empty when the block names no machine at all.
        public let address: String
        /// The keys the block names, in the order it names them. **Empty means
        /// «names none», which is ordinary** — never a `missing` standing in
        /// for silence, which is the fold `KeyUsage.Identity` exists to refuse.
        public let identities: [KeyUsage.Identity]
        /// The `known_hosts` lines this block's host name appears in.
        public let trusted: [KnownHostsFile.Entry]

        public var id: Int { index }

        public init(index: Int, patterns: String, address: String,
                    identities: [KeyUsage.Identity], trusted: [KnownHostsFile.Entry]) {
            self.index = index
            self.patterns = patterns
            self.address = address
            self.identities = identities
            self.trusted = trusted
        }
    }

    /// The whole tab: the blocks, and the trusts that belong to no block.
    public struct Table: Equatable, Sendable {
        public let rows: [Row]
        /// Trusted lines matching no block — every hashed line among them,
        /// since a hashed line names nobody. **Kept rather than dropped**: it
        /// is still a trust somebody may want to forget, and forgetting is by
        /// line.
        public let other: [KnownHostsFile.Entry]

        public init(rows: [Row], other: [KnownHostsFile.Entry]) {
            self.rows = rows
            self.other = other
        }
    }

    public static func table(config: SSHConfigFile.Document, keys: [String], home: String,
                             known: KnownHostsFile.Document) -> Table {
        let identities = KeyUsage.ofHosts(config, keys: keys, home: home)
        let entries = known.entries
        var claimed: Set<Int> = []
        let rows = config.hosts.map { host -> Row in
            let fields = config.fields(ofHost: host.index)
            let name = hostName(of: host, fields: fields)
            let trusted = name.map { name in entries.filter { names(of: $0).contains(name) } } ?? []
            claimed.formUnion(trusted.map(\.index))
            return Row(index: host.index,
                       patterns: host.patterns,
                       address: address(name: name, fields: fields),
                       identities: identities[host.index] ?? [],
                       trusted: trusted)
        }
        return Table(rows: rows, other: entries.filter { !claimed.contains($0.index) })
    }

    /// Where the block goes, lower-cased for comparison, or nil when it names
    /// no single machine.
    ///
    /// **`ssh` uses the alias when no `HostName` says otherwise**, so a block
    /// with nothing but a name is a working host and its row must say where it
    /// goes. A *pattern* is not a name, though: `Host *` and `Host web1 web2`
    /// stand for whatever was typed on the command line, and a row that read
    /// one as an address would name a machine that does not exist — the same
    /// mistake `KeyUsage.isEveryHost` avoids one file over.
    static func hostName(of host: SSHConfigFile.Host,
                         fields: [SSHConfigFile.Field]) -> String? {
        if let explicit = fields.last(where: { $0.name == .hostName })?.value {
            return explicit.lowercased()
        }
        let patterns = host.patterns.split(whereSeparator: \.isWhitespace)
        guard patterns.count == 1, let alias = patterns.first,
              !alias.contains(where: { "*?!".contains($0) }) else { return nil }
        return alias.lowercased()
    }

    /// `user@host:port`, with nothing written for a part the block leaves out.
    /// A row that spelled a bare `@` or a trailing `:` would be showing a
    /// setting the file does not carry.
    private static func address(name: String?, fields: [SSHConfigFile.Field]) -> String {
        guard let name else { return "" }
        let user = fields.last { $0.name == .user }?.value
        let port = fields.last { $0.name == .port }?.value
        return (user.map { $0 + "@" } ?? "") + name + (port.map { ":" + $0 } ?? "")
    }

    /// The host names one `known_hosts` line carries, lower-cased and with the
    /// bracket form unwrapped.
    ///
    /// **`[host]:port` is how a non-default port is written**, and a plain
    /// comparison misses every one of them — which reads on screen as «this
    /// host has never been trusted» beside a host that has been trusted for
    /// years. A hashed line names nothing and answers with nothing.
    static func names(of entry: KnownHostsFile.Entry) -> Set<String> {
        Set(entry.hosts.map { host -> String in
            guard host.hasPrefix("["), let close = host.lastIndex(of: "]") else {
                return host.lowercased()
            }
            return String(host[host.index(after: host.startIndex)..<close]).lowercased()
        })
    }
}
