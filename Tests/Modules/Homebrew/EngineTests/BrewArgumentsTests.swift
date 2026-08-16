import XCTest
@testable import Module_Homebrew_Engine

/// Where a value stops being a value.
///
/// Nothing here is a shell injection: the arguments are an array and the
/// executable path is absolute, so no shell ever parses them. But `brew` parses
/// them, and it reads a leading `-` as a flag wherever it finds one. `query` is
/// typed by the user; `name` is a word this module parsed out of brew's own
/// stdout. Verified against Homebrew 6.0.13:
///
///     $ brew search --formula -n
///     Usage: brew search, -S [options] text|/regex/ [...]     ← the search never ran
///     $ brew search --formula -- -n
///     aarch64-elf-binutils …                                  ← searched for "-n"
///
/// `--` is accepted by every subcommand this module runs (`desc`, `search`,
/// `install`, `uninstall`, `upgrade`, with and without `--cask`).
private final class RecordingRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _calls.append(args); lock.unlock()
        return (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.lock(); _calls.append(args); lock.unlock()
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

final class BrewArgumentsTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester")
    }

    /// Asserts the *structure* — the value sits behind a terminator — rather
    /// than comparing the whole argument list, which would have to be rewritten
    /// every time a flag is added and would say nothing about the hazard.
    private func assertBehindTerminator(_ args: [String], value: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        guard let terminator = args.firstIndex(of: "--") else {
            return XCTFail("no `--` in \(args): brew reads \(value.debugDescription) as a flag",
                           file: file, line: line)
        }
        guard let at = args.firstIndex(of: value) else {
            return XCTFail("\(value.debugDescription) is not in \(args)", file: file, line: line)
        }
        XCTAssertGreaterThan(at, terminator,
                             "\(value.debugDescription) is ahead of the `--` in \(args)",
                             file: file, line: line)
    }

    func testASearchQueryIsBehindATerminator() {
        let runner = RecordingRunner()
        _ = engine(runner).search("-n")
        XCTAssertFalse(runner.calls.isEmpty, "no call was made at all")
        for call in runner.calls { assertBehindTerminator(call, value: "-n") }
    }

    func testDescribedNamesAreBehindATerminator() {
        let runner = RecordingRunner()
        _ = engine(runner).descriptions(names: ["--version"], isCask: false)
        XCTAssertFalse(runner.calls.isEmpty)
        for call in runner.calls { assertBehindTerminator(call, value: "--version") }
    }

    func testInstallPutsTheNameBehindATerminator() {
        for isCask in [false, true] {
            let runner = RecordingRunner()
            engine(runner).install(name: "-n", isCask: isCask)
            XCTAssertEqual(runner.calls.count, 1)
            assertBehindTerminator(runner.calls[0], value: "-n")
        }
    }

    func testUninstallPutsTheNameBehindATerminator() {
        for isCask in [false, true] {
            let runner = RecordingRunner()
            engine(runner).uninstall(name: "-n", isCask: isCask)
            XCTAssertEqual(runner.calls.count, 1)
            assertBehindTerminator(runner.calls[0], value: "-n")
        }
    }

    func testUpgradePutsTheNameBehindATerminator() {
        let runner = RecordingRunner()
        engine(runner).upgrade(name: "-n")
        XCTAssertEqual(runner.calls.count, 1)
        assertBehindTerminator(runner.calls[0], value: "-n")
    }

    /// `upgradeAll` has no subject, so it must not grow a stray terminator —
    /// the guard above is about values, and there is no value here.
    func testUpgradeAllTakesNoSubjectAndNoTerminator() {
        let runner = RecordingRunner()
        engine(runner).upgradeAll()
        XCTAssertEqual(runner.calls, [["upgrade"]])
    }

    /// The flags the module chooses itself stay flags: a terminator that landed
    /// ahead of `--cask` would turn it into a package name.
    func testTheModulesOwnFlagsStayAheadOfTheTerminator() {
        let runner = RecordingRunner()
        engine(runner).install(name: "wget", isCask: true)
        let call = runner.calls[0]
        let terminator = call.firstIndex(of: "--")
        let cask = call.firstIndex(of: "--cask")
        XCTAssertNotNil(terminator)
        XCTAssertNotNil(cask)
        XCTAssertLessThan(cask ?? .max, terminator ?? .min, "--cask became a package name: \(call)")
    }
}
