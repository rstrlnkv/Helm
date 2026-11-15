import HelmTestSupport
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The runner bounds a hung query now (`AQueryRunnerHasADeadlineTests`), but a
/// deadline alone only moves the lie: every query used to hand whatever came
/// back to a parser, so a timeout — empty stdout — became an empty list, and
/// the page said "No packages installed." about a machine with 54 of them.
///
/// A list query that timed out answers *nothing*, which this codebase
/// distinguishes from an empty answer: `nil` here, and the view model keeps the
/// list it had.
/// Kept: guards the defect fixed in 882fe986 fix(homebrew): the batch — a hang has a deadline, a press has an answer, a phase has a name.
final class ATimedOutQueryIsANamedRefusalTests: XCTestCase {

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
        /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
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

    /// The log is triaged for what happened to the answer: "keeping the last
    /// answer" is true of the installed list, and false of a search, which
    /// keeps nothing.
    func testTheLogSaysWhatWasKeptOnlyForTheQueriesThatKeepOne() {
        tailTheLog()
        let e = engine(TimedOutRunner())
        _ = e.search("wget")
        _ = e.listInstalled()
        let lines = loggedLines("homebrew")
        XCTAssertTrue(lines.contains { $0.hasPrefix("search formulae timed out") && $0.hasSuffix("no answer") },
                      "a search that keeps nothing was logged otherwise: \(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("list formulae timed out") && $0.hasSuffix("keeping the last answer") },
                      "the installed list was not logged as kept: \(lines)")
    }

    /// The list of queries that keep their last answer is guarded line by line:
    /// each of `outdated`, `config` and `descriptions` is named here, so taking
    /// one out of `HomebrewEngine.outcome(of:)` turns this red.
    func testOutdatedConfigAndDescriptionsAreLoggedAsKept() {
        tailTheLog()
        let e = engine(TimedOutRunner())
        _ = e.outdated()
        _ = e.config()
        _ = e.descriptions(names: ["a"], isCask: false)
        let lines = loggedLines("homebrew")
        for query in ["outdated", "config", "descriptions"] {
            XCTAssertTrue(lines.contains { $0.hasPrefix("\(query) timed out") && $0.hasSuffix("keeping the last answer") },
                          "\(query) was not logged as keeping the last answer: \(lines)")
        }
    }
}
