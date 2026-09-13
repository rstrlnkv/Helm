import XCTest
@testable import Module_Homebrew_Engine

/// Three questions about one new query, and the middle one is the point.
///
/// `brew uses` takes a **formula**. Handed a cask name it does not fail — it
/// exits 0 and says `Warning: No available formula with the name "firefox"` on
/// stderr, which the runner drops (measured 2026-09-13). So a cask asked this
/// question comes back as a confident empty list after paying half a second for
/// a tool run that could never have answered. Nothing depends on a cask, so the
/// answer is known without asking, and the tool is not run at all.
///
/// The third question is the one this codebase always asks of a query: brew
/// refusing must not read as a clean machine. A refusal here means the dialog
/// cannot promise that nothing breaks, and `nil` is how it says so.
private final class UsesRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    var status: Int32 = 0
    var stdout = ""

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _calls.append(args); lock.unlock()
        return (status, stdout)
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

/// Homebrew is not installed, or was uninstalled in a terminal beside this
/// window — `FSBrewLocator` re-reads the disk at every call, so this is an
/// ordinary answer and not a broken fixture.
private struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

final class ACaskIsNeverAskedWhatUsesItTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    func testAFormulaIsAskedWithItsNameBehindADoubleDash() {
        let runner = UsesRunner()
        runner.stdout = "aria2\nnode\n"
        let answer = engine(runner).dependents(name: "openssl@3", isCask: false)
        XCTAssertEqual(answer, ["aria2", "node"])
        XCTAssertEqual(runner.calls.first, ["uses", "--installed", "--", "openssl@3"])
    }

    func testACaskCostsNoToolRun() {
        let runner = UsesRunner()
        let answer = engine(runner).dependents(name: "firefox", isCask: true)
        XCTAssertEqual(answer, [])
        XCTAssertTrue(runner.calls.isEmpty, "a cask was asked a question about formulae")
    }

    func testARefusalIsNotALeaf() {
        let runner = UsesRunner()
        runner.status = 1
        XCTAssertNil(engine(runner).dependents(name: "openssl@3", isCask: false),
                     "brew refusing must not read as «nothing depends on it»")
    }

    /// The same sentence one step earlier. A `brew` that is not there is the
    /// purest case of a query that never ran, and the empty list it used to
    /// answer with is the dialog promising nothing depends on this package on
    /// the strength of a tool nobody could launch.
    ///
    /// A cask stays `[]` beside it — that answer is *known*, not measured, which
    /// is the distinction the two halves of this case draw.
    func testAMissingBrewIsAQueryThatNeverRan() {
        let runner = UsesRunner()
        let engine = HomebrewEngine(locator: NoBrew(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        XCTAssertNil(engine.dependents(name: "openssl@3", isCask: false),
                     "no brew to ask read as «nothing depends on it»")
        XCTAssertEqual(engine.dependents(name: "firefox", isCask: true), [],
                       "nothing depends on a cask, and that is known without a brew")
        XCTAssertTrue(runner.calls.isEmpty, "a tool was launched with no brew to launch")
    }
}
