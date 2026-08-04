import Foundation
import HelmRuntime

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
