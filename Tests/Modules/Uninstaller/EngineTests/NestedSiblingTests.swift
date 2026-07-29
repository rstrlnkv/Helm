import XCTest
@testable import Module_Uninstaller_Engine

/// The sibling test again, for the sibling the *directory listing* cannot see.
///
/// `SiblingPrefixTests` pins the rule: uninstalling `com.acme.tool` must not
/// claim `com.acme.tool.staging`'s data, because that is a different app
/// somebody has installed. `LeftoverOwnership` enforces it with two rules, and
/// the second — "not another installed app" — is the only one that can refuse a
/// name like `com.acme.tool.staging`, which really is this id followed by a dot.
///
/// That second rule is answered from `installedBundleIDs()`, and `AppLister`'s
/// own documentation says what that set is missing:
///
/// > Does the system know an app with this bundle id, wherever it lives?
/// > LaunchServices sees apps one folder down and helpers nested inside other
/// > bundles; a directory listing sees neither.
///
/// `installedBundleIDs()` is `contentsOfDirectory` over four folders, matching
/// `*.app` at the top level only. `/Applications/Adobe Acrobat DC/Adobe
/// Acrobat.app`, `/Applications/Microsoft Office/…`, and every helper inside
/// another bundle are absent from it. `OrphanDetector` was given
/// `isKnownToSystem` for exactly this reason — its comment records that nested
/// apps "were being offered for deletion while their apps were installed and
/// running" — and `scanSync`'s glob filter, written later, asks the narrow
/// question.
///
/// So the vendor's *other* product, installed one folder down, is invisible to
/// the rule meant to protect it: its container is claimed, and because a glob
/// hit is never `matchedByName` it arrives on the review screen pre-ticked next
/// to a Trash button.
///
/// Assertions name paths, never counts — a count is satisfied by any two of
/// them.
private struct NestedFS: FileSystemPort {
    let entries: [String: Int]
    func exists(_ url: URL) -> Bool { entries[url.path] != nil }
    func size(_ url: URL) -> Int { entries[url.path] ?? 0 }
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

/// A real Mac's two answers, which differ. `topLevel` is what
/// `contentsOfDirectory` finds; `nested` is installed and running and lives one
/// folder down, so only LaunchServices knows about it.
private struct PartlyVisible: AppLister {
    let topLevel: Set<String>
    let nested: Set<String>
    func installedApps() -> [InstalledApp] {
        topLevel.map { InstalledApp(name: $0, bundleID: $0,
                                    path: "/Applications/\($0).app", sizeBytes: 0) }
    }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { topLevel }
    func isKnownToSystem(bundleID: String) -> Bool {
        topLevel.contains(bundleID) || nested.contains(bundleID)
    }
}

private struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome { .success }
}
private struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {}
}

final class NestedSiblingTests: XCTestCase {
    private let lib = "/Users/x/Library"

    private func scan(_ id: String, topLevel: Set<String>, nested: Set<String>,
                      entries: [String: Int]) async throws -> ScanResult {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: PartlyVisible(topLevel: topLevel, nested: nested),
                                       fs: NestedFS(entries: entries),
                                       trash: NoTrash(), running: NoRunning())
        return try await engine.scan(bundleID: id, appPath: "/Applications/Acrobat.app",
                                     appName: "Acrobat")
    }

    /// The shape `SiblingPrefixTests` already refuses, moved one folder down.
    ///
    /// `com.adobe.acrobat.reader` is `com.adobe.acrobat` followed by a dot, so
    /// the separator rule waves it through; only "it is another installed app"
    /// can stop it, and the set that answers that question does not contain a
    /// bundle inside `/Applications/Adobe Acrobat DC/`.
    func test_a_nested_installed_sibling_is_not_this_apps_leftover() async throws {
        let mine = "\(lib)/Containers/com.adobe.acrobat"
        let theirs = "\(lib)/Containers/com.adobe.acrobat.reader"

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: [mine: 10, theirs: 4_000_000])

        XCTAssertFalse(result.leftovers.map(\.path).contains(theirs),
                       "claimed an installed app's container because it lives one folder "
                       + "down: \(result.leftovers.map(\.path))")
        XCTAssertEqual(result.leftovers.map(\.path), [mine], "and it still claims its own")
    }

    /// Every glob folder, because a filter that covers Containers and misses
    /// LaunchAgents is not a filter. A LaunchAgent is the worst of them: trashing
    /// it stops the neighbour's updater from ever running again.
    func test_no_glob_folder_lets_a_nested_installed_sibling_through() async throws {
        var entries: [String: Int] = [:]
        var theirs: [String] = []
        for dir in ["Caches", "Containers", "Application Scripts"] {
            entries["\(lib)/\(dir)/com.adobe.acrobat"] = 1
            let path = "\(lib)/\(dir)/com.adobe.acrobat.reader"
            entries[path] = 1
            theirs.append(path)
        }
        for path in ["\(lib)/LaunchAgents/com.adobe.acrobat.reader.plist",
                     "\(lib)/Group Containers/group.com.adobe.acrobat.reader"] {
            entries[path] = 1
            theirs.append(path)
        }

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: entries)

        let claimed = Set(result.leftovers.map(\.path))
        for path in theirs { XCTAssertFalse(claimed.contains(path), "claimed \(path)") }
    }

    /// What the review screen does with it. A glob hit carries
    /// `matchedByName == false`, and that is exactly what `defaultSelection`
    /// ticks — so the neighbour's data is not merely listed, it is selected.
    func test_a_nested_siblings_data_does_not_arrive_pre_ticked() async throws {
        let theirs = "\(lib)/Containers/com.adobe.acrobat.reader"
        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: ["\(lib)/Containers/com.adobe.acrobat": 1,
                                              theirs: 1])
        let app = InstalledApp(name: "Acrobat", bundleID: "com.adobe.acrobat",
                               path: "/Applications/Acrobat.app", sizeBytes: 0)
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)

        XCTAssertFalse(UninstallPlan.defaultSelection([group]).contains(theirs),
                       "pre-ticked a nested installed app's container")
    }

    /// The control, and the reason the glob exists at all: a helper container
    /// that belongs to no installed app — nested or otherwise — is still found.
    /// Without this the tests above could be satisfied by refusing everything.
    func test_a_helper_belonging_to_nobody_is_still_found() async throws {
        let entries = [
            "\(lib)/Caches/com.adobe.acrobat": 1,
            "\(lib)/Caches/com.adobe.acrobat.helper": 1,
            "\(lib)/Containers/com.adobe.acrobat.packet-extension-mac": 1,
        ]

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: [],
                                    entries: entries)

        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(entries.keys))
    }
}
