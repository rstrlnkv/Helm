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
}

public protocol TrashPort: Sendable {
    func trash(_ url: URL) -> Bool
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    func quit(bundleID: String)
}
