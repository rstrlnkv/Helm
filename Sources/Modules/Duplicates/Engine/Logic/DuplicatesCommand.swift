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
    public init(path: String) { self.path = path }
}
