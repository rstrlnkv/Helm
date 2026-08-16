import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// When a query cannot answer, the page keeps the answer it had. The view model
/// used to write `?? []` over every reply, so one hung `brew list` replaced a
/// real package list with an empty one — "No packages installed." over a full
/// Cellar, which is a lie about the machine.
@MainActor
final class ATimedOutQueryKeepsTheLastAnswerTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Answers like brew until told to hang the way the bounded runner reports
    /// a hang — the same call record, two states, because the real port can be
    /// in both.
    private final class FickleRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _timedOut = false
        var timedOut: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _timedOut }
            set { lock.lock(); _timedOut = newValue; lock.unlock() }
        }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            if timedOut { return (HelmProcess.timedOutStatus, "") }
            guard args.first == "list" else { return (0, "") }
            return args.contains("--formula") ? (0, "wget 1.25.0\n") : (0, "")
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    func testAListThatStopsAnsweringDoesNotEmptyThePage() async {
        let runner = FickleRunner()
        let transport = LocalTransport()
        // Held for the test's life: the engine wires the transport's handler
        // with `[weak self]`.
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)
        defer { _ = engine }
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        await model.refreshInstalled()
        XCTAssertEqual(model.installed.map(\.name), ["wget"],
                       "precondition: the first list arrived")
        XCTAssertTrue(model.loadedInstalled)

        runner.timedOut = true
        await model.refreshInstalled()

        XCTAssertEqual(model.installed.map(\.name), ["wget"], """
            a query that could not answer replaced the real list with an empty \
            one — the page said "No packages installed." over a full Cellar
            """)
    }
}
