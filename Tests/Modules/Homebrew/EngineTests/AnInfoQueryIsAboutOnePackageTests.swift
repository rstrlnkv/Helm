import XCTest
@testable import Module_Homebrew_Engine

/// The questions this codebase asks of a new query, asked of `info` — in the
/// shape `ACaskIsNeverAskedWhatUsesItTests` established for exactly this kind of
/// query: what the tool is asked, what it answers, and the two silences that
/// must not read as an answer (brew refused, and there is no brew).
///
/// **The first case asserts the answer and not only the arguments**, because
/// without that every case in this file discarded the result or asserted nil —
/// and three mutations lived through the lot: `info` returning nil
/// unconditionally, `isCask` inverted on the way into `BrewInfoParser.parse`,
/// and the parser handed bytes that were not the tool's. A query whose green
/// path nothing asserts is a query whose green path is not tested, however many
/// cases stand around it. The sibling asserts its positive on its first case for
/// the same reason.
///
/// The payload is JSON, so this one runs through `runData` — the same reason
/// `outdated()` does, and the same reason its fake speaks `Data` rather than
/// `String` (`OutdatedQueryAllocationBenchmark`'s `CannedRunner`).
private final class InfoRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    private var _envs: [[String: String]] = []
    var envs: [[String: String]] { lock.lock(); defer { lock.unlock() }; return _envs }
    var status: Int32 = 0
    var stdout = Data()

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        (status, String(bytes: stdout, encoding: .utf8) ?? "")
    }

    func runData(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: Data) {
        lock.lock(); _calls.append(args); _envs.append(env); lock.unlock()
        return (status, stdout)
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

final class AnInfoQueryIsAboutOnePackageTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    // Trimmed the same way `BrewInfoParserTests` trims its fixtures: real
    // keys, real nesting, nothing invented for the test's convenience.
    private let formulaDocument = Data("""
    {"formulae":[{"name":"openssl@3","desc":"Cryptography and SSL/TLS Toolkit",
    "homepage":"https://openssl-library.org","license":"Apache-2.0","tap":"homebrew/core",
    "deprecated":false,"versioned_formulae":[],"dependencies":[],"caveats":null,
    "versions":{"stable":"3.6.4","head":"HEAD","bottle":true},
    "installed":[{"version":"3.6.4","time":1757800000,"installed_on_request":false}]}],"casks":[]}
    """.utf8)

    /// Subcommand, flag, terminator, name — in that order; and the document
    /// brew answered with, read and handed back.
    ///
    /// The assertions on the answer are what make the three mutations above
    /// reachable: the name and the install facts come out of the document, and
    /// `isCask` decides which half of it is even looked at, so a formula
    /// document parsed as a cask answers nil.
    func testTheSubcommandNamesTheKindAndTerminatesBeforeTheName() {
        let runner = InfoRunner()
        runner.stdout = formulaDocument
        let info = engine(runner).info(name: "openssl@3", isCask: false)
        XCTAssertEqual(runner.calls.first, ["info", "--json=v2", "--formula", "--", "openssl@3"])
        XCTAssertEqual(info?.name, "openssl@3", "the document brew answered was not read back")
        XCTAssertFalse(info?.isCask ?? true, "a formula came back marked as a cask")
        XCTAssertEqual(info?.desc, "Cryptography and SSL/TLS Toolkit")
        XCTAssertEqual(info?.license, "Apache-2.0")
        XCTAssertEqual(info?.installedVersion, "3.6.4")
        XCTAssertEqual(info?.latestVersion, "3.6.4")
        XCTAssertEqual(info?.installedOnRequest, false)
    }

    func testACaskAsksWithItsOwnFlag() {
        let runner = InfoRunner()
        runner.stdout = Data(#"{"formulae":[],"casks":[]}"#.utf8)
        _ = engine(runner).info(name: "firefox", isCask: true)
        XCTAssertEqual(runner.calls.first, ["info", "--json=v2", "--cask", "--", "firefox"])
    }

    /// This query answers about the disk, and must not refresh the catalogue
    /// to do it — the same reasoning `queryEnvironment`'s doc comment gives for
    /// `dependents` and `descriptions`.
    func testTheQueryDoesNotRefreshTheCatalogue() {
        let runner = InfoRunner()
        runner.stdout = formulaDocument
        _ = engine(runner).info(name: "openssl@3", isCask: false)
        XCTAssertEqual(runner.envs.first, HomebrewEngine.queryEnvironment)
    }

    /// brew refusing must not read as "this package does not exist" — the same
    /// sentence `ACaskIsNeverAskedWhatUsesItTests.testARefusalIsNotALeaf`
    /// asserts for `dependents`.
    func testARefusalIsNotAnEmptyAnswer() {
        let runner = InfoRunner()
        runner.status = 1
        runner.stdout = formulaDocument
        XCTAssertNil(engine(runner).info(name: "openssl@3", isCask: false),
                     "brew refusing must not read as «nothing to say about this package»")
    }

    /// A document `BrewInfoParser` does not recognise is not the same sentence
    /// as brew having nothing to say — see that parser's own doc comment.
    func testADocumentTheParserRefusesIsNotAnAnswer() {
        let runner = InfoRunner()
        runner.stdout = Data("not json".utf8)
        XCTAssertNil(engine(runner).info(name: "openssl@3", isCask: false),
                     "a shape this build cannot read must not surface as an empty package")
    }

    /// The same sentence one step earlier, and the branch the query's own doc
    /// comment rests on: `info` answers nil when brew refused **and** when there
    /// is no brew to ask.
    ///
    /// Not a broken fixture — `FSBrewLocator` re-reads the disk at every call, so
    /// Homebrew can be uninstalled in a terminal beside this window while a
    /// package is on screen. The second assertion is the one that costs
    /// something: a nil arrived at by launching a tool that could not exist is
    /// the same value by a different route, and the route is the claim
    /// (`ACaskIsNeverAskedWhatUsesItTests.testAMissingBrewIsAQueryThatNeverRan`).
    func testAMissingBrewIsAQueryThatNeverRan() {
        let runner = InfoRunner()
        runner.stdout = formulaDocument
        let engine = HomebrewEngine(locator: NoBrew(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        XCTAssertNil(engine.info(name: "openssl@3", isCask: false),
                     "no brew to ask read as an answer about the package")
        XCTAssertTrue(runner.calls.isEmpty, "a tool was launched with no brew to launch")
    }
}
