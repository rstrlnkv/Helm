import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The whole path of a press on Stop: view model → wire → engine → the child's
/// handle. Driven over the real `LocalTransport`, because the command name
/// crosses a target boundary and only the trip proves the two sides agree.
@MainActor
final class TheStopButtonReachesTheChildTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    private final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var _terminated = false
        var terminated: Bool { lock.lock(); defer { lock.unlock() }; return _terminated }
        func terminate() { lock.lock(); _terminated = true; lock.unlock() }
    }

    /// Hangs, or the stop would race a stream already over.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _handles: [Handle] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); lock.unlock()
            return handle
        }
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<20_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "never reached: \(what)")
    }

    func testStopFromTheViewModelTerminatesTheChild() async {
        let runner = HangingRunner()
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)
        defer { _ = engine }
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        model.upgradeAll()
        await waitUntil("the operation was seen running") { model.op.phase == .running }
        await waitUntil("the stream started") { !runner.handles.isEmpty }

        model.stop()

        await waitUntil("the child was terminated") { runner.handles.first?.terminated == true }
    }

    /// The page offers the press: a stop nobody can reach is not a feature.
    /// Structural, the way `AnErasedQueryDoesNotShowOldResultsTests` pins its
    /// seam into the body.
    func testThePageWiresTheStopButton() throws {
        let page = RepoSource.root
            .appendingPathComponent("Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(source.contains("hb.stop()"),
                      "HomebrewSettingsPage offers no way to stop a running operation")
    }
}
