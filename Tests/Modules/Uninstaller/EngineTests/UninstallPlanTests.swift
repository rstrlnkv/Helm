import XCTest
@testable import Module_Uninstaller_Engine

private func app(_ name: String, _ id: String) -> InstalledApp {
    InstalledApp(name: name, bundleID: id, path: "/Applications/\(name).app")
}
private func leftover(_ path: String, _ size: Int) -> Leftover {
    Leftover(path: path, kind: .caches, sizeBytes: size, matchedByName: false)
}
private func group(_ name: String, running: Bool,
                   leftovers: [Leftover] = []) -> UninstallGroup {
    UninstallGroup(app: app(name, "com.test.\(name)"),
                   leftovers: leftovers, running: running)
}

/// The batch flow: pick several apps, review their files grouped per app, then
/// trash the selection. Running apps must not be removed silently.
final class UninstallPlanTests: XCTestCase {
    // MARK: - Paths and sizes

    func testPathsCoverTheAppBundleAndItsSelectedLeftovers() {
        let g = group("Alpha", running: false,
                      leftovers: [leftover("/L1", 10), leftover("/L2", 20)])
        let selected: Set<String> = ["/L1"]
        XCTAssertEqual(UninstallPlan.paths([g], selectedLeftovers: selected),
                       ["/Applications/Alpha.app", "/L1"])
    }

    func testEverySelectedAppContributesEvenWithoutLeftovers() {
        let groups = [group("Alpha", running: false),
                      group("Beta", running: false)]
        XCTAssertEqual(UninstallPlan.paths(groups, selectedLeftovers: []),
                       ["/Applications/Alpha.app", "/Applications/Beta.app"])
    }

    /// Prefix globs and exact paths can resolve to the same directory, and a
    /// second attempt would fail with "doesn't exist".
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

    func testTwoAppsSharingALeftoverTrashItOnce() {
        let shared = Leftover(path: "/L/shared", kind: .caches, sizeBytes: 5, matchedByName: false)
        let a = UninstallGroup(app: app("Alpha", "com.a"), leftovers: [shared], running: false)
        let b = UninstallGroup(app: app("Beta", "com.b"), leftovers: [shared], running: false)
        XCTAssertEqual(UninstallPlan.paths([a, b], selectedLeftovers: ["/L/shared"]),
                       ["/Applications/Alpha.app", "/L/shared", "/Applications/Beta.app"])
    }
}
