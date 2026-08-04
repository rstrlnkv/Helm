import Foundation
import HelmRuntime

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
