import Foundation
import HelmRuntime

public protocol AppLister: Sendable {
    /// Apps from /Applications, ~/Applications, and any Setapp folder, with
    /// `sizeBytes` left at zero — see `appSizes`.
    func installedApps() -> [InstalledApp]
    /// Bundle path → size on disk. Separate because measuring a bundle walks
    /// every file in it: the list is worth showing before the numbers arrive.
    func appSizes(_ apps: [InstalledApp]) -> [String: Int]
    /// Just the ids. Sizing a bundle means walking every file inside it, and
    /// the leftovers scan only ever asks "is this app still here?" — it threw
    /// the sizes away after paying nine seconds for them.
    func installedBundleIDs() -> Set<String>
    /// Does the system know an app with this bundle id, wherever it lives?
    /// LaunchServices sees apps one folder down and helpers nested inside
    /// other bundles; a directory listing sees neither.
    func isKnownToSystem(bundleID: String) -> Bool
    /// The installed bundles declaring this id. Normally one — the app the
    /// scan is about — because an id is what identifies an application. Two is
    /// the fact the scan cannot do without: a bundle id is read from an app's
    /// own `Info.plist`, so an app can declare somebody else's, and every
    /// candidate built from an id belongs to whoever else declares it just as
    /// well. An honest second copy (a Setapp build beside a direct download)
    /// looks the same and means the same thing — the data stays in use.
    func installedPaths(forBundleID id: String) -> [String]

    /// When Spotlight last recorded this bundle being opened, or `nil`.
    ///
    /// **Every reason it has no date collapses into `nil`, and the caller cannot
    /// tell them apart:** the volume is not indexed or indexing is off, the
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
    /// Dragging an app there is how almost everyone uninstalls on a Mac, and it is
    /// the one removal Helm never saw. The bundle is intact while it waits, so its
    /// own `Info.plist` still answers the only question the leftover scan needs.
    ///
    /// Reading `~/.Trash` requires Full Disk Access — measured: a process without it
    /// gets `Operation not permitted`. **Empty was the answer to both, and that is
    /// what made the switch on the Leftovers tab a claim nobody had checked:** a
    /// grant every install takes away again arrived here as «there is nothing in
    /// the Trash», so the sweep said so and the switch said on. The refusal is its
    /// own answer now, and `TrashWatch` is what the page draws it from.
    ///
    /// A Trash that is not there yet — a fresh account has none until something is
    /// deleted — is `[]` and not nil: nothing in it is the true answer for that
    /// one, and it must not be reported as a missing permission.
    func trashedApps() -> [TrashedApp]?

    /// Whether the Trash can be read at all — the one question the switch asks on
    /// a press, answered without opening a single bundle. Not readable is a refused
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

    /// Nothing, for a lister that only knows what is installed — an answer, since
    /// such a lister is not the one being refused a read.
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
    /// Reports what macOS actually said: classifying failures by guessing from
    /// the path told users to grant access they already had.
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
    /// **The two were one value, and that cost the module its best sentence.** The
    /// tool's exit status was folded to an empty listing, so «no extensions on this
    /// Mac» and «the tool did not run» arrived as the same empty set — and a bundle
    /// macOS refused *because its extension is live* was then classified from the
    /// bare Cocoa code, with the failure sheet's «Open Extensions…» button missing.
    /// It is also the state no test could plant while both members answered
    /// non-optionals, which is the `PowerSource.supply()` lesson one module over:
    /// the repair belongs on the port.
    func activeExtensionHosts() -> Set<String>?
}

/// Whether Helm may read what only Full Disk Access opens. The unattended orphan
/// scan asks it before it lists anything.
public protocol FullDiskAccessPort: Sendable {
    /// `.granted` only when a protected file was actually read. `nil` is a probe
    /// that could not be answered at all, and it is **not** granted: with nobody
    /// watching, a grant nobody could confirm is not one to scan under, because
    /// the listing below it answers empty for what it could not open.
    func fullDiskAccess() -> PermissionState?
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    /// `force` skips the app's save/confirm dialogs — needed when the user
    /// chose to remove an app that is still running.
    ///
    /// **By bundle identifier, so no location.** The call reaches every copy of
    /// the app that is running. A fake can only record ids, so "the wrong copy
    /// was quit" is a state no test can express while the port has this shape.
    func quit(bundleID: String, force: Bool)
}

/// Default when no lister is injected (tests, previews). A Mac with no system
/// extensions on it — which is an answer, and deliberately not the silence above:
/// a test that wants the tool to have said nothing says so with a double of its
/// own.
public struct NoSystemExtensions: SystemExtensionPort {
    public init() {}
    public func activeExtensionHosts() -> Set<String>? { [] }
}

/// Default when no probe is injected (tests, previews): a Mac that granted it.
public struct GrantedFullDiskAccess: FullDiskAccessPort {
    public init() {}
    public func fullDiskAccess() -> PermissionState? { .granted }
}
