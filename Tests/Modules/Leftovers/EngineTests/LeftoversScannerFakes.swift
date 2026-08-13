import Foundation
import HelmRuntime
@testable import Module_Leftovers_Engine

/// The scanner's three ports, faked once for this target.
///
/// **There were five sets of these in six files, and two of them could not
/// describe an ordinary Mac.** `LeftoversScanTests` and
/// `LeftoversOfferConsistencyTests` each carried a `FakeFiles` whose writability
/// was one `Bool` for every directory — while the port is
/// `isWritableDirectory(_ url:)` and the whole distinction the scanner draws with
/// it is `~/Library/LaunchAgents` (the person's own, writable) against
/// `/Library/LaunchAgents` and `/Library/LaunchDaemons` (root's, not). One flag
/// cannot hold both at once, so «one row Helm can move and one it cannot, in the
/// same scan» was a state no test in those files could write down — and
/// `ScanOrderIsTotalTests` builds exactly that pair, with the `/Library` copy
/// coming back `writable: true`, which on a real Mac it never is. That is the
/// unrepresentable-state shape CLAUDE.md names, in a fixture rather than in a fake
/// of a port: the same defect `LeftoversWritableTests` had already found in the
/// other direction and fixed *locally*, by locking the item instead of its folder.
///
/// So writability is a set of directory paths here, which is the only lock that
/// decides this — and the shared fake is the *richer* of the two shapes, never the
/// simpler one.
struct LeftoversFakeFiles: LeftoversFilePort {
    /// Directories whose contents Helm cannot unlink: root's folders. Empty means
    /// every directory is the person's own, which is what every fixture that does
    /// not care about this wants.
    var unwritable: Set<String> = []
    var listing: [String: [String]] = [:]
    /// Paths that exist — a job's `Program`, so far.
    var existing: Set<String> = []
    var plists: [String: PlistData] = [:]

    func isWritableDirectory(_ url: URL) -> Bool { !unwritable.contains(url.path) }
    func children(of url: URL) -> [URL] {
        (listing[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
    func exists(_ path: String) -> Bool { existing.contains(path) }
    /// One size for everything: what this port answers is measured against the real
    /// filesystem in `LeftoversRemovalTests`, and a fixture size here is only ever
    /// «some bytes».
    func size(_ url: URL) -> Int { 100 }
    /// Nil for a plist nobody put here — which is also the port's answer for a file
    /// it could not read, and `APlistNobodyCouldReadTests` is about that being one
    /// answer for two facts.
    func readPlist(_ url: URL) -> PlistData? { plists[url.path] }
}

struct LeftoversFakeApps: InstalledAppsPort {
    var ids: Set<String> = []
    func installedBundleIDs() -> Set<String> { ids }
}

/// The reading half of launchd and `systemextensionsctl`.
///
/// Both fields are real answers the scan reads: `installed` is what
/// `installedExtensions()` returns, and `disabled` is the labels the person has
/// switched off. A fixture that set an `ids` field nothing read is the defect
/// `ExtensionOfferFixtureTests` exists for.
struct LeftoversFakeLoaded: LoadedItemsPort {
    var installed: [SystemExtensionInfo] = []
    var disabled: Set<String> = []
    func installedExtensions() -> [SystemExtensionInfo] { installed }
    func disabledLabels() -> Set<String> { disabled }
}
