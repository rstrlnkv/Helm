import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// A long operation used to have exactly one exit: the child's own EOF. A brew
/// hung on the network, another brew's lock, or an installer waiting for input
/// meant the busy gate never released — the module was dead until the app
/// restarted, spinner running. Operations are not bounded by a clock (an
/// install may honestly take an hour); they are stopped by hand.
///
/// The runner must not answer on its own: a stream that exits synchronously
/// would finish before there is anything to stop.
final class ARunningOperationCanBeStoppedTests: XCTestCase {

    func testStopTerminatesTheChildAndNamesTheOutcome() async {
        let runner = HangingRunner()
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: news)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.handles.count, 1, "precondition: the operation started")

        engine.stop()
        XCTAssertTrue(runner.handles[0].terminated,
                      "Stop was pressed and the child brew was not terminated")

        runner.finishAll(code: 15)
        let state = await lastOpState(news)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .stopped,
                       "a stop the person asked for reported itself as an ordinary failure")

        // And the gate is released: the module lives on.
        engine.upgradeAll()
        XCTAssertEqual(runner.handles.count, 2, "the stopped operation left the gate shut")
    }

    /// An exit the person did not ask for keeps its own name: signal 15 from
    /// outside (a brew killed in a terminal) is a failure, not a stop.
    func testAnUnrequestedSignalDeathIsNotAStop() async {
        let runner = HangingRunner()
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: news)

        engine.install(name: "wget", isCask: false)
        runner.finishAll(code: 15)

        let state = await lastOpState(news)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertNil(state?.reason, "nobody pressed Stop, but the failure claims one")
    }

    /// Stopping nothing is a no-op, not a crash and not a stray event.
    func testStopWithNothingRunningIsHarmless() async {
        let runner = HangingRunner()
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: news)

        engine.stop()

        let state = await lastOpState(news)
        XCTAssertNil(state, "stop with nothing running invented an operation state")
    }

    /// A *later* stop must not reach back: the flag is cleared when the next
    /// operation starts, or one stop would rename every failure after it.
    func testTheStopFlagDoesNotOutliveItsOperation() async {
        let runner = HangingRunner()
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: news)

        engine.install(name: "wget", isCask: false)
        engine.stop()
        runner.finishAll(code: 15)

        engine.upgradeAll()
        runner.finishAll(code: 1)

        let state = await lastOpState(news)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertNil(state?.reason,
                     "the previous operation's stop renamed this one's honest failure")
    }
}
