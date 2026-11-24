import Foundation
import HelmRuntime

public protocol AppLister: Sendable {
    /// Apps from /Applications, ~/Applications, and any Setapp folder, unsized —
    /// see `appSizes`.
    func installedApps() -> [InstalledApp]
    /// Bundle path → size on disk. Separate because measuring a bundle walks
    /// every file in it: the list is worth showing before the numbers arrive.
    func appSizes(_ apps: [InstalledApp]) -> [String: Int]
    /// Just the ids, unsized: the leftovers scan only asks "is this app still
    /// here?", and sizing walks every file of every bundle.
    func installedBundleIDs() -> Set<String>
    /// Does the system know an app with this bundle id, wherever it lives?
    /// LaunchServices sees helpers nested inside other bundles and apps deeper
    /// than the listing's two levels; a directory listing sees neither.
    func isKnownToSystem(bundleID: String) -> Bool
    /// The installed bundles declaring this id, normally one. Two matter: an id
    /// is read from an app's own `Info.plist`, so an app can declare somebody
    /// else's, and every candidate built from the id belongs to the other one
    /// as well. An honest second copy means the same: the data stays in use.
    func installedPaths(forBundleID id: String) -> [String]

    /// When Spotlight last recorded this bundle being opened, or `nil`.
    ///
    /// Every reason it has no date collapses into `nil`, and the caller cannot
    /// tell them apart: the volume is not indexed or indexing is off, the
    /// bundle has not been indexed yet (a fresh install, a reindex in progress),
    /// Spotlight has an entry with no last-used attribute (never opened, or not
    /// yet recorded; on a volume it does not index the system's own answer is the
    /// file's modification date, which is not an opening and is refused), the
    /// attribute is not a date, and the path is gone. It is the *opening of this
    /// bundle* through LaunchServices — an app used every
    /// day through a helper in another bundle can read as long unopened.
    /// A caller must therefore say "no record", never "never opened".
    ///
    /// Blocking, one Spotlight lookup per call: call it off the main thread.
    func lastOpened(path: String) -> Date?

    /// Application bundles sitting in the user's Trash, or `nil` when the Trash
    /// could not be read at all.
    ///
    /// Dragging an app there is how most people uninstall on a Mac. The bundle
    /// is intact while it waits, so its own `Info.plist` still names its id.
    ///
    /// Reading `~/.Trash` requires Full Disk Access, which every install takes
    /// away. A refused read is `nil`, not empty, so the switch on the Leftovers
    /// tab does not say on over a Trash nothing can see (`TrashWatch`).
    ///
    /// A Trash that is not there yet (a fresh account) is `[]`: empty is the
    /// true answer, and it must not read as a missing permission.
    func trashedApps() -> [TrashedApp]?

    /// Whether the Trash can be read at all, asked by the switch on a press
    /// without opening a single bundle. Not readable is a refused
    /// read (Full Disk Access); a Trash that is not there is readable and empty,
    /// the same split `trashedApps()` makes.
    func trashIsReadable() -> Bool
}

extension AppLister {
    /// What a lister that only lists can answer. `WorkspaceAppLister` overrides
    /// it, because the folders it lists are not where every app lives.
    func installedPaths(forBundleID id: String) -> [String] {
        installedApps().filter { $0.bundleID == id }.map(\.path)
    }

    /// Nothing, for a lister that only knows what is installed: an answer, not
    /// a refused read.
    func trashedApps() -> [TrashedApp]? { [] }

    /// What `trashedApps()` says, so a lister that only lists keeps its answer.
    func trashIsReadable() -> Bool { trashedApps() != nil }

    /// No dates, for a lister that only lists — an answer, "no record".
    func lastOpened(path: String) -> Date? { nil }
}

public protocol FileSystemPort: Sendable {
    func exists(_ url: URL) -> Bool
    /// Allocated bytes, the contents of a directory or package included and a hard
    /// link counted once. 0 for a path that cannot be read, a missing one among them.
    func size(_ url: URL) -> Int
    /// Resolve a `*`-in-last-component pattern against its parent dir.
    func glob(_ pattern: URL) -> [URL]
    /// Immediate children of a directory; empty if missing or unreadable.
    func children(of url: URL) -> [URL]
}

public struct TrashOutcome: Sendable, Equatable {
    let succeeded: Bool
    /// Cocoa error code when it failed (0 when it succeeded or was unknown).
    let errorCode: Int
    let message: String

    init(succeeded: Bool, errorCode: Int = 0, message: String = "") {
        self.succeeded = succeeded
        self.errorCode = errorCode
        self.message = message
    }

    static let success = TrashOutcome(succeeded: true)
}

public protocol TrashPort: Sendable {
    /// Reports what macOS actually said: a failure guessed from the path tells
    /// people to grant access they already have.
    func trashItem(_ url: URL) -> TrashOutcome
}

/// System extensions block their host app from being moved; the UI needs to
/// name that reason instead of reporting a bare failure.
///
/// One question, because only one is asked; Leftovers has its own port for the
/// whole list.
public protocol SystemExtensionPort: Sendable {
    /// Bundle ids that currently have an activated system extension, or `nil` when
    /// `systemextensionsctl` did not answer at all.
    ///
    /// Empty is «no extensions on this Mac»; `nil` is «the tool did not run».
    /// Folded into empty, a bundle refused for a live extension would be
    /// classified from the bare Cocoa code, without the sheet's «Open
    /// Extensions…». An optional also lets a test plant the silence.
    func activeExtensionHosts() -> Set<String>?
}

/// Whether Helm may read what only Full Disk Access opens. The unattended orphan
/// scan asks it before it lists anything.
public protocol FullDiskAccessPort: Sendable {
    /// `.granted` only when a protected file was actually read. `nil` is a probe
    /// that could not answer, and it is not granted: the listing answers empty
    /// for what it cannot open, so an unconfirmed grant is not one to scan under.
    func fullDiskAccess() -> PermissionState?
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    /// `force` skips the app's save/confirm dialogs, for an app the person chose
    /// to remove while it runs.
    ///
    /// By bundle identifier, so it reaches every running copy. A fake records
    /// only ids, so "the wrong copy was quit" is a state no test can express.
    func quit(bundleID: String, force: Bool)
}

/// Default when no lister is injected (tests, previews): a Mac with no system
/// extensions, an answer and not the silence. A test that wants the silence
/// brings a double of its own.
public struct NoSystemExtensions: SystemExtensionPort {
    public init() {}
    public func activeExtensionHosts() -> Set<String>? { [] }
}

/// Default when no probe is injected (tests, previews): a Mac that granted it.
public struct GrantedFullDiskAccess: FullDiskAccessPort {
    public init() {}
    public func fullDiskAccess() -> PermissionState? { .granted }
}
