import Foundation
import HelmRuntime

public struct InstalledApp: Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let path: String
}

public enum LeftoverKind: String, Sendable, CaseIterable {
    case appSupport, caches, preferences, containers, groupContainers,
         savedState, logs, httpStorages, webKit, cookies, appScripts, launchAgent
}

public struct Leftover: Equatable, Sendable {
    public let path: String
    public let kind: LeftoverKind
    public let sizeBytes: Int
    public let matchedByName: Bool
}

public struct ScanResult: Equatable, Sendable {
    public let leftovers: [Leftover]
    public let runningNow: Bool
}

/// An app sitting in the Trash and what it left behind — one group in the window
/// that offers to clean up after it.
///
/// `HelmApp` depends on the UI targets only, so the whole sweep is one call on
/// the module's model rather than the host listing the Trash itself.
public struct TrashedAppLeftovers: Equatable, Sendable {
    public let bundleID: String
    /// What the person will recognise, from the bundle's own `Info.plist`.
    public let name: String
    /// Where it sits in the Trash. The window reads its icon from here; it is not
    /// offered for deletion, since the app is already where the person put it.
    public let appPath: String
    public let leftovers: [Leftover]

    public var totalBytes: Int { leftovers.reduce(0) { $0 + $1.sizeBytes } }
}

/// Why one path could not be moved, so the UI can say something actionable.
///
/// Not `HelmTrash.Refusal`: it also carries what macOS said, verbatim, which
/// this module's failure sheet draws under the reason. The other modules act on
/// the classification alone, so the field stays off the shared type.
///
/// The reason is the enum, not a string holding its raw value.
public struct TrashFailureInfo: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let reason: TrashFailure.Reason
    /// What macOS said, verbatim — the sheet shows it under the reason.
    public let message: String
    init(path: String, reason: TrashFailure.Reason, message: String = "") {
        self.path = path; self.reason = reason; self.message = message
    }
}

public struct UninstallResult: Equatable, Sendable {
    public let trashed: [String]
    public let freedBytes: Int
    public let failures: [TrashFailureInfo]

    /// The application bundles in the batch that were still running when it came
    /// to move them, with no quit allowed or still up after the quit that was.
    /// Non-empty means nothing moved: a leftover carries no link back to its app,
    /// so there is no "the rest of it" (`UninstallPlan.verdict`).
    ///
    /// Its own field rather than a `TrashFailureInfo`: nothing was attempted, so
    /// there is no failure to classify, and the screen's answer is the offer it
    /// already has, to quit the app or allow the quit.
    public let stillRunning: [String]

    /// The refused paths, derived from `failures` so the two cannot disagree: a
    /// path missing here would file an app macOS refused as the person's own
    /// "no", which takes it off every screen.
    public var failed: [String] { failures.map(\.path) }

    init(trashed: [String], freedBytes: Int, failures: [TrashFailureInfo] = [],
                stillRunning: [String] = []) {
        self.trashed = trashed; self.freedBytes = freedBytes
        self.failures = failures; self.stillRunning = stillRunning
    }
}

/// Leftovers grouped by the bundle id of an app that is no longer installed.
public struct OrphanGroup: Equatable, Sendable {
    public let bundleID: String
    public let leftovers: [Leftover]
    public var totalBytes: Int { leftovers.reduce(0) { $0 + $1.sizeBytes } }
}
