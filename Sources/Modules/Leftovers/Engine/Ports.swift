import Foundation
import HelmRuntime

/// A property list crossing a concurrency boundary. `[String: Any]` cannot be
/// Sendable, and the contents are read-only here, so the box carries them.
public struct PlistData: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) { self.raw = raw }
}

public protocol LeftoversFilePort: Sendable {
    func children(of url: URL) -> [URL]
    func exists(_ path: String) -> Bool
    func size(_ url: URL) -> Int
    func readPlist(_ url: URL) -> PlistData?
    func trash(_ url: URL) -> TrashResult
}

public struct TrashResult: Sendable, Equatable {
    public let succeeded: Bool
    public let message: String
    public init(succeeded: Bool, message: String = "") {
        self.succeeded = succeeded
        self.message = message
    }
    public static let success = TrashResult(succeeded: true)
}

/// Installed apps and their bundle ids — the yardstick for "is anyone still
/// using this".
public protocol InstalledAppsPort: Sendable {
    func installedBundleIDs() -> Set<String>
}

/// Activated system extensions, so an extension whose app is gone can be told
/// apart from one that is simply not running.
public protocol ExtensionsPort: Sendable {
    func activeExtensionIdentifiers() -> Set<String>
    /// The full list, so the module can name them instead of counting them.
    func installedExtensions() -> [SystemExtensionInfo]
}
