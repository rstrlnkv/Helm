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

// MARK: - What the commands carry
//
// **Three request shapes, and each was declared twice.** `ScanReq`,
// `UninstallReq` and `QuitReq` were `private struct`s inside the engine and
// `private struct`s again inside the view model, matched to each other by field
// name across a JSON hop with no compiler between them — the same pair found in
// Keep Awake, Homebrew and VPN.
//
// Here it had already gone wrong. The engine's `QuitReq` read
// `let force: Bool?` and the view model's read `let force: Bool`: one side had
// been made tolerant of a payload without the field and the other had not, and
// nothing could have told anybody the two had stopped being the same type. The
// engine then wrote `r.force ?? false`, a default for a field the only sender
// in the app always sets. One declaration now, and `force` is what it is.

/// Which app to scan for leftovers. The path and the name travel with the id
/// because the app may be gone by the time the engine looks.
public struct UninstallScanRequest: Codable, Sendable {
    public let bundleID: String
    public let appPath: String
    public let appName: String
    public init(bundleID: String, appPath: String, appName: String) {
        self.bundleID = bundleID
        self.appPath = appPath
        self.appName = appName
    }
}

/// The bundle to remove and everything chosen to go with it.
public struct UninstallRequest: Codable, Sendable {
    public let appPath: String
    public let paths: [String]
    public init(appPath: String, paths: [String]) {
        self.appPath = appPath
        self.paths = paths
    }
}

/// Ask a running app to quit before its bundle is taken away.
public struct QuitRequest: Codable, Sendable {
    public let bundleID: String
    /// `terminate` rather than a polite request. The person ticked it.
    public let force: Bool
    public init(bundleID: String, force: Bool) {
        self.bundleID = bundleID
        self.force = force
    }
}
