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
/// its own bare launch, and so did the shell's updater, which is the one that
/// hands the swap script over: a refusal there aborted the app *while it was
/// replacing itself*. Both start their child through `HelmProcess.start` now.
///
/// A scan rather than a type, because there is nothing to make impossible —
/// `Process.run()` is Foundation's and every file can reach it. What a scan can
/// do is make the next one an error rather than a discovery, and it costs
/// nothing to keep.
///
/// **The scan is over `Sources` entire; the class is named for the shell
/// because the shell is where it began.** It reads every `.swift` file there
/// through `SwiftSource.code`, which blanks comments and the insides of string
/// literals and keeps every line where it was. The reading matters: the files
/// that explain this trap quote the spelling in their own comments, `HelmProcess`
/// and Homebrew's ports among them, and a scan that read comments would report
/// the explanation as the offence. `Sources/HelmLaunch` is Objective-C and is
/// not read; `HelmLaunchTask` is defined there, and it is the launch the door
/// goes through.
final class NoBareLaunchInTheShellTests: XCTestCase {

    /// The spelling that aborts, as a file would write it: the letters `try`
    /// and a space on the same line as a `.run()`. `try?` and `try!` are not
    /// this spelling, and the scan does not see them.
    private static let bareLaunch = "try process.run()"

    /// The lines of `code` that start a child that way. `code` is a file as
    /// `SwiftSource.code` reads it, so the line a finding names is the file's
    /// own.
    private static func bareLaunches(in code: String, path: String) -> [String] {
        var found: [String] = []
        for (index, line) in code.components(separatedBy: "\n").enumerated() {
            guard line.contains("try "), line.contains(".run()") else { continue }
            found.append("\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
        }
        return found
    }

    /// No `.swift` file under `Sources` starts a child that way. The name says
    /// the shell for the reason the class's does.
    func testNothingInTheShellStartsAChildWithoutTheGuard() throws {
        let files = try SwiftSource.code(under: "Sources")
        XCTAssertFalse(files.isEmpty, "the walk under `Sources` returned no file")

        var offences: [String] = []
        for file in files {
            offences += Self.bareLaunches(in: file.text, path: file.path)
        }
        XCTAssertEqual(offences, [], """
            a child is started here without the guard. `NSTask` raises an Objective-C exception \
            on some launch paths and a Swift `catch` cannot see it, so this aborts the app \
            rather than throwing — `HelmProcess.start(_:path:)` is the door that answers
            """)
    }

    /// And the door can move: the scan above is green over a tree that starts
    /// no child at all, so this says the code of `HelmProcess`'s file still
    /// spells `HelmLaunchTask` and its opening parenthesis, read as
    /// `SwiftSource.code` reads it so that a comment or a literal that names
    /// the launch cannot stand in for the call. The check is of the letters,
    /// anywhere in that code: a call nothing reaches, or the letters at the end
    /// of a longer name, is not seen.
    func testTheDoorsFileStillSpellsItsLaunchThroughHelmLaunchTask() throws {
        let runtime = try SwiftSource.code(
            RepoSource.text(of: "Sources/HelmRuntime/HelmProcess.swift"))
        XCTAssertTrue(runtime.contains("HelmLaunchTask("), """
            the code of `HelmProcess.swift` no longer spells `HelmLaunchTask(`: the door's \
            launch has left this file or is spelled another way, and the scan above is green \
            over a tree that starts no child at all
            """)
    }

    /// And the reading can fail: the spelling is found in code, found after a
    /// string literal that holds `//`, and not found where a comment or a
    /// literal only speaks of it — whatever the tree holds.
    func testTheReadingFindsALaunchInCodeAndNotInWhatIsSaidAboutIt() {
        func found(_ source: String) -> [String] {
            Self.bareLaunches(in: SwiftSource.code(source), path: "fixture")
        }
        let launch = Self.bareLaunch
        XCTAssertEqual(found("func start() throws {\n    \(launch)\n}\n"),
                       ["fixture:2: \(launch)"],
                       "a bare launch in code was not found, or not on its own line")
        XCTAssertFalse(found("    let from = \"https://example.invalid\"; \(launch)\n").isEmpty,
                       "a bare launch after a literal holding `//` was taken for a comment")
        XCTAssertEqual(found("    // \(launch)\n    /// \(launch)\n    /* \(launch) */\n"), [],
                       "a comment that quotes the spelling was read as a launch")
        XCTAssertEqual(found("    let said = \"\(launch)\"\n"), [],
                       "a literal that quotes the spelling was read as a launch")
    }
}
