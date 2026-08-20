import HelmTestSupport
import XCTest

/// **`try process.run()` is a way to abort the app, and a Swift `catch` cannot
/// stop it.**
///
/// `NSTask` raises an Objective-C exception on some launch paths, and an ObjC
/// exception goes past a Swift `catch` straight into `std::terminate`. A build
/// shipped and died with SIGABRT inside `-[NSConcreteTask launchWithDictionary:error:]`,
/// which is why `HelmProcess` grew `HelmLaunchTask` — a launch that answers
/// instead of raising — and why `run` and `runData` were moved onto it.
///
/// **They were moved and two callers were not.** Homebrew's streaming port kept
/// its own bare launch, and so did this target's updater, which is the one that
/// hands the swap script over: a refusal there aborts the app *while it is
/// replacing itself*.
///
/// A scan rather than a type, because there is nothing to make impossible —
/// `Process.run()` is Foundation's and every file can reach it. What a scan can
/// do is make the next one an error rather than a discovery, and it costs
/// nothing to keep.
///
/// A test in `HelmAppTests` and not one scan over the whole tree, deliberately:
/// the modules are other people's targets today, and a guard that goes red on
/// somebody else's file is a guard they will delete. Widening it to `Sources/`
/// is worth doing once the last bare launch is gone.
final class NoBareLaunchInTheShellTests: XCTestCase {

    /// `try` on the same line as a `.run()` that is not `HelmProcess`'s own.
    private static let bareLaunch = "try process.run()"

    func testNothingInTheShellStartsAChildWithoutTheGuard() throws {
        var offences: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/HelmApp") {
            for (index, line) in try RepoSource.lines(of: path).enumerated() {
                let code = RepoSource.code(line)
                guard code.contains("try "), code.contains(".run()") else { continue }
                offences.append("\(path):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offences, [], """
            a child is started here without the guard. `NSTask` raises an Objective-C exception \
            on some launch paths and a Swift `catch` cannot see it, so this aborts the app \
            rather than throwing — `HelmProcess.start(_:path:)` is the door that answers
            """)
    }

    /// And the scan can fail: the spelling it hunts for has to be one the tree
    /// could really contain, or a rename of `Process.run()` would leave it
    /// passing over a shell full of bare launches.
    func testTheSpellingItHuntsForIsStillHowAChildIsStarted() throws {
        let runtime = try RepoSource.text(of: "Sources/HelmRuntime/HelmProcess.swift")
        XCTAssertTrue(runtime.contains(".run()") || runtime.contains("HelmLaunchTask"), """
            `HelmProcess` no longer starts a child by either spelling this scan knows, so the \
            scan above is looking for something that has been renamed under it
            """)
    }
}
