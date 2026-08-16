import Foundation
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// A phase names itself while it runs, not only after. The owner's log carried
/// `sample: 226 MB — no phases running` beside a Homebrew session, and the line
/// was right: the queries close their phases before their memory line prints,
/// and the operations had no phase at all — an `upgrade all` that ran 25 s was
/// invisible to every sample taken beside it.
///
/// The runner must hang: the phase's whole point is the interval *during*, and
/// a stream that exits synchronously has no during.
final class AnOperationNamesItselfWhileItRunsTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }
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

    private func phaseOpen() -> Bool {
        HelmActivity.running.contains { $0.label == "homebrew.operation" }
    }

    /// The registry is process-global and other suites abandon engines
    /// mid-operation on purpose (a quit is exactly that), so the label may
    /// arrive already open. Closed here, so the assertions below are about
    /// this test's engine and not about who ran first.
    override func setUp() {
        super.setUp()
        HelmActivity.end("homebrew.operation")
    }

    func testALongOperationIsARunningPhaseUntilItExits() {
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester")

        XCTAssertFalse(phaseOpen(), "precondition: no operation, no phase")
        engine.install(name: "wget", isCask: false)
        XCTAssertTrue(phaseOpen(),
                      "the operation is running and a memory sample taken now "
                      + "would still say \"no phases running\"")

        runner.finishAll(code: 0)
        XCTAssertFalse(phaseOpen(), "the operation ended and its phase did not")
    }

    /// A refusal before the stream starts must close what it opened — the
    /// account-name gate is the earliest way out of `installBrew`.
    func testARefusedInstallBrewLeavesNoPhaseOpen() {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: HangingRunner(),
                                    privileged: NoPrivileges(), user: "bad;name")
        engine.installBrew()
        XCTAssertFalse(phaseOpen(), "a refused installBrew left its phase running for ever")
    }
}
