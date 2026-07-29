import XCTest
@testable import Module_Uninstaller_Engine

/// The sibling tests are about the *names* a glob reaches. This one is about
/// the id itself.
///
/// `SiblingPrefixTests` and `NestedSiblingTests` both compare an entry's name
/// against the bundle id being removed, and both take for granted that the id
/// belongs to the app being removed. It does not have to: the id is read from
/// that app's own `Info.plist`, and an app may write anybody's there.
///
/// The exact candidates — `Containers/<id>`, `Preferences/<id>.plist`,
/// `HTTPStorages/<id>`, `WebKit/<id>`, `Cookies/<id>.binarycookies`,
/// `Saved Application State/<id>.savedState` — went through no ownership check
/// at all, so removing a 2 MB download would take the whole of another app's
/// container with it, ticked, on a screen whose next button is Trash.
///
/// The evidence available is that two installed bundles declare the one id.
/// Assertions name paths, never counts.
private struct ImpostorFS: FileSystemPort {
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

/// `listed` is what a directory listing finds; `nested` is an app installed one
/// folder down, which only LaunchServices sees. Both declare the id.
private struct Declarers: AppLister {
    let id: String
    let listed: [String]
    var nested: [String] = []

    func installedApps() -> [InstalledApp] {
        listed.map { InstalledApp(name: "App", bundleID: id, path: $0, sizeBytes: 0) }
    }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { [id] }
    func isKnownToSystem(bundleID: String) -> Bool { bundleID == id }
    func installedPaths(forBundleID id: String) -> [String] {
        id == self.id ? listed + nested : []
    }
}

private struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome { .success }
}
private struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {}
}

final class ImpostorBundleIDTests: XCTestCase {
    private let lib = "/Users/x/Library"
    private let id = "com.adobe.acrobat"

    /// Every folder the exact candidates reach, so a fix that covers Containers
    /// and misses Cookies is visibly not a fix.
    private var theirData: [String: Int] {
        ["\(lib)/Containers/\(id)": 4_000_000,
         "\(lib)/Caches/\(id)": 900_000,
         "\(lib)/Preferences/\(id).plist": 2_000,
         "\(lib)/HTTPStorages/\(id)": 30_000,
         "\(lib)/WebKit/\(id)": 40_000,
         "\(lib)/Cookies/\(id).binarycookies": 1_000,
         "\(lib)/Saved Application State/\(id).savedState": 3_000,
         "\(lib)/Application Scripts/\(id)": 500,
         "\(lib)/Application Support/\(id)": 700]
    }

    private func scan(_ apps: AppLister, entries: [String: Int]) async throws -> ScanResult {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: apps, fs: ImpostorFS(entries: entries),
                                       trash: NoTrash(), running: NoRunning())
        return try await engine.scan(bundleID: id, appPath: "/Applications/Sketchy.app",
                                     appName: "Sketchy")
    }

    /// The impostor: a second bundle in `/Applications` declaring the id of an
    /// app that is installed and running.
    func test_an_id_a_second_installed_bundle_declares_claims_nothing() async throws {
        let apps = Declarers(id: id, listed: ["/Applications/Sketchy.app",
                                              "/Applications/Adobe Acrobat.app"])
        let result = try await scan(apps, entries: theirData)
        for path in theirData.keys {
            XCTAssertFalse(result.leftovers.map(\.path).contains(path), "claimed \(path)")
        }
    }

    /// The same, with the rightful owner one folder down where the listing
    /// cannot see it — so the engine has to ask the port rather than group the
    /// listing itself.
    func test_a_rival_the_listing_cannot_see_still_stops_the_claim() async throws {
        let apps = Declarers(id: id, listed: ["/Applications/Sketchy.app"],
                             nested: ["/Applications/Adobe Acrobat DC/Adobe Acrobat.app"])
        let result = try await scan(apps, entries: theirData)
        XCTAssertEqual(result.leftovers.map(\.path), [], "claimed a nested app's data")
    }

    /// Refusing is not the same as hiding: nothing that was refused may come
    /// back through `defaultSelection`, which is what puts a tick beside a path.
    func test_nothing_refused_arrives_pre_ticked() async throws {
        let apps = Declarers(id: id, listed: ["/Applications/Sketchy.app",
                                              "/Applications/Adobe Acrobat.app"])
        let result = try await scan(apps, entries: theirData)
        let app = InstalledApp(name: "Sketchy", bundleID: id,
                               path: "/Applications/Sketchy.app", sizeBytes: 0)
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)
        XCTAssertEqual(UninstallPlan.defaultSelection([group]), [])
    }

    /// The control, and the reason none of this may be answered by refusing
    /// everything: one bundle declares the id, so the app's own files are found
    /// in every one of those folders.
    func test_an_app_that_alone_declares_its_id_keeps_its_leftovers() async throws {
        let apps = Declarers(id: id, listed: ["/Applications/Sketchy.app"])
        let result = try await scan(apps, entries: theirData)
        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(theirData.keys))
    }
}
