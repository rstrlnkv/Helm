import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// A child brew survives Helm: quit the app mid-`upgrade all` and the install
/// carries on with no observer — at the next launch the page looked calm while
/// the Cellar had changed underneath it. Killing the child at quit would be
/// worse (a build interrupted halfway is how broken Cellar state is made), so
/// the engine *knows and says*: the running operation leaves a marker, a clean
/// exit removes it, and the next launch's first `status()` reports what was
/// left behind — once.
final class AQuitMidOperationIsReportedTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Never finishes unless told to — a quit happens *during* an operation.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _exits: [@Sendable (Int32) -> Void] = []
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _exits.append(onExit); lock.unlock()
            return NoProcess()
        }
        func finishAll(code: Int32 = 0) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    private func engine(_ runner: ProcessRunner, marker: OpMarker) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester", marker: marker)
    }

    func testAQuitMidOperationIsReportedAtTheNextLaunchOnce() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))

        // Launch one: the operation starts and the app "quits" — the engine is
        // simply gone, the way a process is.
        let before = engine(HangingRunner(), marker: marker)
        before.upgradeAll()

        // Launch two.
        let after = engine(HangingRunner(), marker: marker)
        XCTAssertEqual(after.status().interruptedOp, "upgrade all",
                       "the operation Helm quit under was never reported")
        XCTAssertNil(after.status().interruptedOp,
                     "the report must be made once, not on every status query")
    }

    func testAFinishedOperationLeavesNothingToReport() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let runner = HangingRunner()
        let before = engine(runner, marker: marker)
        before.upgradeAll()
        runner.finishAll(code: 0)

        let after = engine(HangingRunner(), marker: marker)
        XCTAssertNil(after.status().interruptedOp,
                     "a clean exit left its marker behind — every launch would report a ghost")
    }

    /// A failure is an exit too: the person saw it fail on screen, and the next
    /// launch has nothing new to say about it.
    func testAFailedOperationLeavesNothingToReport() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let runner = HangingRunner()
        let before = engine(runner, marker: marker)
        before.upgradeAll()
        runner.finishAll(code: 1)

        let after = engine(HangingRunner(), marker: marker)
        XCTAssertNil(after.status().interruptedOp)
    }

    /// The session's own status queries must not eat the marker while the
    /// operation is still running — the page refreshes its status freely, and
    /// the marker exists for the launch after this one.
    func testAStatusQueryDuringTheOperationDoesNotEatTheMarker() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let running = engine(HangingRunner(), marker: marker)
        running.upgradeAll()

        XCTAssertNil(running.status().interruptedOp,
                     "a running operation reported itself as an interrupted one")

        let after = engine(HangingRunner(), marker: marker)
        XCTAssertEqual(after.status().interruptedOp, "upgrade all",
                       "the mid-operation status query above consumed the marker")
    }
}
