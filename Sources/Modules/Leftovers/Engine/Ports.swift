import Foundation
import HelmRuntime

/// A property list crossing a concurrency boundary. `[String: Any]` cannot be
/// Sendable, and the contents are read-only here, so the box carries them.
public struct PlistData: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) { self.raw = raw }
}

public protocol LeftoversFilePort: Sendable {
    /// Whether what sits **in this directory** can be moved to the Trash without
    /// an admin password.
    ///
    /// A question about the directory, and it cannot be anything else: moving a
    /// file means unlinking it from its folder, so POSIX asks for write
    /// permission on the folder and never on the file. A read-only plist in
    /// `~/Library/Preferences` still goes to the Trash; an ordinary one in
    /// `/Library/LaunchAgents` does not.
    ///
    /// **It used to be `isWritable(_ item: URL)`** — handed the item, quietly
    /// looking at its parent — and two things came of the name. The scan asked
    /// once per item: 542 identical calls for one answer on this machine's
    /// `~/Library/Preferences`, measured at 3,000 ms against 0,004 ms asked
    /// once, which made it the most expensive step of the pass by 4.5× over
    /// reading every file's size. And the fakes answered by *item* path, so the
    /// tests modelled one locked file among readable ones — a distinction the
    /// shipping code cannot make and does not need to.
    func isWritableDirectory(_ url: URL) -> Bool
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

/// What macOS currently has loaded, as the scan needs to read it.
///
/// Two readings from two different tools — `systemextensionsctl` for the
/// extensions, launchd's own per-user list for the login items somebody has
/// switched off — and they travel together because one scan wants both and
/// neither is a file. Activated extensions are here so an extension whose app is
/// gone can be told apart from one that is simply not running.
public protocol LoadedItemsPort: Sendable {
    /// The full list, so the module can name them instead of counting them.
    func installedExtensions() -> [SystemExtensionInfo]
    /// launchd labels the user has switched off.
    func disabledLabels() -> Set<String>
}

/// Switching a login item off or back on, and stopping it now if it is running.
///
/// **Split from the reading side, because the scan never writes.** These three
/// methods were one protocol named after extensions, two of them launchd's, and
/// the scanner took the whole of it to read two. The cost was visible in the
/// tests: five fakes carried an empty `setDisabled` to satisfy a protocol they
/// only ever read from — five stubs for a method no scan calls.
public protocol LoginItemSwitchPort: Sendable {
    func setDisabled(_ disabled: Bool, label: String)
}
