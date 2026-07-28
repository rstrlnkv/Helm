import Foundation
import HelmRuntime

/// A property list crossing a concurrency boundary. `[String: Any]` cannot be
/// Sendable, and the contents are read-only here, so the box carries them.
public struct PlistData: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) { self.raw = raw }
}

public protocol LeftoversFilePort: Sendable {
    /// Whether the item's own folder can be written — i.e. whether Helm can
    /// move the file to the Trash without an admin password.
    func isWritable(_ url: URL) -> Bool
    func children(of url: URL) -> [URL]
    func exists(_ path: String) -> Bool
    func size(_ url: URL) -> Int
    func readPlist(_ url: URL) -> PlistData?
}


/// Installed apps and their bundle ids — the yardstick for "is anyone still
/// using this".
public protocol InstalledAppsPort: Sendable {
    func installedBundleIDs() -> Set<String>
}

/// Activated system extensions, so an extension whose app is gone can be told
/// apart from one that is simply not running.
public protocol ExtensionsPort: Sendable {
    /// The full list, so the module can name them instead of counting them.
    func installedExtensions() -> [SystemExtensionInfo]
    /// launchd labels the user has switched off.
    func disabledLabels() -> Set<String>
    /// Switches a login item off or back on, and stops it now if it is running.
    func setDisabled(_ disabled: Bool, label: String)
}
