import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// **A tool's refusal is not an empty answer.**
///
/// A `brew` that exits non-zero with an empty stdout must answer nil, not a
/// parsed empty list the page draws as a fact about the machine:
///
///   * `listInstalled` → "No packages installed." over a full Cellar;
///   * `outdated` → "Everything is up to date." over held-back updates, and
///     «Updates: 0» in the status line.
///
/// `brew` exits non-zero when the trouble is about the tool: a broken tap, a
/// Ruby error, an unreadable Cellar, another brew holding the lock (which this
/// module reaches by itself, since a child brew survives the app). Its sentence
/// goes to stderr, which `HelmProcess` discards, so the exit code is all that is
/// left. Nil means "could not answer": the view model keeps its list and Refresh
/// stays live.
///
/// **`search` is excluded, and the last test says why.**
final class ARefusedQueryIsNotACleanMachineTests: XCTestCase {

    // MARK: - The installed list

    func testAListBrewRefusedIsNotAnEmptyMachine() {
        let runner = ScriptedRunner(answers: [BrewAnswer(["list"], 1, "")])
        let answer = brewEngine(runner).listInstalled()
        XCTAssertFalse(runner.queries.isEmpty, "precondition: brew was actually asked")
        XCTAssertNil(answer, """
            `brew list` exited 1 with nothing on stdout and the module answered \
            an empty list — the page says "No packages installed." about a \
            machine it never managed to read
            """)
    }

    /// Two children, and only the second refuses: the formulae must not be kept
    /// while every cask silently disappears, a list that looks complete.
    func testACaskListRefusedDoesNotSilentlyDropEveryCask() {
        let runner = ScriptedRunner(answers: [BrewAnswer(["list", "--formula"], 0, "wget 1.25.0\n"),
                                 BrewAnswer(["list", "--cask"], 1, "")])
        let answer = brewEngine(runner).listInstalled()
        XCTAssertEqual(runner.queries.count, 2, "precondition: both lists were asked for")
        XCTAssertNil(answer, """
            the cask half of the list was refused and the module answered with \
            the formulae alone — every installed app vanished from the page and \
            nothing anywhere says the question failed
            """)
    }

    /// The control: a machine with nothing installed is `brew` exiting **0**
    /// with no output, and that is still an answer.
    func testAMachineWithNothingInstalledStillAnswers() {
        let answer = brewEngine(ScriptedRunner(answers: [BrewAnswer(["list"], 0, "")])).listInstalled()
        XCTAssertNotNil(answer, "an honestly empty Cellar was reported as unreadable")
        XCTAssertEqual(answer?.count, 0)
    }

    /// A brew that vanished between the locator and the ask is no machine with
    /// nothing on it: each reading says it could not answer.
    func testAMissingBrewIsNotACleanMachine() {
        let runner = ScriptedRunner(answers: [])
        let e = HomebrewEngine(locator: NoBrew(), runner: runner,
                               privileged: NoPrivileges(), user: "tester",
                               news: EngineNews(), marker: InMemoryOpMarker())
        XCTAssertNil(e.listInstalled(), "a missing brew answered \"No packages installed.\"")
        XCTAssertNil(e.outdated(), "a missing brew answered an up-to-date machine")
        XCTAssertNil(e.search("wget"), "a missing brew answered \"no results\"")
        XCTAssertTrue(runner.queries.isEmpty, "brew was asked although it is missing")
    }

    // MARK: - The outdated list

    func testAnOutdatedCheckBrewRefusedIsNotAnUpToDateMachine() {
        let runner = ScriptedRunner(answers: [BrewAnswer(["outdated"], 1, "")])
        let answer = brewEngine(runner).outdated()
        XCTAssertFalse(runner.queries.isEmpty, "precondition: brew was actually asked")
        XCTAssertNil(answer, """
            `brew outdated` exited 1 and the module answered "nothing is \
            outdated" — the status line then says «Updates: 0» about a question \
            that was refused
            """)
    }

    /// **Every field of `--json=v2`'s root is optional, so any JSON object at
    /// all would decode to "nothing is outdated".** A newer brew that renames
    /// the arrays exits 0 and prints a readable document; the shape below is the
    /// same data under a hypothetical v3 name, and must not read as up to date.
    func testJSONFromANewerBrewIsNotAnUpToDateMachine() {
        let payload = """
        {"outdated":{"formulae":[{"name":"deno","installed_versions":["2.9.3"],\
        "current_version":"2.9.4"}],"casks":[]}}
        """
        let answer = brewEngine(ScriptedRunner(answers: [BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNil(answer, """
            a JSON shape this decoder does not know was read as an up-to-date \
            machine: neither `formulae` nor `casks` was present and the answer \
            was still a confident empty list
            """)
    }

    /// Bytes that stop mid-document, a child killed mid-write: `JSONDecoder`
    /// gives up on the whole document, and that is no empty list.
    func testATruncatedAnswerIsNotAnUpToDateMachine() {
        let payload = #"{"formulae":[{"name":"deno","installed_versions":["2.9.3"]"#
        let answer = brewEngine(ScriptedRunner(answers: [BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNil(answer, "a truncated JSON document was read as a machine with no updates")
    }

    /// The control: `{"formulae":[],"casks":[]}` is what brew prints when
    /// everything is current, and it stays an answer.
    func testAnHonestlyCurrentMachineStillAnswers() {
        let payload = #"{"formulae":[],"casks":[]}"#
        let answer = brewEngine(ScriptedRunner(answers: [BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNotNil(answer, "a genuinely up-to-date machine was reported as unreadable")
        XCTAssertEqual(answer?.count, 0)
    }

    // MARK: - Why search is not in this family

    /// Measured against a real brew:
    ///
    ///     $ brew search --formula -- zzqqxxnope ; echo $?
    ///     1                       ← and nothing on stdout
    ///
    /// For `search` a non-zero exit is brew's "no matches", and an empty list is
    /// the honest answer. The rule for the two above therefore cannot be «nil on
    /// any non-zero status».
    func testASearchThatFoundNothingIsStillAnAnswer() {
        let runner = ScriptedRunner(answers: [BrewAnswer(["search"], 1, "")])
        let answer = brewEngine(runner).search("zzqqxxnope")
        XCTAssertNotNil(answer, """
            brew spells "no matches" as exit 1 for `search`; the module now \
            reports it as a failure and the page keeps the previous query's hits
            """)
        XCTAssertEqual(answer?.count, 0)
    }
}
