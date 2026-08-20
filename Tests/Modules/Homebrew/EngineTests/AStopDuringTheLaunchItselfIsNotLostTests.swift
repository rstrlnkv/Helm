import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **The other side of the window `AStopBeforeTheChildExistsTests` closes.**
///
/// That one is a press that lands *before* the launch, which the launch itself
/// now reads. This one lands after that reading and before the engine owns a
/// handle — while `runner.stream` is in flight, which for the real runner is a
/// `posix_spawn` and a pipe. `stop` finds `current` still nil, so it terminates
/// nothing; a moment later `adopt` is handed the very child the person asked to
/// end. Without the check there, the press is recorded, the page says
/// «Stopped», and `brew install` goes on running to completion.
///
/// It is milliseconds wide and it is not unreachable: `stop` arrives on the
/// transport from a button press, on a different thread from the one inside
/// `runOp`, and the two are not ordered by anything else.
///
/// **The fake presses the button from inside `stream`,** which is the only way
/// to be exactly there. A fake that merely returns a handle cannot represent
/// «the press landed during the spawn», so no test of this could exist however
/// carefully it was written.
final class AStopDuringTheLaunchItselfIsNotLostTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Records the SIGTERM without ending the stream — the real handle does not
    /// finish on `terminate` either: the child dies, then EOF, then `onExit`.
    private final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var _terminated = false
        var terminated: Bool { lock.lock(); defer { lock.unlock() }; return _terminated }
        func terminate() { lock.lock(); _terminated = true; lock.unlock() }
    }

    /// A runner that lets the test act *while the launch is happening*.
    private final class RunnerThatIsInterrupted: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _handles: [Handle] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        /// Called after the child exists and before the handle is handed back.
        var duringLaunch: (@Sendable () -> Void)?

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); lock.unlock()
            duringLaunch?()
            return handle
        }
    }

    func testAStopPressedWhileTheChildIsBeingLaunchedStillReachesIt() {
        let runner = RunnerThatIsInterrupted()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: LocalTransport(),
                                    marker: InMemoryOpMarker())
        runner.duringLaunch = { [weak engine] in engine?.stop() }

        engine.install(name: "wget", isCask: false)

        XCTAssertEqual(runner.handles.count, 1, "precondition: the child was launched")
        XCTAssertTrue(runner.handles[0].terminated, """
            Stop was pressed while the child was being launched and reached \
            nothing: `current` was still nil at the press, and the handle that \
            arrived a moment later was adopted as if nobody had asked
            """)
    }

    /// The control: a launch nobody interrupted keeps its child. Without it the
    /// assertion above holds on an engine that terminates everything it starts.
    func testAnUninterruptedLaunchKeepsItsChild() {
        let runner = RunnerThatIsInterrupted()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: LocalTransport(),
                                    marker: InMemoryOpMarker())

        engine.install(name: "wget", isCask: false)

        XCTAssertEqual(runner.handles.count, 1)
        XCTAssertFalse(runner.handles[0].terminated,
                       "nobody pressed Stop and the child was terminated anyway")
    }
}
