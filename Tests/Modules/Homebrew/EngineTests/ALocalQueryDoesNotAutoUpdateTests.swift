import XCTest
@testable import Module_Homebrew_Engine

/// A query that reads the disk must not be allowed to change the machine.
///
/// `brew list --versions` and `brew desc` answer about what is already
/// installed: nothing they report depends on the catalogue being fresh. Left to
/// itself brew may refresh that catalogue first — on this Mac a cold
/// `brew outdated` was measured at 7.4 s against 0.3–0.6 s warm (helm.log,
/// 2026-08-15 16:09:35→42) — so a person pressing Refresh on a list of
/// installed packages could be made to wait on a download nobody asked for, on
/// a network that may not be there.
///
/// `outdated` and `search` are deliberately **not** in this test. They are
/// answers about the catalogue, and a stale catalogue makes «Updates: 0» a lie
/// about the machine. The gate is "does this query need the catalogue", not
/// "is this query slow".
private final class EnvironmentRecorder: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(args: [String], env: [String: String])] = []
    var calls: [(args: [String], env: [String: String])] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _calls.append((args, env)); lock.unlock()
        return (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.lock(); _calls.append((args, env)); lock.unlock()
        onExit(0)
        return NoProcess()
    }
}

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

final class ALocalQueryDoesNotAutoUpdateTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    func testListAndDescribeRefuseTheAutoUpdate() {
        let runner = EnvironmentRecorder()
        _ = engine(runner).listInstalled()
        XCTAssertFalse(runner.calls.isEmpty, "the query never ran")
        for call in runner.calls {
            XCTAssertEqual(call.env["HOMEBREW_NO_AUTO_UPDATE"], "1",
                           "\(call.args.first ?? "?") may refresh the catalogue it does not read")
        }
    }

    func testDescriptionsRefuseTheAutoUpdate() {
        let runner = EnvironmentRecorder()
        _ = engine(runner).descriptions(names: ["wget"], isCask: false)
        XCTAssertEqual(runner.calls.first?.env["HOMEBREW_NO_AUTO_UPDATE"], "1")
    }

    /// The control. These two are about the catalogue, and a catalogue nobody
    /// refreshes makes both of them answer confidently about a world that has
    /// moved. Without this half, "set it everywhere" passes the test above.
    func testOutdatedAndSearchStillRefreshTheCatalogue() {
        let runner = EnvironmentRecorder()
        let e = engine(runner)
        _ = e.outdated()
        _ = e.search("wget")
        XCTAssertFalse(runner.calls.isEmpty)
        for call in runner.calls {
            XCTAssertNil(call.env["HOMEBREW_NO_AUTO_UPDATE"],
                         "\(call.args.first ?? "?") would answer from a catalogue it refused to refresh")
        }
    }

    /// The console shows what the tool says, and brew's environment hints are
    /// several lines of advice about shells that have nothing to do with the
    /// install a person is watching.
    func testAnOperationSilencesTheEnvironmentHints() {
        let runner = EnvironmentRecorder()
        engine(runner).install(name: "wget", isCask: false)
        XCTAssertEqual(runner.calls.first?.env["HOMEBREW_NO_ENV_HINTS"], "1")
    }
}
