import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

final class UninstallerOrphanScanTests: XCTestCase {
    /// Only bundle-id-shaped entries with no installed app are reported, grouped by id.
    func testScanOrphansGroupsByBundleID() async {
        let fs = FakeFS(existing: [
            "/Users/x/Library/Caches/com.gone.app": 500,
            "/Users/x/Library/Preferences/com.gone.app.plist": 20,
            "/Users/x/Library/Caches/com.acme.tool": 100,
            "/Users/x/Library/Caches/Google": 999,
        ])
        fs.listings = [
            "/Users/x/Library/Caches": ["com.gone.app", "com.acme.tool", "Google"],
            "/Users/x/Library/Preferences": ["com.gone.app.plist"],
        ]
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                  apps: FakeApps(apps: [InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                                                     path: "/Applications/Tool.app")]),
                                  fs: fs, trash: FakeTrash(), running: FakeRunning(running: []))
        let groups = await e.scanOrphans()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bundleID, "com.gone.app")
        XCTAssertEqual(groups.first?.totalBytes, 520)
        XCTAssertEqual(Set(groups.first?.leftovers.map(\.path) ?? []),
                       ["/Users/x/Library/Caches/com.gone.app",
                        "/Users/x/Library/Preferences/com.gone.app.plist"])
    }

    /// One id found in several folders is asked about once: each question is a
    /// LaunchServices lookup, and a scan over thousands of entries repeats ids.
    func testAnIdFoundInSeveralFoldersIsAskedAboutOnce() async {
        final class Counting: AppLister, @unchecked Sendable {
            var asked: [String] = []
            func installedBundleIDs() -> Set<String> { [] }
            func isKnownToSystem(bundleID: String) -> Bool { asked.append(bundleID); return false }
            func installedApps() -> [InstalledApp] { [] }
            func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        }
        let fs = FakeFS(existing: [:])
        fs.listings = [
            "/Users/x/Library/Caches": ["com.gone.app"],
            "/Users/x/Library/Preferences": ["com.gone.app.plist"],
            "/Users/x/Library/Application Support": ["com.gone.app"],
        ]
        let apps = Counting()
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: apps,
                                  fs: fs, trash: FakeTrash(), running: FakeRunning(running: []))
        _ = await e.scanOrphans()
        XCTAssertEqual(apps.asked, ["com.gone.app"], "the same id was put to LaunchServices more than once")
    }
}
