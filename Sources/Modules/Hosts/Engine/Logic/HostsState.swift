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

    public init(hostsText: String = "", hostsReadable: Bool = true, backups: [String] = []) {
        self.hostsText = hostsText
        self.hostsReadable = hostsReadable
        self.backups = backups
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
