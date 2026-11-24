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
/// `activate()`'s single `Task` is the only thing in the app that asks the
/// store to fetch. Without it a Mac that never cached the documents never
/// would, and search would keep brew's alphabetical order with nothing saying
/// why. A runtime test, because a scan for `refreshIfDue` would pass over a
/// task nobody started.
/// file would pass over a task nobody ever started.
final class ActivationIsWhatStartsTheRefreshTests: XCTestCase {

    /// A wall-clock wait and not a cooperative yield: the ask lands on a task
    /// of its own, so a yield would buy a turn on the pool and no time at all
    /// (Architecture/TestsAndMeasurement.md § Fakes).
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
