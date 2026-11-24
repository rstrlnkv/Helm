import HelmTestSupport
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The runner bounds a hung query (`AQueryRunnerHasADeadlineTests`), but a
/// timeout's empty stdout handed to a parser would become an empty list, and
/// the page would say "No packages installed." about a full Cellar.
///
/// A list query that timed out answers *nothing*, which this codebase
/// distinguishes from an empty answer: `nil` here, and the view model keeps the
/// list it had.
final class ATimedOutQueryIsANamedRefusalTests: XCTestCase {

    /// What `ShellProcessRunner` answers once its deadline has passed.
    private func timedOutRunner() -> ScriptedRunner {
        ScriptedRunner(answers: [BrewAnswer([], HelmProcess.timedOutStatus, "")])
    }

    func testAListThatTimedOutIsNotAnEmptyMachine() {
        XCTAssertNil(brewEngine(timedOutRunner()).listInstalled(),
                     "a hung brew list came back as \"no packages installed\"")
    }

    func testAnOutdatedCheckThatTimedOutIsNotAllCurrent() {
        XCTAssertNil(brewEngine(timedOutRunner()).outdated(),
                     "a hung brew outdated came back as \"everything is up to date\"")
    }

    func testASearchThatTimedOutIsNotNoResults() {
        XCTAssertNil(brewEngine(timedOutRunner()).search("wget"),
                     "a hung brew search came back as \"no results\"")
    }

    /// `describe` splits a failed batch in half and asks again — right for one
    /// bad name, catastrophic for a timeout: each half hangs for the same full
    /// deadline, so a fifty-name batch would park the queue for hours.
    func testATimedOutDescriptionsBatchIsNotSplitAndRetried() {
        let runner = timedOutRunner()
        _ = brewEngine(runner).descriptions(names: ["a", "b", "c", "d"], isCask: false)
        XCTAssertEqual(runner.queries.count, 1,
                       "a timed-out desc batch was split and re-asked: \(runner.queries.count) calls, "
                       + "each of which hangs for the whole deadline again")
    }

    /// The log is triaged for what happened to the answer: "keeping the last
    /// answer" is true of the installed list, and false of a search, which
    /// keeps nothing.
    func testTheLogSaysWhatWasKeptOnlyForTheQueriesThatKeepOne() {
        tailTheLog()
        let e = brewEngine(timedOutRunner())
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
        let e = brewEngine(timedOutRunner())
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
