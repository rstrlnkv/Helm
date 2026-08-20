import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A tool's refusal read as a success.**
///
/// `ATimedOutQueryIsANamedRefusalTests` pinned one way a query can fail to
/// answer — the runner's own deadline — and the engine handles that one: the
/// status is compared against `HelmProcess.timedOutStatus` and the query
/// answers nil. It is the *only* status the query path looks at. Every other
/// exit code is dropped on the floor and whatever came back on stdout is handed
/// to a parser, so a `brew` that refused with an empty stdout becomes an empty
/// list, which the page draws as a fact about the machine:
///
///   * `listInstalled` → "No packages installed." over a full Cellar;
///   * `outdated` → "Everything is up to date." over thirty held-back updates,
///     and «Updates: 0» in the status line.
///
/// A refusal is not hypothetical: `brew` exits non-zero whenever the trouble is
/// about the tool rather than about the question — a broken tap, a Ruby error, a
/// Cellar it cannot read, another brew holding the lock, which is a state this
/// module reaches by *itself* since a child brew survives the app
/// (`AQuitMidOperationIsReportedTests`). Those causes are named from what brew
/// documents, not measured here; what *was* measured on this Mac is in the last
/// test. Either way the sentence explaining a refusal goes to stderr, and
/// `HelmProcess` sends stderr to `nullDevice` — so the exit code is the only
/// thing left that knows anything went wrong.
///
/// The module already has a word for "could not answer" and it is nil: zero
/// bytes on the wire, the view model keeps its last answer, Refresh stays live
/// (`ATimedOutQueryKeepsTheLastAnswerTests`). These tests ask for that word
/// where today there is a confident empty list.
///
/// **`search` is deliberately excluded, and the last test says why.** Measured
/// against the Homebrew on this Mac (6.0.18): `brew search --formula -- <no
/// match>` exits **1** with empty stdout — a non-zero exit is how brew spells
/// "nothing found" for that one subcommand, so nil-ing every non-zero exit
/// would turn every fruitless search into "the module could not answer".
/// One canned answer: the words an argument list must contain for this answer
/// to be the one, and the `(status, stdout)` brew would have replied with.
private struct BrewAnswer {
    let match: [String]
    let status: Int32
    let stdout: String
    init(_ match: [String], _ status: Int32, _ stdout: String) {
        self.match = match; self.status = status; self.stdout = stdout
    }
}

final class ARefusedQueryIsNotACleanMachineTests: XCTestCase {

    // MARK: - Fakes

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// A brew that answers a canned `(status, stdout)` per subcommand — and can
    /// answer *differently per call*, because the real one does: `listInstalled`
    /// runs `list --formula` and `list --cask` as two children, and a refusal
    /// that lands on the second only is the half-applied state a fake keyed by
    /// subcommand alone could not represent.
    ///
    /// Both `run` and `runData` are implemented rather than leaning on the
    /// protocol's converting default: the real port has two independent bodies
    /// (`ShellProcessRunner.run` and `.runData`), and `outdated` is the caller
    /// that takes the second one.
    private final class CannedBrew: ProcessRunner, @unchecked Sendable {
        /// Keyed by a word the argument list has to contain, first match wins.
        private let answers: [BrewAnswer]
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

        init(_ answers: [BrewAnswer]) { self.answers = answers }

        private func answer(_ args: [String]) -> (Int32, String) {
            lock.lock(); _calls.append(args); lock.unlock()
            for a in answers where a.match.allSatisfy(args.contains) {
                return (a.status, a.stdout)
            }
            return (0, "")
        }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            answer(args)
        }

        func runData(_ launchPath: String, _ args: [String],
                     env: [String: String]) -> (status: Int32, stdout: Data) {
            let (status, out) = answer(args)
            return (status, Data(out.utf8))
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            NoProcess()
        }
    }

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        // Every port named, including the marker: a forgetful construction that
        // took a real one would be an integration test against this Mac.
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       transport: LocalTransport(), marker: InMemoryOpMarker())
    }

    // MARK: - The installed list

    func testAListBrewRefusedIsNotAnEmptyMachine() {
        let runner = CannedBrew([BrewAnswer(["list"], 1, "")])
        let answer = engine(runner).listInstalled()
        XCTAssertFalse(runner.calls.isEmpty, "precondition: brew was actually asked")
        XCTAssertNil(answer, """
            `brew list` exited 1 with nothing on stdout and the module answered \
            an empty list — the page says "No packages installed." about a \
            machine it never managed to read
            """)
    }

    /// The half that is easy to miss: two children, and only the second one
    /// refuses. Today the formulae are kept and every cask silently disappears
    /// from the page — a worse answer than nothing, because it looks complete.
    func testACaskListRefusedDoesNotSilentlyDropEveryCask() {
        let runner = CannedBrew([BrewAnswer(["list", "--formula"], 0, "wget 1.25.0\n"),
                                 BrewAnswer(["list", "--cask"], 1, "")])
        let answer = engine(runner).listInstalled()
        XCTAssertEqual(runner.calls.count, 2, "precondition: both lists were asked for")
        XCTAssertNil(answer, """
            the cask half of the list was refused and the module answered with \
            the formulae alone — every installed app vanished from the page and \
            nothing anywhere says the question failed
            """)
    }

    /// The control that keeps the fix honest: a machine with nothing installed
    /// is `brew` exiting **0** with no output, and that is still an answer.
    func testAMachineWithNothingInstalledStillAnswers() {
        let answer = engine(CannedBrew([BrewAnswer(["list"], 0, "")])).listInstalled()
        XCTAssertNotNil(answer, "an honestly empty Cellar was reported as unreadable")
        XCTAssertEqual(answer?.count, 0)
    }

    // MARK: - The outdated list

    func testAnOutdatedCheckBrewRefusedIsNotAnUpToDateMachine() {
        let runner = CannedBrew([BrewAnswer(["outdated"], 1, "")])
        let answer = engine(runner).outdated()
        XCTAssertFalse(runner.calls.isEmpty, "precondition: brew was actually asked")
        XCTAssertNil(answer, """
            `brew outdated` exited 1 and the module answered "nothing is \
            outdated" — the status line then says «Updates: 0» about a question \
            that was refused
            """)
    }

    /// **Every field of `--json=v2`'s root is optional, so any JSON object at
    /// all decodes to "nothing is outdated".** A newer brew that renames or
    /// re-nests the arrays exits 0, prints a document this decoder reads
    /// perfectly, and the module reports a machine with no updates for ever —
    /// no throw, no log, nothing to notice. The shape below is the same data
    /// under a name from a hypothetical v3; what matters is that it carries
    /// outdated packages and this parser sees none.
    func testJSONFromANewerBrewIsNotAnUpToDateMachine() {
        let payload = """
        {"outdated":{"formulae":[{"name":"deno","installed_versions":["2.9.3"],\
        "current_version":"2.9.4"}],"casks":[]}}
        """
        let answer = engine(CannedBrew([BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNil(answer, """
            a JSON shape this decoder does not know was read as an up-to-date \
            machine: neither `formulae` nor `casks` was present and the answer \
            was still a confident empty list
            """)
    }

    /// Bytes that stop mid-document — a child killed mid-write, a pipe cut.
    /// `JSONDecoder` gives up on the whole document, and `try?` turns that into
    /// an empty list.
    func testATruncatedAnswerIsNotAnUpToDateMachine() {
        let payload = #"{"formulae":[{"name":"deno","installed_versions":["2.9.3"]"#
        let answer = engine(CannedBrew([BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNil(answer, "a truncated JSON document was read as a machine with no updates")
    }

    /// The control on the other side: `{"formulae":[],"casks":[]}` is exactly
    /// what brew prints when everything really is current, and it must stay an
    /// answer rather than becoming a refusal.
    func testAnHonestlyCurrentMachineStillAnswers() {
        let payload = #"{"formulae":[],"casks":[]}"#
        let answer = engine(CannedBrew([BrewAnswer(["outdated"], 0, payload)])).outdated()
        XCTAssertNotNil(answer, "a genuinely up-to-date machine was reported as unreadable")
        XCTAssertEqual(answer?.count, 0)
    }

    // MARK: - Why search is not in this family

    /// Measured, not assumed (Homebrew 6.0.18, this Mac):
    ///
    ///     $ brew search --formula -- zzqqxxnope ; echo $?
    ///     1                       ← and nothing on stdout
    ///
    /// So for `search` a non-zero exit is brew's way of saying "no matches",
    /// and an empty list is the honest answer. This test exists so that a fix
    /// for the two above cannot be «nil on any non-zero status», which would
    /// turn every search that finds nothing into a module that cannot answer.
    func testASearchThatFoundNothingIsStillAnAnswer() {
        let runner = CannedBrew([BrewAnswer(["search"], 1, "")])
        let answer = engine(runner).search("zzqqxxnope")
        XCTAssertNotNil(answer, """
            brew spells "no matches" as exit 1 for `search`; the module now \
            reports it as a failure and the page keeps the previous query's hits
            """)
        XCTAssertEqual(answer?.count, 0)
    }
}
