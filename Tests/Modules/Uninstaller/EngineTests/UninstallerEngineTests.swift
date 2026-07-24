import XCTest
@testable import Module_Uninstaller_Engine

// MARK: - Fakes

private struct FakeFS: FileSystemPort {
    let existing: [String: Int]
    func exists(_ url: URL) -> Bool { existing[url.path] != nil }
    func size(_ url: URL) -> Int { existing[url.path] ?? 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
}
private struct FakeApps: AppLister { func installedApps() -> [InstalledApp] { [] } }
private final class FakeTrash: TrashPort, @unchecked Sendable {
    var trashed: [String] = []
    let failing: Set<String>
    init(failing: [String] = []) { self.failing = Set(failing) }
    func trash(_ url: URL) -> Bool {
        if failing.contains(url.path) { return false }
        trashed.append(url.path); return true
    }
}
private struct FakeRunning: RunningAppsPort {
    let running: Set<String>
    init(running: [String]) { self.running = Set(running) }
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    func quit(bundleID: String) {}
}

// MARK: - Tests

final class UninstallerEngineTests: XCTestCase {
    private func engine(fs: FakeFS, trash: FakeTrash = FakeTrash(), running: [String] = []) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                          apps: FakeApps(), fs: fs, trash: trash,
                          running: FakeRunning(running: running))
    }

    func testScanReturnsOnlyExistingCandidates() async throws {
        let fs = FakeFS(existing: [
            "/Users/x/Library/Caches/com.acme.tool": 100,
            "/Users/x/Library/Preferences/com.acme.tool.plist": 10,
        ])
        let r = try await engine(fs: fs).scan(bundleID: "com.acme.tool",
                                              appPath: "/Applications/Tool.app", appName: "Tool")
        XCTAssertEqual(Set(r.leftovers.map(\.path)),
                       ["/Users/x/Library/Caches/com.acme.tool",
                        "/Users/x/Library/Preferences/com.acme.tool.plist"])
        XCTAssertEqual(r.leftovers.first { $0.kind == .caches }?.sizeBytes, 100)
        XCTAssertFalse(r.runningNow)
    }

    func testScanFlagsRunning() async throws {
        let fs = FakeFS(existing: [:])
        let r = try await engine(fs: fs, running: ["com.acme.tool"])
            .scan(bundleID: "com.acme.tool", appPath: "/Applications/Tool.app", appName: "Tool")
        XCTAssertTrue(r.runningNow)
    }

    func testUninstallTrashesSelectedAndSumsFreed() async throws {
        let trash = FakeTrash()
        let fs = FakeFS(existing: ["/a": 100, "/b": 50, "/Applications/Tool.app": 1000])
        let r = try await engine(fs: fs, trash: trash)
            .uninstall(appPath: "/Applications/Tool.app", paths: ["/a", "/b"])
        XCTAssertEqual(r.freedBytes, 1150)
        XCTAssertEqual(Set(trash.trashed), ["/a", "/b", "/Applications/Tool.app"])
        XCTAssertTrue(r.failed.isEmpty)
    }

    func testUninstallReportsTrashFailures() async throws {
        let trash = FakeTrash(failing: ["/b"])
        let fs = FakeFS(existing: ["/a": 100, "/b": 50, "/Applications/Tool.app": 1000])
        let r = try await engine(fs: fs, trash: trash)
            .uninstall(appPath: "/Applications/Tool.app", paths: ["/a", "/b"])
        XCTAssertEqual(r.failed, ["/b"])
        XCTAssertEqual(r.freedBytes, 1100)
    }
}
