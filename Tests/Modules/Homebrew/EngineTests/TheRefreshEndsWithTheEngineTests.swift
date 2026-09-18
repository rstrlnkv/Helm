import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// A store whose refresh takes long enough to still be running when the engine
/// goes, and which records whether it was cancelled.
///
/// One side of the boundary only: what is under test is the engine's lifecycle,
/// so this decides nothing of its own. The sleep is the whole mechanism — a
/// refresh that returns straight away is over before `deactivate()` is reached,
/// and a test built on one passes with every guard below deleted.
///
/// `try?` around the sleep, because cancellation is how it is *meant* to end:
/// `Task.sleep` throws `CancellationError`, and what is asserted afterwards is
/// `Task.isCancelled`, read inside the same task the engine started.
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

private struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}

private struct IdleRunner: ProcessRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

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

/// **The other half of the refresh's lifecycle, which nothing held.**
///
/// `ActivationIsWhatStartsTheRefreshTests` holds the line that *starts* the
/// fetch — its own doc comment records that deleting that line left the tree
/// green. Ending it was in the same position: emptying `cancelTheRefresh()`,
/// dropping the `deinit`, or giving the task in `activate()` a capture that
/// keeps the engine alive left every test in this tree passing.
/// `activate()`'s comment block argues for the capture list and the
/// under-the-lock assignment at length, and none of it was held by anything.
///
/// **What the capture half of that does and does not catch, measured.** Two
/// `[weak self]` shapes were planted here against these two cases.
/// `Task { [weak self] in await self?.popularity.refreshIfDue() }` passes both:
/// the optional chain resolves the weak reference, reads the port out of it and
/// lets the engine go before the call suspends, so `deinit` still runs.
/// `Task { [weak self] in await self?.someAsyncMethodOfTheEngine() }` — the
/// shape CLAUDE.md names, where the method holds `self` for as long as it runs
/// — fails the second case below at its five-second wait. So what is held here
/// is "the engine can be dropped while the fetch is in flight", which is the
/// property that matters; the capture list is protected only through it.
///
/// What that costs when it is wrong: a module the person switched off goes on
/// reaching `formulae.brew.sh` on its behalf, and an engine dropped by any
/// route that is not `deactivate()` leaves a fetch running that nothing can
/// stop.
///
/// Both cases are wall-clock waits and not cooperative yields: the refresh runs
/// on a task of its own, so a yield would buy a turn on the pool and no time at
/// all (CLAUDE.md § What not to do, and what breaks if you do). They complete in
/// milliseconds when cancellation works and time out when it does not.
final class TheRefreshEndsWithTheEngineTests: XCTestCase {

    private func engine(_ popularity: PopularityReading) -> HomebrewEngine {
        HomebrewEngine(locator: NoBrew(), runner: IdleRunner(),
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker(), popularity: popularity)
    }

    func testDeactivationCancelsARefreshStillRunning() {
        let spy = SleepySpy()
        let engine = self.engine(spy)

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
    /// The engine is dropped rather than deactivated, which is only survivable
    /// because nothing the task captures keeps the engine alive — a capture
    /// whose body then calls a method *on* the engine holds it for as long as
    /// the fetch runs, and this case times out.
    func testDroppingTheEngineCancelsARefreshStillRunning() {
        let spy = SleepySpy()
        var engine: HomebrewEngine? = self.engine(spy)

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
