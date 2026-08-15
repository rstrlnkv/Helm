import Foundation

/// Everything the duplicate finder's engine answers to.
///
/// **The switch below is exhaustive, and that is the whole gain.** A command
/// name used to be a string on both sides of the transport: a caller's typo fell
/// through the engine's `default`, the reply was empty, and the caller read that
/// as `nil` — which this codebase spells "the module could not answer". A
/// misspelling was indistinguishable from a refusal. Adding a case here without
/// handling it is now a build error instead.
///
/// The unknown-name door is still there and still open, one step earlier: a
/// string the enum cannot parse is a command this engine does not know, which is
/// exactly what the transport should say about it.
public enum DuplicatesCommand: String, CaseIterable, Sendable {
    case find
    case cancel
    case trash
    /// Shares its spelling with `ScanCommand.backgroundScan`, which is what the
    /// coordinator sends — pinned by a test, because the two live in different
    /// targets and neither compiler sees both.
    case backgroundScan
}

/// Everything the engine says while a search runs.
///
/// The one name it emits was a literal in the engine and a literal again in the
/// view model's `guard event.name == …`. Both targets import this file, so a
/// spelling they must agree on has no reason to be written twice — and the
/// failure is the quiet kind: the search still runs, the sheet's bar simply
/// never moves.
public enum DuplicatesEvent: String, Sendable {
    /// How far the walk and the hashing have got.
    case progress
}

/// Which folder to search. It crossed the transport as a `["path": …]`
/// dictionary from the view model and a `PathPayload` struct inside the engine
/// — the same shape agreed on by habit, where renaming the field on one side
/// leaves the other encoding a key nobody reads and the search answering
/// nothing at all.
public struct DuplicateSearchRequest: Codable, Sendable {
    public let path: String

    /// Which copy of identical content this search should keep, as the person
    /// has the page set right now.
    ///
    /// **Optional, and a raw string.** A non-optional field with a default would
    /// not decode a payload written before it existed: a synthesised `Decodable`
    /// demands the key whatever the property's initial value is, and
    /// `JSONDecoder` then abandons the whole request rather than the one field —
    /// so a search sent by an older caller would arrive as no search at all
    /// (CLAUDE.md § A `defaulted` property on a `Codable` payload). `nil` means
    /// «the caller did not say», and the engine falls back to what is stored.
    ///
    /// A string on the wire because a `KeepPolicy` this build does not know is a
    /// value to fall back from, not a document to throw away; `keepPolicy` below
    /// is the only place it is turned back into one.
    public let policy: String?

    /// The policy this request carries, or nil when it carries none — including
    /// a spelling this build has never heard of.
    public var keepPolicy: KeepPolicy? { policy.flatMap(KeepPolicy.init(rawValue:)) }

    /// Taking the policy itself rather than its spelling: the caller cannot
    /// write a value the engine will not recognise, which is the whole failure a
    /// name shared across a target boundary has.
    public init(path: String, policy: KeepPolicy? = nil) {
        self.path = path
        self.policy = policy?.rawValue
    }
}
