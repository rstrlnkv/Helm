import XCTest
@testable import Module_Homebrew_Engine

// MARK: - Fakes

private struct FixedLocator: BrewLocator {
    var path: String? = "/opt/homebrew/bin/brew"
    func brewPath() -> String? { path }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

/// A runner that answers the way `brew` itself does, as observed on Homebrew
/// 6.0.12: it validates every name it was given *before* it prints anything, so
/// one name it cannot resolve costs the whole call — exit 1, the message on
/// stderr, and **stdout empty**.
///
///     $ brew desc --formula jq zzqqxxnope
///     Error: No available formula with the name "zzqqxxnope".   (stderr)
///     $ echo $?
///     1
///     # stdout: nothing at all, not even jq's line
private final class BrewLikeRunner: ProcessRunner, @unchecked Sendable {
    /// name → description, for the names this fake brew knows.
    let known: [String: String]
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

    init(known: [String: String]) { self.known = known }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _calls.append(args); lock.unlock()
        guard args.first == "desc" else { return (0, "") }
        // Names are whatever follows the `--`, which is what brew itself does:
        // the terminator ends option parsing and everything after it is a name.
        guard let terminator = args.firstIndex(of: "--") else { return (1, "") }
        let names = args[args.index(after: terminator)...]
        guard names.allSatisfy({ known[$0] != nil }) else { return (1, "") }
        return (0, names.map { "\($0): \(known[$0]!)" }.joined(separator: "\n") + "\n")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

/// What the queries do when `brew` does not answer the way the happy path
/// assumes. Every one of them throws the exit status away and hands whatever
/// landed on stdout to a parser, so "the tool failed" and "there is nothing"
/// arrive at the page as the same thing.
final class HomebrewEngineQueryTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester")
    }

    /// The trap: one name in the batch that brew cannot resolve.
    ///
    /// The page asks for descriptions in a single call covering the whole
    /// installed list — `loadDescriptions` builds one `names` array per kind.
    /// A Cellar can easily hold a formula brew can no longer look up: installed
    /// from a tap that has since been removed, or renamed upstream. `brew list
    /// --versions` still reports it, because it is on disk; `brew desc` refuses
    /// the whole call because of it.
    ///
    /// The result is not a missing description on one row. It is **no
    /// description on any row**, for every package the person has, with nothing
    /// anywhere saying why — the status that would have said so is dropped on
    /// the floor by `runner.run(...).stdout`.
    ///
    /// Asserted on the description that survives, not on the one that cannot:
    /// `zzqqxxnope` has no answer and must not invent one.
    func testOneUnresolvableNameDoesNotBlankEveryDescription() {
        let runner = BrewLikeRunner(known: [
            "jq": "Lightweight and flexible command-line JSON processor",
            "wget": "Internet file retriever",
        ])
        let engine = engine(runner)

        let out = engine.descriptions(names: ["jq", "zzqqxxnope", "wget"], isCask: false)

        XCTAssertEqual(out["jq"], "Lightweight and flexible command-line JSON processor",
                       "one name brew could not resolve took every other description "
                       + "with it — the whole list rendered without descriptions")
        XCTAssertEqual(out["wget"], "Internet file retriever")
        XCTAssertNil(out["zzqqxxnope"], "and no description may be invented for the bad name")
    }

    /// The control: with every name resolvable the batch is one call and works.
    /// So the answer above is not "ask one at a time and be slow" by default.
    func testAGoodBatchIsStillOneCall() {
        let runner = BrewLikeRunner(known: ["jq": "A", "wget": "B"])
        let engine = engine(runner)
        let out = engine.descriptions(names: ["jq", "wget"], isCask: false)
        XCTAssertEqual(out, ["jq": "A", "wget": "B"])
        XCTAssertEqual(runner.calls.filter { $0.first == "desc" }.count, 1,
                       "a batch that brew can answer must stay one call")
    }
}
