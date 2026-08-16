import Foundation

/// Everything the uninstaller's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
///
/// **Two cases were removed on 2026-08-16 rather than kept as room to grow.**
/// `uninstall` was `trashPaths` with the app bundle appended — a second door to
/// the same removal, skipping the plan that already appends it
/// (`UninstallPlan.paths`) — and `systemExtensions` was the only route to a port
/// member and a `systemextensionsctl` call that no screen ever drew. Nothing in
/// `Sources` sent either, and `periphery` cannot see it: a `case` a switch
/// handles is a case that is used. A command kept for a screen that may be
/// written one day is a command nobody deletes and nobody notices rotting.
public enum UninstallerCommand: String, CaseIterable, Sendable {
    case listApps
    case appSizes
    case scan
    case scanOrphans
    case trashPaths
    case quit
    /// Shares its spelling with `ScanCommand.backgroundScan`, which is what
    /// the coordinator sends — pinned by a test, because the two live in
    /// different targets and neither compiler sees both.
    case backgroundScan
    case trashedAppLeftovers
    case dismissTrashedApp
    case setWatchingTrash
    case watchingTrash
}

/// What the uninstaller's engine says without being asked.
///
/// An enum for the same reason every other module has one: the name crosses two
/// target boundaries and nothing on either side of a literal would notice it
/// changing. It was a `static let` on the engine, which the module's own two
/// sides could share — but the **host** could not, and wrote `"trashChanged"`
/// as a string under a comment explaining that the boundary left it no choice.
/// It did: `UninstallerDescriptor` re-exports this the way the descriptors
/// already re-export their command enums for the hotkeys, and the host says the
/// name rather than spelling it.
///
/// What a silent break costs here is a feature going quiet: drag an app to the
/// Trash and Helm simply never offers to clear up after it.
public enum UninstallerEvent: String, Sendable {
    /// Something reached `~/.Trash` that could have been an app, or the offer
    /// was switched on and what is already there deserves an answer.
    case trashChanged
}

// MARK: - What the commands carry
//
// **Three request shapes, and each was declared twice.** `ScanReq`,
// `UninstallReq` and `QuitReq` were `private struct`s inside the engine and
// `private struct`s again inside the view model, matched to each other by field
// name across a JSON hop with no compiler between them — the same pair found in
// Keep Awake, Homebrew and VPN. Two of the three are below; `UninstallReq`'s
// successor went with the `uninstall` command it was the payload of.
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

/// A batch to move to the Trash, and what Helm may do about an application in it
/// that turns out to still be running.
///
/// The permission travels with the batch because the *question* belongs to the
/// engine: whether an app is up can only be answered at the moment of removal,
/// and the answer the review screen holds was read when the scan ran. The view
/// model used to ask it there and quit the apps itself, which is how an app
/// started since the review got its bundle moved out from under it.
public struct TrashBatchRequest: Codable, Sendable {
    public let paths: [String]
    /// The person's answer to «Force quit and remove anyway». False means: if
    /// anything in this batch is up, move nothing.
    public let quitRunningApps: Bool

    public init(paths: [String], quitRunningApps: Bool = false) {
        self.paths = paths
        self.quitRunningApps = quitRunningApps
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
