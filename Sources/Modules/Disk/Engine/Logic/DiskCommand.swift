import Foundation

/// Everything the disk module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. The
/// unknown-name door stays open one step earlier: a string this enum cannot
/// parse is a command the engine does not know, which is what the transport
/// should say about it.
public enum DiskCommand: String, CaseIterable, Sendable {
    case volumes
    case scan
    /// Shares its spelling with `ScanCommand.backgroundScan`, which is what
    /// the coordinator sends — pinned by a test, because the two live in
    /// different targets and neither compiler sees both.
    case backgroundScan
    case cancel
    case trash
}

/// Everything the engine says while a scan runs.
///
/// Two names, and each was a literal in the engine's `emit` and a literal again
/// in the view model's `switch`. The sixth module found that way. What it costs
/// here is the whole screen: `partial` is what draws the ring while the walk is
/// still going, so a name that stops matching leaves a spinner over a scan that
/// is working perfectly.
public enum DiskEvent: String, Sendable {
    /// How far the walk has got — files seen, bytes so far.
    case progress
    /// A tree good enough to draw, before the walk has finished.
    case partial
}
