import Foundation
import XCTest
@testable import Module_Homebrew_Engine

/// One long operation at a time — the engine's own first sentence, and nothing
/// held it.
///
/// `beginBusy`/`endBusy` guard every `brew install`, `uninstall`, `upgrade` and
/// `upgrade all` behind one flag, and the module's doc comment opens by
/// promising it. The refusal is quiet by design: the second press writes a line
/// to the console and returns, so a broken flag does not throw, does not fail a
/// build, and does not look like anything on screen — it runs two `brew`
/// processes against one prefix, which is the state Homebrew's own lock exists
/// to prevent.
///
/// **The runner has to be one that does not answer.** With a fake that calls
/// `onExit` synchronously, the flag is released before the first call returns
/// and a second one is admitted correctly — so a test built on such a fake
/// passes whether the guard exists or not. `HangingRunner` never exits, which
/// is what a real `brew install` looks like for the seconds that matter.
final class OneOperationAtATimeTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Records what it was asked to run and never finishes it, until a test
    /// says so.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        private var _exits: [@Sendable (Int32) -> Void] = []

        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            (0, "")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) {
            lock.lock(); _calls.append(args); _exits.append(onExit); lock.unlock()
        }

        /// Lets the operation that is in flight finish, the way a `brew` that
        /// has run to completion would.
        func finishAll(code: Int32 = 0) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester")
    }

    func testASecondOperationIsRefusedWhileTheFirstIsStillRunning() {
        let runner = HangingRunner()
        let engine = engine(runner)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.calls.count, 1, "precondition: the first operation started")

        engine.uninstall(name: "jq", isCask: false)

        XCTAssertEqual(runner.calls.count, 1,
                       "a second brew ran against the same prefix while the first was "
                       + "still going: \(runner.calls)")
    }

    /// Every verb goes through the same gate, so none of them may be the one
    /// that slips past a running operation.
    func testEveryLongOperationRespectsTheGate() {
        for second in ["install", "uninstall", "upgrade", "upgradeAll"] {
            let runner = HangingRunner()
            let engine = engine(runner)
            engine.install(name: "wget", isCask: false)

            switch second {
            case "install": engine.install(name: "jq", isCask: true)
            case "uninstall": engine.uninstall(name: "jq", isCask: false)
            case "upgrade": engine.upgrade(name: "jq")
            default: engine.upgradeAll()
            }

            XCTAssertEqual(runner.calls.count, 1, "\(second) ran beside a live operation")
        }
    }

    /// The other half: the flag is *released*. A guard that never lets go is a
    /// module that works once per launch, and it would pass the test above.
    func testTheNextOperationIsAdmittedOnceTheFirstHasFinished() {
        let runner = HangingRunner()
        let engine = engine(runner)

        engine.install(name: "wget", isCask: false)
        runner.finishAll()
        engine.uninstall(name: "jq", isCask: false)

        XCTAssertEqual(runner.calls.count, 2,
                       "the operation ended and the gate stayed shut: \(runner.calls)")
    }

    /// And a failure releases it too. `endBusy` runs before the exit code is
    /// looked at, so a `brew` that exits non-zero must not wedge the module.
    func testAFailedOperationAlsoReleasesTheGate() {
        let runner = HangingRunner()
        let engine = engine(runner)

        engine.install(name: "wget", isCask: false)
        runner.finishAll(code: 1)
        engine.upgradeAll()

        XCTAssertEqual(runner.calls.count, 2, "a failed operation left the gate shut")
    }
}
