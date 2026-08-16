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

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// A handle the way the real one is: terminating it does not finish the
    /// stream by itself — the child dies, *then* EOF and the exit arrive.
    private final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var _terminated = false
        var terminated: Bool { lock.lock(); defer { lock.unlock() }; return _terminated }
        func terminate() { lock.lock(); _terminated = true; lock.unlock() }
    }

    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); _exits.append(onExit); lock.unlock()
            return handle
        }
        /// The child is gone; the pipe closes; the exit lands. SIGTERM deaths
        /// report the signal number, which is what the engine must not read as
        /// a build failure once it asked for the stop itself.
        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    private func lastOpState(_ transport: LocalTransport) async -> OpState? {
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var last: OpState?
        for await event in transport.events {
            if event.name == "test.sentinel" { break }
            if event.name == HomebrewEvent.opState.rawValue {
                last = try? JSONDecoder().decode(OpState.self, from: event.payload)
            }
        }
        return last
    }

    func testStopTerminatesTheChildAndNamesTheOutcome() async {
        let runner = HangingRunner()
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.handles.count, 1, "precondition: the operation started")

        engine.stop()
        XCTAssertTrue(runner.handles[0].terminated,
                      "Stop was pressed and the child brew was not terminated")

        runner.exitAll(code: 15)
        let state = await lastOpState(transport)
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
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)

        engine.install(name: "wget", isCask: false)
        runner.exitAll(code: 15)

        let state = await lastOpState(transport)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertNil(state?.reason, "nobody pressed Stop, but the failure claims one")
    }

    /// Stopping nothing is a no-op, not a crash and not a stray event.
    func testStopWithNothingRunningIsHarmless() async {
        let runner = HangingRunner()
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)

        engine.stop()

        let state = await lastOpState(transport)
        XCTAssertNil(state, "stop with nothing running invented an operation state")
    }

    /// A *later* stop must not reach back: the flag is cleared when the next
    /// operation starts, or one stop would rename every failure after it.
    func testTheStopFlagDoesNotOutliveItsOperation() async {
        let runner = HangingRunner()
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)

        engine.install(name: "wget", isCask: false)
        engine.stop()
        runner.exitAll(code: 15)

        engine.upgradeAll()
        runner.exitAll(code: 1)

        let state = await lastOpState(transport)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertNil(state?.reason,
                     "the previous operation's stop renamed this one's honest failure")
    }
}
