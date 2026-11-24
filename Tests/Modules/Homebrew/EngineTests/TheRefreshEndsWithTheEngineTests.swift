import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// A store whose refresh takes long enough to still be running when the engine
/// goes, and which records whether it was cancelled.
///
/// The sleep is the whole mechanism: a refresh that returns at once is over
/// before `deactivate()` is reached, and a test on it passes with every guard
/// deleted. `try?` around the sleep, because cancellation is how it is *meant*
/// to end; what is asserted is `Task.isCancelled`, read inside the task the
/// engine started.
private final class SleepySpy: PopularityReading, @unchecked Sendable {
    let began = XCTestExpectation(description: "the refresh began")
    let ended = XCTestExpectation(description: "the refresh came back")

    private let lock = NSLock()
    private var cancelled = false
    var sawCancellation: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    /// Synchronous, because a lock may not be taken in an asynchronous context.
    private func record(_ value: Bool) { lock.lock(); cancelled = value; lock.unlock() }

    func readings() -> PopularityReadings { .none }

    func refreshIfDue() async {
        began.fulfill()
        // Far longer than the waits below: the only thing that can end this
        // inside the test is a cancellation.
        try? await Task.sleep(for: .seconds(30))
        record(Task.isCancelled)
        ended.fulfill()
    }
}

/// **The refresh `activate()` starts ends with the engine**, by
/// `deactivate()` or, on any other route, by the `deinit`. Otherwise a module
/// the person switched off goes on reaching `formulae.brew.sh`, and a dropped
/// engine leaves a fetch nothing can stop.
///
/// What is held is "the engine can be dropped while the fetch is in flight";
/// the capture list in `activate()` is protected only through it. A
/// `[weak self]` body that calls a method *on* the engine holds it for as long
/// as the fetch runs and fails the second case
/// (Architecture/StateAndLifetime.md § State that outlives a page and ends with its module).
/// `self?.popularity.refreshIfDue()` reads the port out and lets the engine go,
/// so it passes.
///
/// Both cases are wall-clock waits: the refresh runs on a task of its own, so a
/// yield buys no time (Architecture/TestsAndMeasurement.md § Fakes). They
/// complete in milliseconds when cancellation works.
final class TheRefreshEndsWithTheEngineTests: XCTestCase {

    func testDeactivationCancelsARefreshStillRunning() {
        let spy = SleepySpy()
        let engine = brewEngine(ScriptedRunner(), locator: NoBrew(), popularity: spy)

        engine.activate()
        XCTAssertEqual(XCTWaiter.wait(for: [spy.began], timeout: 5), .completed,
                       "the refresh never started, so this case would pass with the "
                       + "cancellation deleted")

        engine.deactivate()

        XCTAssertEqual(XCTWaiter.wait(for: [spy.ended], timeout: 5), .completed,
                       "deactivate() left the refresh running — a module the person has "
                       + "switched off goes on fetching from formulae.brew.sh, and the app "
                       + "carries the task to the end of the process")
        XCTAssertTrue(spy.sawCancellation,
                      "the refresh came back without ever being cancelled, so what ended it "
                      + "was not deactivate()")
    }

    /// The `deinit` backstop: the routes that never reach `deactivate()`.
    ///
    /// The engine is dropped rather than deactivated, which works only because
    /// nothing the task captures keeps the engine alive.
    func testDroppingTheEngineCancelsARefreshStillRunning() {
        let spy = SleepySpy()
        var engine: HomebrewEngine? = brewEngine(ScriptedRunner(), locator: NoBrew(), popularity: spy)

        engine?.activate()
        XCTAssertEqual(XCTWaiter.wait(for: [spy.began], timeout: 5), .completed,
                       "the refresh never started, so this case would pass with the "
                       + "cancellation deleted")

        engine = nil

        XCTAssertEqual(XCTWaiter.wait(for: [spy.ended], timeout: 5), .completed,
                       "an engine let go of without deactivate() left its refresh running, "
                       + "with nothing anywhere still holding the task to cancel it")
        XCTAssertTrue(spy.sawCancellation,
                      "the refresh came back without ever being cancelled, so what ended it "
                      + "was not the engine's deinit")
    }
}
