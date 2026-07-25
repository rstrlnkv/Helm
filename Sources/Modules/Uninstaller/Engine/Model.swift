import Foundation

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

/// Why one path could not be moved, so the UI can say something actionable.
public struct TrashFailureInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    /// Raw value of `TrashFailure.Reason`.
    public let reason: String
    /// What macOS said, verbatim — dev builds surface it for triage.
    public let message: String
    public init(path: String, reason: String, message: String = "") {
        self.path = path; self.reason = reason; self.message = message
    }
}

public struct UninstallResult: Codable, Equatable, Sendable {
    public let trashed: [String]
    public let failed: [String]
    public let freedBytes: Int
    public let failures: [TrashFailureInfo]
    public init(trashed: [String], failed: [String], freedBytes: Int,
                failures: [TrashFailureInfo] = []) {
        self.trashed = trashed; self.failed = failed; self.freedBytes = freedBytes
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
