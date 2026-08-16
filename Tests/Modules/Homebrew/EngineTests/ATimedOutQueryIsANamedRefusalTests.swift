import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The runner bounds a hung query now (`AQueryRunnerHasADeadlineTests`), but a
/// deadline alone only moves the lie: every query used to hand whatever came
/// back to a parser, so a timeout — empty stdout — became an empty list, and
/// the page said "No packages installed." about a machine with 54 of them.
///
/// A query that timed out answers *nothing*, which this codebase distinguishes
/// from an empty answer: `nil` here, zero bytes on the wire, and the view model
/// keeps the last answer it had.
final class ATimedOutQueryIsANamedRefusalTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// What `ShellProcessRunner` answers once its deadline has passed.
    private final class TimedOutRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            lock.lock(); _calls.append(args); lock.unlock()
            return (HelmProcess.timedOutStatus, "")
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester")
    }

    func testAListThatTimedOutIsNotAnEmptyMachine() {
        XCTAssertNil(engine(TimedOutRunner()).listInstalled(),
                     "a hung brew list came back as \"no packages installed\"")
    }

    func testAnOutdatedCheckThatTimedOutIsNotAllCurrent() {
        XCTAssertNil(engine(TimedOutRunner()).outdated(),
                     "a hung brew outdated came back as \"everything is up to date\"")
    }

    func testASearchThatTimedOutIsNotNoResults() {
        XCTAssertNil(engine(TimedOutRunner()).search("wget"),
                     "a hung brew search came back as \"no results\"")
    }

    /// `describe` splits a failed batch in half and asks again — right for one
    /// bad name, catastrophic for a timeout: each half hangs for the same full
    /// deadline, so a fifty-name batch would park the queue for hours.
    func testATimedOutDescriptionsBatchIsNotSplitAndRetried() {
        let runner = TimedOutRunner()
        _ = engine(runner).descriptions(names: ["a", "b", "c", "d"], isCask: false)
        XCTAssertEqual(runner.calls.count, 1,
                       "a timed-out desc batch was split and re-asked: \(runner.calls.count) calls, "
                       + "each of which hangs for the whole deadline again")
    }
}
