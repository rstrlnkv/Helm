import XCTest
@testable import Module_Uninstaller_Engine

// MARK: - Fakes

struct FakeFS: FileSystemPort {
    let existing: [String: Int]
    /// Directory listings for the orphan scan, keyed by parent path.
    var listings: [String: [String]] = [:]
    func exists(_ url: URL) -> Bool { existing[url.path] != nil }
    func size(_ url: URL) -> Int { existing[url.path] ?? 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] {
        (listings[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
}
struct FakeApps: AppLister {
    func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
    var known: Set<String> = []
    func isKnownToSystem(bundleID: String) -> Bool { known.contains(bundleID) }
    var apps: [InstalledApp] = []
    func installedApps() -> [InstalledApp] { apps }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
}
final class FakeTrash: TrashPort, @unchecked Sendable {
    var trashed: [String] = []
    let failing: Set<String>
    init(failing: [String] = []) { self.failing = Set(failing) }
    func trashItem(_ url: URL) -> TrashOutcome {
        if failing.contains(url.path) {
            // 513 = NSFileWriteNoPermissionError, what macOS returns for a
            // protected container.
            return TrashOutcome(succeeded: false, errorCode: 513, message: "denied")
        }
        trashed.append(url.path)
        return .success
    }
}
/// A running app that can actually stop running.
///
/// `running` was a `let`, so quitting changed nothing the port could report and
/// "the app is gone now" was unrepresentable — which is why nothing could test
/// a wait for it, and why the wait was a fixed 800 ms sleep in the view model.
final class FakeRunning: RunningAppsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var running: Set<String>
    /// Apps that ignore a quit request, so the deadline path has a subject.
    private let stubborn: Set<String>
    /// Records (bundleID, force) so tests can assert how an app was quit.
    private(set) var quits: [(String, Bool)] = []

    /// How long an app takes to actually go after being asked.
    ///
    /// Zero would make every test of a *wait* vacuous: the app would be gone
    /// before `waitUntilGone` was even called, so the assertion would hold with
    /// the wait deleted. A real app takes a moment, and that moment is the
    /// whole subject.
    private let quitAfter: TimeInterval

    init(running: [String], stubborn: [String] = [], quitAfter: TimeInterval = 0) {
        self.running = Set(running)
        self.stubborn = Set(stubborn)
        self.quitAfter = quitAfter
    }

    func isRunning(bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running.contains(bundleID)
    }

    func quit(bundleID: String, force: Bool) {
        lock.lock()
        quits.append((bundleID, force))
        let willGo = !stubborn.contains(bundleID)
        let delay = quitAfter
        if willGo, delay == 0 { running.remove(bundleID) }
        lock.unlock()
        guard willGo, delay > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock(); running.remove(bundleID); lock.unlock()
        }
    }
}

// MARK: - Tests

final class UninstallerEngineTests: XCTestCase {
    /// A running app must be force-quit only when the caller asks for it.
    func test_quit_passes_force_flag_to_the_port() async {
        let running = FakeRunning(running: ["com.test.app"])
        let e = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                  apps: FakeApps(), fs: FakeFS(existing: [:]),
                                  trash: FakeTrash(), running: running)
        e.quit(bundleID: "com.test.app")
        e.quit(bundleID: "com.test.app", force: true)
        XCTAssertEqual(running.quits.map(\.1), [false, true])
    }

    /// Leftover paths in the shape the engine will actually see: inside the
    /// home the engine was given. Bare "/a" is refused by the scope gate, and
    /// rightly — nothing at the root of the volume is an app's leftover.
    private let cacheA = "/Users/x/Library/Caches/a"
    private let cacheB = "/Users/x/Library/Caches/b"

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

    /// What a removal says it freed is measured off the disk, not off a table of
    /// sizes a test wrote down — `FMFileSystem.size` has always been
    /// `FileWeight.allocated`, so a fake table was never the thing production
    /// reads. Those three tests live in `TrashBatchFollowsTheSharedRulesTests`
    /// now, over a real tree, beside the batch rules they are part of.
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
                                                                     path: "/Applications/Tool.app", sizeBytes: 1)]),
                                  fs: fs, trash: FakeTrash(), running: FakeRunning(running: []))
        let groups = await e.scanOrphans()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bundleID, "com.gone.app")
        XCTAssertEqual(groups.first?.totalBytes, 520)
        XCTAssertEqual(Set(groups.first?.leftovers.map(\.path) ?? []),
                       ["/Users/x/Library/Caches/com.gone.app",
                        "/Users/x/Library/Preferences/com.gone.app.plist"])
    }

}
