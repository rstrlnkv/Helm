import XCTest
import HelmContract
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// A failed operation is not a no-op on the machine. `brew upgrade` with no
/// subject walks the outdated list package by package and exits non-zero when
/// *one* of them fails to build — everything before it is already upgraded.
/// `refreshAfterOp` runs only on `phase == .done` (`HomebrewViewModel.swift`,
/// `handle`), so after a failure the page keeps the pre-operation lists: rows
/// offering to upgrade packages that are already current, an installed list
/// with versions that are no longer on disk.
///
/// This test FAILS against the current view model, deliberately: after a
/// `.failed` state the lists must be re-asked, exactly as they are after
/// `.done`. It drives the real engine over the real `LocalTransport`, so the
/// re-ask is measured where it lands — the runner's own call record.
@MainActor
final class AFailedOperationRefreshesTheListsTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Queries answer instantly and are counted; the long operation hangs
    /// until the test fails it — a stream that exited synchronously would
    /// finish before the view model ever saw `.running`.
    private final class SplitRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _queryCalls: [[String]] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        var queryCalls: [[String]] { lock.lock(); defer { lock.unlock() }; return _queryCalls }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            lock.lock(); _queryCalls.append(args); lock.unlock()
            return (0, "")
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _exits.append(onExit); lock.unlock()
            return NoProcess()
        }
        func failAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    /// Yields until `condition` holds, bounded so a red run reports instead of
    /// hanging the suite.
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<20_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "never reached: \(what)")
    }

    /// And the other direction: yields until `value()` has stopped changing,
    /// so "no refresh ever comes" is read off a settled system rather than a
    /// racing one.
    private func settle(_ value: () -> Int) async {
        var last = -1
        var stable = 0
        while stable < 200 {
            await Task.yield()
            let now = value()
            if now == last { stable += 1 } else { stable = 0 }
            last = now
        }
    }

    func testAFailedUpgradeAllReasksTheListsItMayHaveChanged() async {
        let runner = SplitRunner()
        let transport = LocalTransport()
        // Held for the test's life: the engine wires the transport's handler
        // with `[weak self]`.
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport)
        defer { _ = engine }
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        // The subject happens: the operation starts, is seen running, and
        // fails the way a mid-list build failure fails — exit 1 after some
        // packages were already upgraded.
        model.upgradeAll()
        await waitUntil("the operation was seen running") { model.op.phase == .running }
        let asked = runner.queryCalls.count
        runner.failAll(code: 1)
        await waitUntil("the failure reached the page") { model.op.phase == .failed }

        await settle { runner.queryCalls.count }
        XCTAssertGreaterThan(runner.queryCalls.count, asked, """
            A failed `brew upgrade` changed nothing on the page: refreshAfterOp \
            runs only on .done (HomebrewViewModel.handle), so the lists shown \
            are the ones from before the operation — including upgrades it \
            already applied before the one that failed.
            """)
    }
}
