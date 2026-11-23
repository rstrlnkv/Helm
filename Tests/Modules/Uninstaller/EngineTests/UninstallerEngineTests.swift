import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

final class UninstallerEngineTests: XCTestCase {
    // Leftover paths in the shape the engine will actually see: inside the
    // home the engine was given. Bare "/a" is refused by the scope gate, and
    // rightly — nothing at the root of the volume is an app's leftover.

    private func engine(fs: FakeFS, trash: FakeTrash = FakeTrash(), running: [String] = []) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                          apps: FakeApps(), fs: fs, trash: trash,
                          running: FakeRunning(running: running))
    }

    /// The `*<id>*` glob alone finds what `*.<id>` also found: a team-prefixed
    /// folder, a group-prefixed one and the id with a suffix. A scratch home on
    /// the real filesystem, so the glob is expanded by the shipping port.
    func testGroupContainersAreFoundWithoutTheDotPrefixGlob() async throws {
        let home = scratchDirectory("group-containers")
        let names = ["group.x.com.acme.tool", "TEAM.com.acme.tool", "com.acme.tool.helper"]
        for n in names { try write("Library/Group Containers/\(n)/f", in: home) }
        let r = await UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                                        trash: FakeTrash(), running: FakeRunning(running: []))
            .scan(bundleID: "com.acme.tool", appName: "Tool")
        XCTAssertEqual(Set(r.leftovers.map { URL(fileURLWithPath: $0.path).lastPathComponent }), Set(names))
    }

    func testScanFlagsRunning() async throws {
        let fs = FakeFS(existing: [:])
        let r = await engine(fs: fs, running: ["com.acme.tool"])
            .scan(bundleID: "com.acme.tool", appName: "Tool")
        XCTAssertTrue(r.runningNow)
    }

    // What a removal says it freed is measured off the disk, not off a table of
    // sizes a test wrote down — `FMFileSystem.size` has always been
    // `FileWeight.allocated`, so a fake table was never the thing production
    // reads. Those three tests live in `TrashBatchFollowsTheSharedRulesTests`
    // now, over a real tree, beside the batch rules they are part of.
}

final class UninstallerOrphanScanTests: XCTestCase {
    /// Only bundle-id-shaped entries with no installed app are reported, grouped by id.
    func testScanOrphansGroupsByBundleID() async {
        var fs = FakeFS(existing: [
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
        var fs = FakeFS(existing: [:])
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
