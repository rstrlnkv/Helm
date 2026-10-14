import Foundation

/// What the page is told about the world.
///
/// **`init(from:)` is written by hand on purpose.** A stored default does *not*,
/// by itself, make an older payload decode: Swift's synthesised `Decodable`
/// requires the coding key regardless of a property's initial value, and
/// `JSONDecoder` abandons the whole document rather than filling in the one
/// field — leaving every screen holding stale defaults.
/// `KeepAwakeEngine.StatePayload` carried three comments claiming otherwise and
/// none of them was true. `HostsStateDecodingTests` is what keeps this one.
///
/// **`sshText` and `sshReadable` are required, and `{}` throws.** A payload
/// that names neither is not evidence about anybody's config: decoding it into
/// an empty, writable config would draw a page that offers to overwrite a file
/// nobody read.
public struct HostsState: Codable, Sendable, Equatable {
    /// `~/.ssh/config` as it is on disk right now.
    public var sshText: String
    /// False when that file could not be read at all — missing, or not UTF-8.
    /// Distinct from an empty config: an empty one is something a person may
    /// mean to write, and «not there» and «not UTF-8» are not.
    public var sshReadable: Bool
    /// Whether Helm may write it (`SSHFileScope`). A page that offers Apply on a
    /// file it will refuse to write is a page that lies at the last moment.
    public var sshWritable: Bool

    /// The keys in `~/.ssh`, one row each, sorted by name.
    public var keys: [KeyRow]
    /// False when `~/.ssh` could not be read at all — missing, or a directory
    /// this process may not search. **Not the same as no keys**: a Mac with
    /// none yet is an ordinary Mac and its page says «no keys», where a
    /// directory nobody could open has to say something else or the page reads
    /// as a claim it cannot support.
    public var keysReadable: Bool
    /// `~/.ssh`'s own mode, judged. Its own field rather than folded into the
    /// rows: it is one fact about the directory and the fix for it is a
    /// different `chmod` from any key's.
    public var directoryPermission: KeyRow.Permission
    /// What the agent said, in its three states.
    public var agent: AgentList
    /// `~/.ssh/known_hosts` as it is on disk right now.
    public var knownHostsText: String
    /// False when it could not be read at all. A Mac that has never connected
    /// anywhere simply has no such file, and the page says that rather than
    /// drawing an empty table over a file it could not open.
    public var knownHostsReadable: Bool
    /// Whether Helm may write it (`SSHFileScope`), asked of the same gate the
    /// config goes through.
    public var knownHostsWritable: Bool
    /// The home directory the engine read all of this under.
    ///
    /// **It travels rather than being asked again on the other side.**
    /// `IdentityFile ~/.ssh/k`, `%d/.ssh/k` and `/Users/someone/.ssh/k` are one
    /// key, and resolving them needs a home — so a page that asked its own
    /// process for one would be joining the keys the engine listed against a
    /// path nobody read them from. It is also what lets a test own a home
    /// instead of the machine's.
    public var home: String

    public init(sshText: String = "", sshReadable: Bool = true, sshWritable: Bool = true,
                keys: [KeyRow] = [], keysReadable: Bool = true,
                directoryPermission: KeyRow.Permission = .unknown,
                agent: AgentList = .unreachable,
                knownHostsText: String = "", knownHostsReadable: Bool = true,
                knownHostsWritable: Bool = true, home: String = "") {
        self.sshText = sshText
        self.sshReadable = sshReadable
        self.sshWritable = sshWritable
        self.keys = keys
        self.keysReadable = keysReadable
        self.directoryPermission = directoryPermission
        self.agent = agent
        self.knownHostsText = knownHostsText
        self.knownHostsReadable = knownHostsReadable
        self.knownHostsWritable = knownHostsWritable
        self.home = home
    }

    /// The config's text and whether it could be read are read outright; every
    /// other field takes `decodeIfPresent`. A missing `sshText` is a failure
    /// rather than an empty config, because an empty config is a claim about
    /// somebody's machine and a truncated payload is not evidence for it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sshText = try container.decode(String.self, forKey: .sshText)
        sshReadable = try container.decode(Bool.self, forKey: .sshReadable)
        // Everything below is read with `decodeIfPresent`: a payload without
        // one of these fields still decodes, and the page keeps the config
        // rather than losing it over a key about something else.
        sshWritable = try container.decodeIfPresent(Bool.self, forKey: .sshWritable) ?? true
        // The defaults are the cautious ones: no keys and an unreachable agent draw
        // a page that promises nothing, where `keysReadable: true` over an
        // empty list would say «this Mac has no keys» on the strength of a
        // payload that never mentioned them.
        keys = try container.decodeIfPresent([KeyRow].self, forKey: .keys) ?? []
        keysReadable = try container.decodeIfPresent(Bool.self, forKey: .keysReadable) ?? false
        directoryPermission = try container.decodeIfPresent(KeyRow.Permission.self,
                                                            forKey: .directoryPermission) ?? .unknown
        agent = try container.decodeIfPresent(AgentList.self, forKey: .agent) ?? .unreachable
        knownHostsText = try container.decodeIfPresent(String.self, forKey: .knownHostsText) ?? ""
        knownHostsReadable = try container.decodeIfPresent(Bool.self,
                                                           forKey: .knownHostsReadable) ?? false
        knownHostsWritable = try container.decodeIfPresent(Bool.self,
                                                           forKey: .knownHostsWritable) ?? false
        // Empty rather than this process's own home: a payload that never carried one
        // is not evidence about anybody's directory, and an empty home resolves
        // no `~` — which draws a key as «not used here» rather than joining it
        // against a path the engine never read.
        home = try container.decodeIfPresent(String.self, forKey: .home) ?? ""
    }
}
