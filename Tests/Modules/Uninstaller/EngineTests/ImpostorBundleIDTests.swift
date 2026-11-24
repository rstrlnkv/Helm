import XCTest
@testable import Module_Uninstaller_Engine

/// `listed` is what a directory listing finds; `nested` is an app installed one
/// folder down, which only LaunchServices sees. Both declare the id.
private struct Declarers: AppLister {
    let id: String
    let listed: [String]
    var nested: [String] = []

    func installedApps() -> [InstalledApp] {
        listed.map { InstalledApp(name: "App", bundleID: id, path: $0) }
    }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { [id] }
    func isKnownToSystem(bundleID: String) -> Bool { bundleID == id }
    func installedPaths(forBundleID id: String) -> [String] {
        id == self.id ? listed + nested : []
    }
}

/// The id itself, where the sibling tests are about the names a glob reaches.
/// The id is read from the app's own `Info.plist`, where an app may write
/// anybody's, and the exact candidates (`Containers/<id>` and the rest) would
/// hand over another app's data, ticked. Two installed bundles declaring the
/// id is the evidence. Assertions name paths, never counts.
final class ImpostorBundleIDTests: XCTestCase {
    private let lib = "/Users/x/Library"
    private let id = "com.adobe.acrobat"

    /// Every folder the exact candidates reach, so missing one is visible.
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
                                       apps: apps, fs: FakeFS(existing: entries, globbing: true),
                                       trash: NoTrash(), running: NoRunning())
        return await engine.scan(bundleID: id, appName: "Sketchy")
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

    /// The same, with the rightful owner where the listing cannot see it, so the
    /// engine has to ask the port.
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
                               path: "/Applications/Sketchy.app")
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)
        XCTAssertEqual(UninstallPlan.defaultSelection([group]), [])
    }

    /// The control: one bundle declares the id, and the app's own files are found
    /// in every folder.
    func test_an_app_that_alone_declares_its_id_keeps_its_leftovers() async throws {
        let apps = Declarers(id: id, listed: ["/Applications/Sketchy.app"])
        let result = try await scan(apps, entries: theirData)
        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(theirData.keys))
    }
}
