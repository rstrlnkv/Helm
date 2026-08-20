import Foundation
import HelmRuntime
@testable import Module_Leftovers_Engine

/// The module's four ports, faked once for this target — the scanner's three
/// and the switch the engine alone holds.
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
    /// Paths whose existence this process may not check: a program inside a
    /// directory it cannot search, where `stat` answers `EACCES` and
    /// `FileManager.fileExists` folds that to «not there». The port's third answer,
    /// and without it «the read was refused» was a state no fixture could hold —
    /// which is `ARefusedReadIsNotAMissingProgramTests`.
    var unreadable: Set<String> = []
    /// Directories that will not open at all: `contents` answers `.refused` for
    /// these, which is the port's third answer and the one `[]` used to swallow.
    /// Without it «Helm could not read this folder» was a state no fixture could
    /// hold, and a scan that never opened a source looked exactly like a clean Mac
    /// (`ASourceNobodyWalkedIsNotACleanMacTests`).
    var unopenable: Set<String> = []
    var plists: [String: PlistData] = [:]

    /// **A path that leads somewhere other than where it is spelled.** One entry
    /// per symbolic link: the key is the spelling, the value is what it points at.
    ///
    /// Everything this fake answers goes through `resolve` below, so a redirect on
    /// a directory moves its children, their contents and their sizes with it —
    /// which is what the real `FileManager` does and what `listing`, keyed by
    /// spelling alone, could not describe. «These children actually live somewhere
    /// else» was therefore a state no test in this target could write down, which
    /// is why the scan trusted the seven directory names it is compiled with:
    /// `ADirectoryThatIsNotTheOneItNamesTests` is the case that had nowhere to go.
    var redirects: [String: String] = [:]

    func isWritableDirectory(_ url: URL) -> Bool { !unwritable.contains(url.path) }
    func contents(of url: URL) -> DirectoryListing.Contents {
        let real = resolve(url.path)
        guard !unopenable.contains(real) else { return .refused }
        // The child keeps the spelling it was asked for, exactly as
        // `DirectoryListing.children` builds it out of the URL handed in — that
        // false spelling is the whole of the finding.
        return .listed((listing[real] ?? []).map { url.appendingPathComponent($0) })
    }
    func exists(_ path: String) -> Bool? {
        let real = resolve(path)
        guard !unreadable.contains(real) else { return nil }
        return existing.contains(real)
    }
    /// One size for everything: what this port answers is measured against the real
    /// filesystem in `LeftoversRemovalTests`, and a fixture size here is only ever
    /// «some bytes».
    func size(_ url: URL) -> Int { 100 }
    /// Nil for a plist nobody put here — which is also the port's answer for a file
    /// it could not read, and `APlistNobodyCouldReadTests` is about that being one
    /// answer for two facts.
    func readPlist(_ url: URL) -> PlistData? { plists[resolve(url.path)] }

    func resolvingSymlinks(_ url: URL) -> URL { URL(fileURLWithPath: resolve(url.path)) }

    /// Where a path leads once every link in it has been followed — component by
    /// component, so a redirected *ancestor* moves everything under it. A source
    /// whose own last component is a link and one three folders up are the same
    /// escape, and a fake that could only do the first would bless the second.
    private func resolve(_ path: String) -> String {
        var resolved = "/"
        for component in path.split(separator: "/") {
            resolved = (resolved as NSString).appendingPathComponent(String(component))
            // Bounded: a fixture may point two links at each other, and a test
            // hanging is a worse answer than a test failing.
            var hops = 0
            while let target = redirects[resolved], hops < 8 {
                resolved = target
                hops += 1
            }
        }
        return resolved
    }
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
/// Both fields are optional the way the port is: `nil` is «the tool did not
/// answer», which is the state a dropped exit status made unrepresentable — and
/// therefore untestable — while `[]` went on meaning «nothing is loaded».
struct LeftoversFakeLoaded: LoadedItemsPort {
    var installed: [SystemExtensionInfo]? = []
    var disabled: Set<String>? = []
    func installedExtensions() -> [SystemExtensionInfo]? { installed }
    func disabledLabels() -> Set<String>? { disabled }
}

/// The writing half of launchd: what it was asked, and nothing done.
///
/// Two files carried this privately and byte for byte, under the same sentence,
/// and a third and fourth needed it the moment every construction had to name
/// `switcher:` — the real one holds `launchctl disable gui/<uid>/<label>` against
/// the login items of whoever runs the suite.
///
/// `setDisabled` returns nothing in the port, so there is no refusal for this to
/// be freer or poorer about; what it records is the whole of the observable act.
final class LeftoversFakeSwitcher: LoginItemSwitchPort, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func setDisabled(_ disabled: Bool, label: String) {
        lock.lock(); defer { lock.unlock() }
        seen.append(label)
    }
    var labels: [String] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }
}
