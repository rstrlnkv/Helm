import XCTest
@testable import Module_Uninstaller_Engine

/// What the review shows about a batch: whether it may go ahead and how many
/// bytes it frees. Optional: the engine asks again at removal
/// (`TheAppIsAskedAgainAtRemovalTests`), so readiness only draws a warning and
/// the button's help, and a wrong total is a wrong figure, not lost data.
final class UninstallPlanFiguresTests: XCTestCase {
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

    // MARK: - Sizes

    func testSizeCountsTheBundlePlusSelectedLeftoversOnly() {
        let g = group("Alpha", running: false, appSize: 500,
                      leftovers: [leftover("/L1", 10), leftover("/L2", 20)])
        let alpha500 = ["/Applications/Alpha.app": 500]
        XCTAssertEqual(UninstallPlan.totalBytes([g], appBytes: alpha500, selectedLeftovers: ["/L1"]), 510)
        XCTAssertEqual(UninstallPlan.totalBytes([g], appBytes: alpha500, selectedLeftovers: ["/L1", "/L2"]), 530)
        XCTAssertEqual(UninstallPlan.totalBytes([g], appBytes: alpha500, selectedLeftovers: []), 500)
    }

    func testEverySelectedAppIsCounted() {
        let groups = [group("Alpha", running: false, appSize: 100),
                      group("Beta", running: false, appSize: 250)]
        XCTAssertEqual(UninstallPlan.totalBytes(groups, appBytes: ["/Applications/Alpha.app": 100,
                                                                    "/Applications/Beta.app": 250],
                                                     selectedLeftovers: []), 350)
    }

    func testSizeCountsADuplicatedPathOnce() {
        let leftover = Leftover(path: "/L/x", kind: .containers, sizeBytes: 10, matchedByName: false)
        let duplicate = Leftover(path: "/L/x", kind: .caches, sizeBytes: 10, matchedByName: false)
        let g = UninstallGroup(app: app("Alpha", "com.a.b", size: 100),
                               leftovers: [leftover, duplicate], running: false)
        XCTAssertEqual(UninstallPlan.totalBytes([g], appBytes: [g.app.path: 100],
                                                     selectedLeftovers: ["/L/x"]), 110)
    }
}
