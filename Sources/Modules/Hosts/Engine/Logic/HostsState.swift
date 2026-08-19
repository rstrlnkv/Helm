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
public struct HostsState: Codable, Sendable, Equatable {
    /// The file as it is on disk right now.
    public var hostsText: String
    /// False when the file could not be read at all, which is not the same as
    /// an empty file — an empty `/etc/hosts` is something a person may mean to
    /// write, and «not there» and «not UTF-8» are not.
    public var hostsReadable: Bool
    /// The copies this module holds, oldest first.
    public var backups: [String]
    /// `~/.ssh/config` as it is on disk right now.
    public var sshText: String
    /// False when that file could not be read at all — missing, or not UTF-8.
    /// Distinct from an empty config for the reason `hostsReadable` is distinct
    /// from an empty hosts file.
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

    public init(hostsText: String = "", hostsReadable: Bool = true, backups: [String] = [],
                sshText: String = "", sshReadable: Bool = true, sshWritable: Bool = true,
                keys: [KeyRow] = [], keysReadable: Bool = true,
                directoryPermission: KeyRow.Permission = .unknown,
                agent: AgentList = .unreachable,
                knownHostsText: String = "", knownHostsReadable: Bool = true,
                knownHostsWritable: Bool = true) {
        self.hostsText = hostsText
        self.hostsReadable = hostsReadable
        self.backups = backups
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
    }

    /// The two fields that shipped first are read outright; anything added
    /// later takes `decodeIfPresent`. A missing `hostsText` is a failure rather
    /// than an empty file, because an empty file is a claim about somebody's
    /// machine and a truncated payload is not evidence for it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostsText = try container.decode(String.self, forKey: .hostsText)
        hostsReadable = try container.decode(Bool.self, forKey: .hostsReadable)
        backups = try container.decodeIfPresent([String].self, forKey: .backups) ?? []
        // Added with tab 2, so every one of them is read with `decodeIfPresent`:
        // a payload from the build before it must still decode, or the page
        // loses the hosts file as well over a key about SSH.
        sshText = try container.decodeIfPresent(String.self, forKey: .sshText) ?? ""
        sshReadable = try container.decodeIfPresent(Bool.self, forKey: .sshReadable) ?? true
        sshWritable = try container.decodeIfPresent(Bool.self, forKey: .sshWritable) ?? true
        // Added with tab 3, and read the same way for the same reason. The
        // defaults are the cautious ones: no keys and an unreachable agent draw
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
    }
}

/// What an Apply came to.
///
/// The page says a different sentence for each, which is why `declined` is not
/// folded into `failed` and why `tooLarge` is not either.
public enum HostsOutcome: String, Codable, Sendable {
    case applied
    case declined
    case failed
    /// Root reported success and the file on disk is not what was sent.
    ///
    /// Two disasters wear this one face and both must reach it: a file root
    /// never touched, and a file root *emptied*. `>` opens before the pipeline
    /// runs and a pipeline's status is its last command's, so a `.done` over
    /// nothing is a shape the real command can produce.
    case notVerified
    /// The backup could not be written, so nothing was attempted.
    case noBackup
    /// The file is larger than the privileged sentence can carry.
    ///
    /// **Decided 2026-08-18: the ceiling is accepted and made legible, not
    /// lifted.** The arithmetic belongs to `HostsWrite.fits(_:)`, because the
    /// ceiling is a fact about the *sentence* and only that file knows the
    /// sentence's shape; a caller computing it would be re-deriving the command.
    ///
    /// Exceeding it is *safe*: the exec itself refuses, nothing runs, the file
    /// is untouched. What was missing was words. This case exists so the person
    /// gets them, and so this refusal never arrives as `failed` — which is what
    /// a `nil` from `HostsWrite.command` already means («not base64») and would
    /// tell somebody with a 2 MB file precisely nothing. **Two different
    /// refusals must not arrive as one outcome.**
    case tooLarge
}

/// Whether a write is in flight, and what the last one came to.
///
/// Its own event rather than a field of `HostsState`: the transport replays the
/// last event *per name*, and a page reopened mid-write needs both the file and
/// «a write is in flight». One slot hands it whichever arrived last, which is
/// what left Homebrew's page idle with an operation running behind it.
public struct HostsOperation: Codable, Sendable, Equatable {
    public var running: Bool
    public var lastOutcome: String?
    public init(running: Bool, lastOutcome: String? = nil) {
        self.running = running
        self.lastOutcome = lastOutcome
    }
}
