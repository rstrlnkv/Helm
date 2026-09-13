import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// A store that answers nothing and records that it was asked to refresh.
///
/// One side of the boundary only: what is under test is the engine's
/// activation, so this stands for the store and decides nothing of its own.
private final class RefreshSpy: PopularityReading, @unchecked Sendable {
    let asked = XCTestExpectation(description: "the engine asked the store to refresh")
    func readings() -> PopularityReadings { .none }
    func refreshIfDue() async { asked.fulfill() }
}

private struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}

private struct IdleRunner: ProcessRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

/// **The one line that makes the whole feature run, held by a test.**
///
/// Two other guards stand either side of this one and neither can see it.
/// `TheLiveCountsReachTheEngineTests` reads `HomebrewDescriptor` as text and
/// proves the live store is the one handed to the engine;
/// `ASearchRanksByPopularityWhenItHasItTests` proves a reading that is already
/// in the store reaches the ranking. Between them sits `activate()`'s single
/// `Task`, which is the only thing anywhere in the app that ever asks the store
/// to fetch — and deleting that line left every test in the tree green. A Mac
/// that had never cached the documents would then never cache them, search
/// would go on drawing brew's alphabetical order, and nothing would say why.
///
/// It has to be a runtime test rather than a third text scan: what is being
/// asserted is that the ask *happens*, and a scan for `refreshIfDue` in the
/// file would pass over a task nobody ever started.
final class ActivationIsWhatStartsTheRefreshTests: XCTestCase {

    private func engine(_ popularity: PopularityReading) -> HomebrewEngine {
        HomebrewEngine(locator: NoBrew(), runner: IdleRunner(),
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker(), popularity: popularity)
    }

    /// A wall-clock wait and not a cooperative yield: the ask lands on a task
    /// of its own, so a yield would buy a turn on the pool and no time at all
    /// (CLAUDE.md § What not to do, and what breaks if you do).
    func testActivationAsksTheStoreToRefresh() {
        let spy = RefreshSpy()
        // Held for the length of the wait: `deinit` cancels the refresh, so an
        // engine let go of here would be racing its own task.
        let engine = self.engine(spy)

        engine.activate()

        XCTAssertEqual(XCTWaiter.wait(for: [spy.asked], timeout: 5), .completed,
                       "activate() never asked the store to refresh, so nothing in this app "
                       + "ever fetches the install counts — the module ships inert with every "
                       + "other test green")
        engine.deactivate()
    }
}
