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
    /// **Asked of the directory, once**: asked per item, hundreds of identical
    /// calls make it the most expensive step of the scan, and a fake answering by
    /// item path would model one locked file among writable ones — a distinction
    /// the shipping code cannot make and does not need to.
    func isWritableDirectory(_ url: URL) -> Bool
    /// Where this path actually leads, with **every** symbolic link in it followed.
    ///
    /// Asked of each of the eight directories the scan is compiled with, because a
    /// name is not a place: four of them do not exist on a stock install, so any
    /// process running as the user can create one as a link to somewhere else and
    /// have the whole enumeration happen there — under Helm's Full Disk Access,
    /// with the row still spelling the directory it was compiled with.
    ///
    /// **The whole path, not its last component.** `isSymbolicLinkKey` on
    /// `~/Library/QuickLook` answers about `QuickLook` alone, and a link at
    /// `~/Library` redirects the same scan without that ever being true — the
    /// ancestor case `PathCanonical` handles for the removal gate. A source whose
    /// resolved spelling is its own is canonical in every component, so the
    /// children built from it need no second resolution of their own.
    func resolvingSymlinks(_ url: URL) -> URL
    /// What a source directory holds — and whether it opened at all.
    ///
    /// **Three answers, not an array.** A folder that is not there and a folder
    /// this process may not read would both come back empty, and the second is a
    /// permission drawn as a fact about somebody's Mac — «No leftovers found» about
    /// a folder nobody opened. `DirectoryListing.Contents.refused` is the third
    /// answer, and a fake of this port can hold it because the port can.
    func contents(of url: URL) -> DirectoryListing.Contents
    /// Whether something is at this path — and `nil` when this process cannot tell.
    ///
    /// **Not `Bool`, because `false` would mean two things.**
    /// `FileManager.fileExists` returns false for a path that is not there *and*
    /// for one inside a directory this process may not search (a mode, an ACL,
    /// somebody else's folder, a missing TCC grant). The one thing between a live
    /// login item and `.orphaned` is whether its `Program` is there, so a refused
    /// read would make a working job point at nothing — an orange «Leftover»
    /// badge, a tick from «Select all», and a «Turn off» that really does switch
    /// off working software. `nil` is «I could not tell», and the scan answers
    /// `.undetermined` rather than guessing.
    func exists(_ path: String) -> Bool?
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
/// **Both readings are optional, and `nil` is «the tool did not answer».**
/// An empty list is the unsafe direction for each: no active extension means a
/// launch agent whose label *is* a live system extension becomes a leftover
/// with a tick beside it, and no disabled label means a login item somebody
/// switched off loses the badge that says so (Architecture/ModulePattern.md
/// § Module pattern: an unreadable system answer is not folded toward the
/// permissive side). Nothing is promoted to `.orphaned` on a reading that did
/// not happen.
public protocol LoadedItemsPort: Sendable {
    /// The full list, so the module can name them instead of counting them.
    func installedExtensions() -> [SystemExtensionInfo]?
    /// launchd labels the user has switched off.
    func disabledLabels() -> Set<String>?
}

/// Switching a login item off or back on, and stopping it now if it is running.
///
/// **Split from the reading side, because the scan never writes**: the
/// scanner and its fakes take only what they read.
///
/// **The answer is launchd's, not the call's returning.** `.accepted` means launchd
/// accepted the `disable` or `enable`; `.refused` is a definite refusal, a label
/// `LaunchLabel.isSwitchable` turns away included; `.unknown` is a tool that timed
/// out or did not launch, so the switch may or may not have landed. A `bootout` or
/// `kickstart` that fails is not an answer: the job may simply not be running.
public protocol LoginItemSwitchPort: Sendable {
    func setDisabled(_ disabled: Bool, label: String) -> SwitchAnswer
}

/// What `LoginItemSwitchPort.setDisabled` heard back. Three, because the engine's
/// record needs the third: a label whose `disable` timed out may be disabled, and a
/// disabled label nobody recorded is one nobody gives back.
public enum SwitchAnswer: Sendable, Equatable {
    case accepted
    case refused
    case unknown
}
