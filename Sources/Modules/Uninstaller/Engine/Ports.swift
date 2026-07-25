import Foundation

public protocol AppLister: Sendable {
    /// Apps from /Applications, ~/Applications, and any Setapp folder.
    func installedApps() -> [InstalledApp]
}

public protocol FileSystemPort: Sendable {
    func exists(_ url: URL) -> Bool
    /// Recursive byte size; 0 if missing.
    func size(_ url: URL) -> Int
    /// Resolve a `*`-in-last-component pattern against its parent dir.
    func glob(_ pattern: URL) -> [URL]
    /// Immediate children of a directory; empty if missing or unreadable.
    func children(of url: URL) -> [URL]
}

public protocol TrashPort: Sendable {
    func trash(_ url: URL) -> Bool
}

/// System extensions block their host app from being moved; the UI needs to
/// name that reason instead of reporting a bare failure.
public protocol SystemExtensionPort: Sendable {
    /// Bundle ids that currently have an activated system extension.
    func activeExtensionHosts() -> Set<String>
    func installedExtensions() -> [SystemExtensionInfo]
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    /// `force` skips the app's save/confirm dialogs — needed when the user
    /// chose to remove an app that is still running.
    func quit(bundleID: String, force: Bool)
}

public extension RunningAppsPort {
    func quit(bundleID: String) { quit(bundleID: bundleID, force: false) }
}

/// Default when no lister is injected (tests, previews).
public struct NoSystemExtensions: SystemExtensionPort {
    public init() {}
    public func activeExtensionHosts() -> Set<String> { [] }
    public func installedExtensions() -> [SystemExtensionInfo] { [] }
}
