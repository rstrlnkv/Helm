import Foundation
import HelmRuntime

public protocol AppLister: Sendable {
    /// Apps from /Applications, ~/Applications, and any Setapp folder, with
    /// `sizeBytes` left at zero — see `appSizes`.
    func installedApps() -> [InstalledApp]
    /// Bundle id → size on disk. Separate because measuring a bundle walks
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
}

public extension AppLister {
    /// What a lister that only lists can answer. `WorkspaceAppLister` overrides
    /// it, because the folders it lists are not where every app lives.
    func installedPaths(forBundleID id: String) -> [String] {
        installedApps().filter { $0.bundleID == id }.map(\.path)
    }

    /// Nothing, for a lister that only knows what is installed — an answer, since
    /// such a lister is not the one being refused a read.
    func trashedApps() -> [TrashedApp]? { [] }
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

public struct TrashOutcome: Sendable, Equatable {
    public let succeeded: Bool
    /// Cocoa error code when it failed (0 when it succeeded or was unknown).
    public let errorCode: Int
    public let message: String

    public init(succeeded: Bool, errorCode: Int = 0, message: String = "") {
        self.succeeded = succeeded
        self.errorCode = errorCode
        self.message = message
    }

    public static let success = TrashOutcome(succeeded: true)
}

public protocol TrashPort: Sendable {
    /// Reports what macOS actually said: classifying failures by guessing from
    /// the path told users to grant access they already had.
    func trashItem(_ url: URL) -> TrashOutcome
}

/// System extensions block their host app from being moved; the UI needs to
/// name that reason instead of reporting a bare failure.
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
    func installedExtensions() -> [SystemExtensionInfo]
}

public protocol RunningAppsPort: Sendable {
    func isRunning(bundleID: String) -> Bool
    /// `force` skips the app's save/confirm dialogs — needed when the user
    /// chose to remove an app that is still running.
    func quit(bundleID: String, force: Bool)
}

/// Default when no lister is injected (tests, previews). A Mac with no system
/// extensions on it — which is an answer, and deliberately not the silence above:
/// a test that wants the tool to have said nothing says so with a double of its
/// own.
public struct NoSystemExtensions: SystemExtensionPort {
    public init() {}
    public func activeExtensionHosts() -> Set<String>? { [] }
    public func installedExtensions() -> [SystemExtensionInfo] { [] }
}
