import XCTest
@testable import Module_Homebrew_Engine

/// Four questions about one new query, in the shape
/// `ACaskIsNeverAskedWhatUsesItTests` established for exactly this kind of
/// query.
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
    "installed":[{"version":"3.6.4","time":1757800000,"installed_on_request":false}]}],"casks":[]}
    """.utf8)

    /// Subcommand, flag, terminator, name — in that order.
    func testTheSubcommandNamesTheKindAndTerminatesBeforeTheName() {
        let runner = InfoRunner()
        runner.stdout = formulaDocument
        _ = engine(runner).info(name: "openssl@3", isCask: false)
        XCTAssertEqual(runner.calls.first, ["info", "--json=v2", "--formula", "--", "openssl@3"])
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
}
