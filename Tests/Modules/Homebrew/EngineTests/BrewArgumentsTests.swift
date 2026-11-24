import XCTest
@testable import Module_Homebrew_Engine

/// Where a value stops being a value.
///
/// Nothing here is a shell injection: the arguments are an array and the
/// executable path is absolute. But `brew` reads a leading `-` as a flag
/// wherever it finds one, and `query` is typed by the person while `name` is a
/// word parsed out of brew's own stdout:
///
///     $ brew search --formula -n
///     Usage: brew search, -S [options] text|/regex/ [...]     ← the search never ran
///     $ brew search --formula -- -n
///     aarch64-elf-binutils …                                  ← searched for "-n"
///
/// `--` is accepted by every subcommand this module runs (`desc`, `search`,
/// `install`, `uninstall`, `upgrade`, `uses`, `info`, with and without
/// `--cask`). For `uses` it is read as a terminator, not a formula name:
///
///     $ brew uses --installed -- openssl@3
///     aria2 libngtcp2 libssh2 llama.cpp nmap node python@3.14 yt-dlp
///
/// For `info`, only the second call reads `-n` as a name:
///
///     $ brew info --json=v2 --formula -n
///     Usage: brew info, abv [options] [formula|cask ...]  ← the lookup never ran
///     Error: invalid option: -n
///     $ brew info --json=v2 --formula -- -n
///     Error: No available formula with the name "-n".     ← looked up as a name
final class BrewArgumentsTests: XCTestCase {

    /// Asserts the *structure*, the value behind a terminator, rather than the
    /// whole argument list, which every new flag would rewrite.
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
            // about its arguments.
            ("dependents", "-n", 1, { _ = $0.dependents(name: "-n", isCask: false) }),
            ("upgrade", "-n", 1, { $0.upgrade(name: "-n") }),
        ] + [false, true].flatMap { isCask -> [Row] in [
            ("install, cask: \(isCask)", "-n", 1, { $0.install(name: "-n", isCask: isCask) }),
            ("uninstall, cask: \(isCask)", "-n", 1, { $0.uninstall(name: "-n", isCask: isCask) }),
            // `info` runs through `runData`; only the terminator is asserted.
            ("info, cask: \(isCask)", "-n", 1, { _ = $0.info(name: "-n", isCask: isCask) }),
        ] }
        for row in rows {
            let runner = ScriptedRunner()
            row.act(brewEngine(runner))
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
        let runner = ScriptedRunner()
        brewEngine(runner).upgradeAll()
        XCTAssertEqual(runner.calls.map(\.args), [["upgrade"]])
    }

    /// The flags the module chooses itself stay flags: a terminator that landed
    /// ahead of `--cask` would turn it into a package name.
    func testTheModulesOwnFlagsStayAheadOfTheTerminator() {
        let runner = ScriptedRunner()
        brewEngine(runner).install(name: "wget", isCask: true)
        let call = runner.calls[0].args
        let terminator = call.firstIndex(of: "--")
        let cask = call.firstIndex(of: "--cask")
        XCTAssertNotNil(terminator)
        XCTAssertNotNil(cask)
        XCTAssertLessThan(cask ?? .max, terminator ?? .min, "--cask became a package name: \(call)")
    }
}
