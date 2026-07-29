import XCTest
@testable import Module_Uninstaller_Engine

/// The batch flow: pick several apps, review their files grouped per app, then
/// trash the selection. Running apps must not be removed silently.
final class UninstallPlanTests: XCTestCase {
    private func app(_ name: String, _ id: String, size: Int = 1000) -> InstalledApp {
        InstalledApp(name: name, bundleID: id, path: "/Applications/\(name).app", sizeBytes: size)
    }
    private func leftover(_ path: String, _ size: Int) -> Leftover {
        Leftover(path: path, kind: .caches, sizeBytes: size, matchedByName: false)
    }
    private func group(_ name: String, running: Bool, appSize: Int = 1000,
                       leftovers: [Leftover] = []) -> UninstallGroup {
        UninstallGroup(app: app(name, "com.test.\(name)", size: appSize),
                       leftovers: leftovers, running: running)
    }

    // MARK: - Running apps gate

    func testReadyWhenNothingIsRunning() {
        let groups = [group("Alpha", running: false), group("Beta", running: false)]
        XCTAssertEqual(UninstallPlan.readiness(groups, forceQuit: false), .ready)
    }

    func testRunningAppsBlockUntilForceQuitIsAllowed() {
        let groups = [group("Alpha", running: true), group("Beta", running: false),
                      group("Gamma", running: true)]
        XCTAssertEqual(UninstallPlan.readiness(groups, forceQuit: false),
                       .needsQuit(["Alpha", "Gamma"]))
        // With force-quit chosen the same selection may proceed.
        XCTAssertEqual(UninstallPlan.readiness(groups, forceQuit: true), .ready)
    }

    func testEmptySelectionIsNotReady() {
        XCTAssertEqual(UninstallPlan.readiness([], forceQuit: true), .empty)
    }

    // MARK: - Paths and sizes

    func testPathsCoverTheAppBundleAndItsSelectedLeftovers() {
        let g = group("Alpha", running: false, appSize: 500,
                      leftovers: [leftover("/L1", 10), leftover("/L2", 20)])
        let selected: Set<String> = ["/L1"]
        XCTAssertEqual(UninstallPlan.paths([g], selectedLeftovers: selected),
                       ["/Applications/Alpha.app", "/L1"])
    }

    func testSizeCountsTheBundlePlusSelectedLeftoversOnly() {
        let g = group("Alpha", running: false, appSize: 500,
                      leftovers: [leftover("/L1", 10), leftover("/L2", 20)])
        XCTAssertEqual(UninstallPlan.totalBytes([g], selectedLeftovers: ["/L1"]), 510)
        XCTAssertEqual(UninstallPlan.totalBytes([g], selectedLeftovers: ["/L1", "/L2"]), 530)
        XCTAssertEqual(UninstallPlan.totalBytes([g], selectedLeftovers: []), 500)
    }

    func testEverySelectedAppContributesEvenWithoutLeftovers() {
        let groups = [group("Alpha", running: false, appSize: 100),
                      group("Beta", running: false, appSize: 250)]
        XCTAssertEqual(UninstallPlan.totalBytes(groups, selectedLeftovers: []), 350)
        XCTAssertEqual(UninstallPlan.paths(groups, selectedLeftovers: []),
                       ["/Applications/Alpha.app", "/Applications/Beta.app"])
    }

    /// Prefix globs and exact paths can resolve to the same directory. Trashing
    /// it twice made macOS report "doesn't exist" for the second attempt, which
    /// surfaced as a failure the user could do nothing about.
    func testPathsAreDeduplicated() {
        let leftover = Leftover(path: "/L/Containers/com.a.b", kind: .containers,
                                sizeBytes: 10, matchedByName: false)
        let duplicate = Leftover(path: "/L/Containers/com.a.b", kind: .caches,
                                 sizeBytes: 10, matchedByName: false)
        let g = UninstallGroup(app: app("Alpha", "com.a.b"),
                               leftovers: [leftover, duplicate], running: false)
        XCTAssertEqual(UninstallPlan.paths([g], selectedLeftovers: ["/L/Containers/com.a.b"]),
                       ["/Applications/Alpha.app", "/L/Containers/com.a.b"])
    }

    func testSizeCountsADuplicatedPathOnce() {
        let leftover = Leftover(path: "/L/x", kind: .containers, sizeBytes: 10, matchedByName: false)
        let duplicate = Leftover(path: "/L/x", kind: .caches, sizeBytes: 10, matchedByName: false)
        let g = UninstallGroup(app: app("Alpha", "com.a.b", size: 100),
                               leftovers: [leftover, duplicate], running: false)
        XCTAssertEqual(UninstallPlan.totalBytes([g], selectedLeftovers: ["/L/x"]), 110)
    }

    func testTwoAppsSharingALeftoverTrashItOnce() {
        let shared = Leftover(path: "/L/shared", kind: .caches, sizeBytes: 5, matchedByName: false)
        let a = UninstallGroup(app: app("Alpha", "com.a"), leftovers: [shared], running: false)
        let b = UninstallGroup(app: app("Beta", "com.b"), leftovers: [shared], running: false)
        XCTAssertEqual(UninstallPlan.paths([a, b], selectedLeftovers: ["/L/shared"]),
                       ["/Applications/Alpha.app", "/L/shared", "/Applications/Beta.app"])
    }
}
