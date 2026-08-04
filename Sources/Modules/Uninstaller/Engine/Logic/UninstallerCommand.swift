import Foundation

/// Everything the uninstaller's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum UninstallerCommand: String, CaseIterable, Sendable {
    case listApps
    case appSizes
    case scan
    case scanOrphans
    case uninstall
    case trashPaths
    case quit
    case systemExtensions
    /// Shares its spelling with `ScanCommand.backgroundScan`, which is what
    /// the coordinator sends — pinned by a test, because the two live in
    /// different targets and neither compiler sees both.
    case backgroundScan
    case trashedAppLeftovers
    case dismissTrashedApp
    case setWatchingTrash
    case watchingTrash
}
