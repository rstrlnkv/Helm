import Foundation
import HelmRuntime

public struct InstalledApp: Codable, Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let path: String
    public let sizeBytes: Int
    public init(name: String, bundleID: String, path: String, sizeBytes: Int) {
        self.name = name; self.bundleID = bundleID; self.path = path; self.sizeBytes = sizeBytes
    }
}

public enum LeftoverKind: String, Codable, Sendable, CaseIterable {
    case appSupport, caches, preferences, containers, groupContainers,
         savedState, logs, httpStorages, webKit, cookies, appScripts, launchAgent
}

public struct Leftover: Codable, Equatable, Sendable {
    public let path: String
    public let kind: LeftoverKind
    public let sizeBytes: Int
    public let matchedByName: Bool
    public init(path: String, kind: LeftoverKind, sizeBytes: Int, matchedByName: Bool) {
        self.path = path; self.kind = kind; self.sizeBytes = sizeBytes; self.matchedByName = matchedByName
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let bundleID: String
    public let appPath: String
    public let appSizeBytes: Int
    public let leftovers: [Leftover]
    public let runningNow: Bool
    public init(bundleID: String, appPath: String, appSizeBytes: Int, leftovers: [Leftover], runningNow: Bool) {
        self.bundleID = bundleID; self.appPath = appPath; self.appSizeBytes = appSizeBytes
        self.leftovers = leftovers; self.runningNow = runningNow
    }
}

/// An app sitting in the Trash and what it left behind — one group in the window
/// that offers to clean up after it.
///
/// It crosses the transport because `HelmApp` cannot import this target: the host
/// depends on the UI targets only, so that a direct edge is not "a door past the
/// transport into an engine's internals" (Package.swift, at the HelmApp target).
/// That is why the whole sweep is one command rather than the host listing the
/// Trash itself and asking about each bundle it finds.
public struct TrashedAppLeftovers: Codable, Equatable, Sendable {
    public let bundleID: String
    /// What the person will recognise, from the bundle's own `Info.plist`.
    public let name: String
    /// Where it sits in the Trash. The window reads its icon from here — and it is
    /// deliberately not among the things offered for deletion: the app is already
    /// where the person put it.
    public let appPath: String
    public let leftovers: [Leftover]

    public init(bundleID: String, name: String, appPath: String, leftovers: [Leftover]) {
        self.bundleID = bundleID; self.name = name
        self.appPath = appPath; self.leftovers = leftovers
    }

    public var totalBytes: Int { leftovers.reduce(0) { $0 + $1.sizeBytes } }
}

/// Why one path could not be moved, so the UI can say something actionable.
///
/// **Not `HelmTrash.Refusal` with two extra letters.** It carries a third thing
/// that one deliberately does not: what macOS said, verbatim. The shared loop
/// classifies the error and writes the sentence to the log, because for Disk,
/// Duplicates and Leftovers the classification is the whole of what a person can
/// act on. This module's failure sheet draws both — the reason in Helm's words
/// and macOS's own underneath it as the evidence behind it — and one screen with
/// a use for a field is not a reason to put it on the type the other four share.
///
/// The reason is the enum rather than a string that happens to be its raw value.
/// Leftovers held one of those in a field called `message` and nothing in the
/// type said what it was; three screens here compared it against
/// `.rawValue` by hand.
public struct TrashFailureInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let reason: TrashFailure.Reason
    /// What macOS said, verbatim — the sheet shows it under the reason.
    public let message: String
    public init(path: String, reason: TrashFailure.Reason, message: String = "") {
        self.path = path; self.reason = reason; self.message = message
    }
}

public struct UninstallResult: Codable, Equatable, Sendable {
    public let trashed: [String]
    public let freedBytes: Int
    public let failures: [TrashFailureInfo]

    /// The refused paths, which the two screens read one each: this one decides
    /// which apps a removal answered for, and `failures` is what the report
    /// lists. It was a stored field beside `failures`, appended to on the same
    /// two lines, and nothing but that adjacency kept them in step — a `failed`
    /// missing a path its `failures` recorded would file an app macOS refused as
    /// the person's own "no", which takes it off every screen Helm has.
    public var failed: [String] { failures.map(\.path) }

    public init(trashed: [String], freedBytes: Int, failures: [TrashFailureInfo] = []) {
        self.trashed = trashed; self.freedBytes = freedBytes
        self.failures = failures
    }
}

/// Leftovers grouped by the bundle id of an app that is no longer installed.
public struct OrphanGroup: Codable, Equatable, Sendable {
    public let bundleID: String
    public let leftovers: [Leftover]
    public var totalBytes: Int { leftovers.reduce(0) { $0 + $1.sizeBytes } }
    public init(bundleID: String, leftovers: [Leftover]) {
        self.bundleID = bundleID; self.leftovers = leftovers
    }
}
