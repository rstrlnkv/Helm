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
/// `install`, `uninstall`, `upgrade`, `uses`, `info`, with and without
/// `--cask`). `uses` was verified on 2026-09-13 against Homebrew 6.x:
///
///     $ brew uses --installed -- openssl@3
///     aria2 libngtcp2 libssh2 llama.cpp nmap node python@3.14 yt-dlp
///
/// — exit 0 and eight dependents, so the terminator is read as a terminator
/// there too and is not mistaken for the name of a formula.
///
/// `info` was verified on 2026-09-15 against Homebrew 7.0.1:
///
///     $ brew info --json=v2 --formula -n
///     Usage: brew info, abv [options] [formula|cask ...]  ← the lookup never ran
///     Error: invalid option: -n
///     $ brew info --json=v2 --formula -- -n
///     Error: No available formula with the name "-n".     ← looked up as a name
///
/// — both exit 1, but only the second reads `-n` as the name of a (missing)
/// formula rather than an option `info` does not recognise; the terminator is
/// doing its job even though neither call finds a package.
final class BrewArgumentsTests: XCTestCase {

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester")
    }

    /// Asserts the *structure* — the value sits behind a terminator — rather
    /// than comparing the whole argument list, which would have to be rewritten
    /// every time a flag is added and would say nothing about the hazard.
    private func assertBehindTerminator(_ args: [String], value: String, what: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        guard let terminator = args.firstIndex(of: "--") else {
            return XCTFail("\(what): no `--` in \(args): brew reads \(value.debugDescription) as a flag",
                           file: file, line: line)
        }
        guard let at = args.firstIndex(of: value) else {
            return XCTFail("\(what): \(value.debugDescription) is not in \(args)", file: file, line: line)
        }
        XCTAssertGreaterThan(at, terminator,
                             "\(what): \(value.debugDescription) is ahead of the `--` in \(args)",
                             file: file, line: line)
    }

    /// One door per subcommand that takes a dash-led value, each with the number
    /// of calls it must make — `nil` for the ones that make several and are asked
    /// about every one of them — and a label, so a red run says which subcommand
    /// lost its terminator.
    private typealias Row = (what: String, value: String, count: Int?, act: (HomebrewEngine) -> Void)

    func testEveryDashLedValueIsBehindATerminator() {
        let rows: [Row] = [
            ("search", "-n", nil, { _ = $0.search("-n") }),
            ("descriptions", "--version", nil, { _ = $0.descriptions(names: ["--version"], isCask: false) }),
            // A cask is answered without a tool run, so there is nothing to assert
            // about its arguments — `ACaskIsNeverAskedWhatUsesItTests` owns that half.
            ("dependents", "-n", 1, { _ = $0.dependents(name: "-n", isCask: false) }),
            ("upgrade", "-n", 1, { $0.upgrade(name: "-n") }),
        ] + [false, true].flatMap { isCask -> [Row] in [
            ("install, cask: \(isCask)", "-n", 1, { $0.install(name: "-n", isCask: isCask) }),
            ("uninstall, cask: \(isCask)", "-n", 1, { $0.uninstall(name: "-n", isCask: isCask) }),
            // `info` runs through `runData`, not `run` — `AnInfoQueryIsAboutOnePackageTests`
            // owns that query's own behaviour; this asserts only the hazard this file
            // exists for.
            ("info, cask: \(isCask)", "-n", 1, { _ = $0.info(name: "-n", isCask: isCask) }),
        ] }
        for row in rows {
            let runner = EnvironmentRecorder()
            row.act(engine(runner))
            let calls = runner.calls.map(\.args)
            if let count = row.count {
                XCTAssertEqual(calls.count, count, row.what)
            } else {
                XCTAssertFalse(calls.isEmpty, "\(row.what): no call was made at all")
            }
            for call in calls { assertBehindTerminator(call, value: row.value, what: row.what) }
        }
    }

    /// `upgradeAll` has no subject, so it must not grow a stray terminator —
    /// the guard above is about values, and there is no value here.
    func testUpgradeAllTakesNoSubjectAndNoTerminator() {
        let runner = EnvironmentRecorder()
        engine(runner).upgradeAll()
        XCTAssertEqual(runner.calls.map(\.args), [["upgrade"]])
    }

    /// The flags the module chooses itself stay flags: a terminator that landed
    /// ahead of `--cask` would turn it into a package name.
    func testTheModulesOwnFlagsStayAheadOfTheTerminator() {
        let runner = EnvironmentRecorder()
        engine(runner).install(name: "wget", isCask: true)
        let call = runner.calls[0].args
        let terminator = call.firstIndex(of: "--")
        let cask = call.firstIndex(of: "--cask")
        XCTAssertNotNil(terminator)
        XCTAssertNotNil(cask)
        XCTAssertLessThan(cask ?? .max, terminator ?? .min, "--cask became a package name: \(call)")
    }
}
