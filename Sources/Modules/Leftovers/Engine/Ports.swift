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
    /// Where this path actually leads, with **every** symbolic link in it followed.
    ///
    /// Asked of each of the seven directories the scan is compiled with, because a
    /// name is not a place: four of them do not exist on a stock install, so any
    /// process running as the user can create one as a link to somewhere else and
    /// have the whole enumeration happen there — under Helm's Full Disk Access,
    /// with the row still spelling the directory it was compiled with.
    ///
    /// **The whole path, not its last component.** `isSymbolicLinkKey` on
    /// `~/Library/QuickLook` answers about `QuickLook` alone, and a link at
    /// `~/Library` redirects the same scan without that ever being true — the
    /// ancestor case `PathCanonical` was written for, one layer up from the removal
    /// gate. A source whose resolved spelling is its own is canonical in every
    /// component, so the children built from it are honest by construction and need
    /// no second resolution of their own.
    func resolvingSymlinks(_ url: URL) -> URL
    /// What a source directory holds — and whether it opened at all.
    ///
    /// **It answered `[URL]`, and the empty array meant two things.** A folder that
    /// is not there and a folder this process may not read both came back with
    /// nothing in them, and the scan has no way to tell one from the other: the
    /// second is a permission drawn as a fact about somebody's Mac, and the page
    /// over it says «No leftovers found» about a folder nobody opened. The same
    /// fold `exists` was taken apart for below, one declaration further down, and
    /// the same repair — `DirectoryListing.Contents.refused` is the third answer,
    /// and a fake of this port can hold it because the port can.
    func contents(of url: URL) -> DirectoryListing.Contents
    /// Whether something is at this path — and `nil` when this process cannot tell.
    ///
    /// **It answered `Bool`, and `false` meant two things.**
    /// `FileManager.fileExists` returns false for a path that is not there *and*
    /// for one inside a directory this process may not search: measured on this
    /// Mac, a file under a mode-000 parent answers `false` while `stat` answers
    /// `EACCES`. The one thing between a live login item and `.orphaned` is
    /// whether its `Program` is there, so a refused read made a working job point
    /// at nothing — an orange «Leftover» badge, a tick from «Select all», and a
    /// «Turn off» that really does switch off working software. It bites hardest
    /// with Full Disk Access denied, which is 23 of 42 launches on the machine
    /// ARCHITECTURE.md records.
    ///
    /// The same fold, one file over, that commit `6de0a337` closed for the plist
    /// read: `nil` is «I could not tell», and the scan answers `.undetermined`
    /// rather than guessing which of the two it was.
    func exists(_ path: String) -> Bool?
    func size(_ url: URL) -> Int
    func readPlist(_ url: URL) -> PlistData?
}

public extension LeftoversFilePort {
    /// What is in the directory, for a caller that walks what it finds and draws
    /// no conclusion from an empty answer — every reader of a *source* draws one,
    /// so every reader of a source asks `contents(of:)`.
    ///
    /// Written once here rather than in each conformance, so «the entries» and
    /// «did it open» cannot come apart in a fake the way they came apart in the
    /// port.
    func children(of url: URL) -> [URL] { contents(of: url).entries }
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
/// **Both readings are optional, and `nil` is «the tool did not answer».** They
/// answered `[]` and `[]`, which is the unsafe direction for each: no active
/// extension means a launch agent whose label *is* a live system extension stops
/// being in use and becomes a leftover with a tick beside it, and no disabled label
/// means a login item somebody switched off loses the badge that says so. Two
/// facts — «nothing is loaded» and «nobody asked» — and a dropped exit status made
/// them one (§ Anything that can stop being true on its own owns a channel to say
/// so). Nothing is promoted to `.orphaned` on a reading that did not happen.
public protocol LoadedItemsPort: Sendable {
    /// The full list, so the module can name them instead of counting them.
    func installedExtensions() -> [SystemExtensionInfo]?
    /// launchd labels the user has switched off.
    func disabledLabels() -> Set<String>?
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
