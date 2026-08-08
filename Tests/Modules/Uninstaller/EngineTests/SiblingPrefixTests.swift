import XCTest
@testable import Module_Uninstaller_Engine

/// Uninstalling one app must not offer another installed app's data.
///
/// Every id-derived glob is `"<id>*"` or `"*<id>*"`, and a bundle id is a prefix
/// of its own vendor's next product: `com.acme.tool*` matches `com.acme.toolPro`,
/// which is a different app, possibly running. `scanOrphansSync` runs every
/// entry it finds past `installedBundleIDs()`; `scanSync` ran its glob matches
/// past nothing at all — and because a glob hit is never `matchedByName`,
/// `UninstallPlan.defaultSelection` arrives with it already ticked.
///
/// These assert on *which paths* the scan claims, never on how many, because
/// the count is satisfied by any two of them.
private struct GlobFS: FileSystemPort {
    /// Everything that exists, path → size.
    let entries: [String: Int]
    func exists(_ url: URL) -> Bool { entries[url.path] != nil }
    func size(_ url: URL) -> Int { entries[url.path] ?? 0 }
    /// A real resolution against siblings, which is what the system port does —
    /// a fake that answers `[]` cannot see this defect at all.
    func glob(_ pattern: URL) -> [URL] {
        let dir = pattern.deletingLastPathComponent().path
        let name = pattern.lastPathComponent
        return entries.keys
            .filter { ($0 as NSString).deletingLastPathComponent == dir }
            .filter { GlobMatch.matches(($0 as NSString).lastPathComponent, pattern: name) }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }
    func children(of url: URL) -> [URL] {
        entries.keys
            .filter { ($0 as NSString).deletingLastPathComponent == url.path }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }
}

private struct Installed: AppLister {
    let ids: Set<String>
    func installedApps() -> [InstalledApp] {
        ids.map { InstalledApp(name: $0, bundleID: $0, path: "/Applications/\($0).app", sizeBytes: 0) }
    }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { ids }
    func isKnownToSystem(bundleID: String) -> Bool { ids.contains(bundleID) }
}

final class SiblingPrefixTests: XCTestCase {
    private let lib = "/Users/x/Library"

    private func scan(_ id: String, installed: Set<String>, entries: [String: Int]) async throws -> ScanResult {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: Installed(ids: installed),
                                       fs: GlobFS(entries: entries),
                                       trash: NoTrash(), running: NoRunning())
        return try await engine.scan(bundleID: id, appPath: "/Applications/Tool.app", appName: "Tool")
    }

    /// The trap. `com.acme.toolPro` is installed and has a container of its own;
    /// removing `com.acme.tool` must not reach into it.
    func test_uninstalling_an_app_does_not_claim_a_longer_named_siblings_data() async throws {
        let mine = "\(lib)/Containers/com.acme.tool"
        let theirs = "\(lib)/Containers/com.acme.toolPro"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: [mine: 10, theirs: 9_000_000])
        XCTAssertFalse(result.leftovers.map(\.path).contains(theirs),
                       "the scan claimed an installed sibling's container: \(result.leftovers.map(\.path))")
        XCTAssertEqual(result.leftovers.map(\.path), [mine],
                       "and it still claims its own")
    }

    /// The same shape in every folder a glob reaches, because one filter that
    /// covers Containers and misses Caches is not a fix.
    func test_no_glob_folder_lets_a_longer_named_sibling_through() async throws {
        var entries: [String: Int] = [:]
        var theirs: [String] = []
        for dir in ["Caches", "Containers", "Application Scripts"] {
            entries["\(lib)/\(dir)/com.acme.tool"] = 1
            let p = "\(lib)/\(dir)/com.acme.toolPro"
            entries[p] = 1
            theirs.append(p)
        }
        entries["\(lib)/LaunchAgents/com.acme.toolPro.plist"] = 1
        theirs.append("\(lib)/LaunchAgents/com.acme.toolPro.plist")
        entries["\(lib)/Group Containers/group.com.acme.toolPro"] = 1
        theirs.append("\(lib)/Group Containers/group.com.acme.toolPro")

        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: entries)
        let claimed = Set(result.leftovers.map(\.path))
        for path in theirs {
            XCTAssertFalse(claimed.contains(path), "claimed \(path)")
        }
    }

    /// A sibling that is a *namespaced* app of the same vendor — the shape the
    /// separator rule alone waves through, because `com.acme.tool.staging`
    /// really is `com.acme.tool` followed by a dot. It is installed; it is not
    /// this app's leftover.
    func test_an_installed_namespaced_app_is_not_this_apps_leftover() async throws {
        let mine = "\(lib)/Caches/com.acme.tool"
        let theirs = "\(lib)/Caches/com.acme.tool.staging"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.tool.staging"],
                                    entries: [mine: 1, theirs: 1])
        XCTAssertEqual(result.leftovers.map(\.path), [mine])
    }

    /// Positive control, and the reason the glob exists: a helper or extension
    /// container that belongs to no installed app of its own is still found.
    /// Without this the tests above pass by refusing everything.
    func test_helper_and_team_prefixed_containers_are_still_found() async throws {
        let entries = [
            "\(lib)/Caches/com.acme.tool": 1,
            "\(lib)/Caches/com.acme.tool.helper": 1,
            "\(lib)/Containers/com.acme.tool.packet-extension-mac": 1,
            "\(lib)/Group Containers/2XZUN9L63Z.com.acme.tool": 1,
            "\(lib)/LaunchAgents/com.acme.tool.updater.plist": 1,
        ]
        let result = try await scan("com.acme.tool", installed: ["com.acme.tool"], entries: entries)
        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(entries.keys))
    }

    /// The consequence the review screen shows. A glob hit carries
    /// `matchedByName == false`, which is what `defaultSelection` ticks — so an
    /// unfiltered hit is not merely listed, it is pre-selected next to a Trash
    /// button.
    func test_nothing_belonging_to_an_installed_sibling_arrives_pre_ticked() async throws {
        let theirs = "\(lib)/Containers/com.acme.toolPro"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: ["\(lib)/Containers/com.acme.tool": 1, theirs: 1])
        let app = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                               path: "/Applications/Tool.app", sizeBytes: 0)
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)
        XCTAssertFalse(UninstallPlan.defaultSelection([group]).contains(theirs),
                       "pre-ticked an installed app's container")
    }
}
