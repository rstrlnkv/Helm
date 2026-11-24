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

/// **The one line that makes the whole feature run, held by a test.**
///
/// `activate()`'s single `Task` is the only thing anywhere in the app that ever
/// asks the store to fetch — and deleting that line left every test in the tree
/// green. A Mac that had never cached the documents would then never cache them,
/// search would go on drawing brew's alphabetical order, and nothing would say
/// why.
///
/// It has to be a runtime test rather than another text scan: what is being
/// asserted is that the ask *happens*, and a scan for `refreshIfDue` in the
/// file would pass over a task nobody ever started.
final class ActivationIsWhatStartsTheRefreshTests: XCTestCase {

    /// A wall-clock wait and not a cooperative yield: the ask lands on a task
    /// of its own, so a yield would buy a turn on the pool and no time at all
    /// (ARCHITECTURE.md § Fakes).
    func testActivationAsksTheStoreToRefresh() {
        let spy = RefreshSpy()
        // Held for the length of the wait: `deinit` cancels the refresh, so an
        // engine let go of here would be racing its own task.
        let engine = brewEngine(ScriptedRunner(), locator: NoBrew(), popularity: spy)

        engine.activate()

        XCTAssertEqual(XCTWaiter.wait(for: [spy.asked], timeout: 5), .completed,
                       "activate() never asked the store to refresh, so nothing in this app "
                       + "ever fetches the install counts — the module ships inert with every "
                       + "other test green")
        engine.deactivate()
    }

    /// And only activation: `init` runs for every module the host knows about, and
    /// a module the person has turned off must never reach the network. An engine
    /// that is built and never activated stays silent for the length of the wait.
    func testAnEngineThatIsNeverActivatedNeverAsks() {
        let spy = RefreshSpy()
        spy.asked.isInverted = true
        let engine = brewEngine(ScriptedRunner(), locator: NoBrew(), popularity: spy)

        XCTAssertEqual(XCTWaiter.wait(for: [spy.asked], timeout: 1), .completed,
                       "an engine nobody activated asked the store to refresh, so a module "
                       + "that is switched off still fetches the install counts")
        withExtendedLifetime(engine) {}
    }
}
