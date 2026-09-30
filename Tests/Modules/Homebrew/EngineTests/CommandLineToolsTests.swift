import XCTest
@testable import Module_Homebrew_Engine

/// The pure half of the wait for Apple's tools: whether they are on the Mac,
/// and what one tick concludes. Nothing here starts a process or reads a disk —
/// the engine's side of the wait is `InstallWaitsForApplesToolsTests`.
final class CommandLineToolsTests: XCTestCase {

    // MARK: - Reading

    /// The ordinary Mac with the tools: the fixed path answers and the process
    /// `xcode-select -p` is never started.
    func testTheFixedGitAnswersWithoutStartingAnything() {
        var asked = false
        let present = CommandLineTools.present(
            isExecutable: { $0 == CommandLineTools.git },
            selected: { asked = true; return nil })
        XCTAssertTrue(present)
        XCTAssertFalse(asked, "a Mac that has the tools paid for a process to say so")
    }

    func testAGitUnderTheSelectedDeveloperDirectoryCounts() {
        let xcode = "/Applications/Xcode.app/Contents/Developer"
        let present = CommandLineTools.present(
            isExecutable: { $0 == xcode + "/usr/bin/git" },
            selected: { xcode + "\n" })
        XCTAssertTrue(present, "a Mac whose tools are Xcode's was sent to Apple's installer")
    }

    /// A selected directory that holds no `git` is not the tools: `install.sh`
    /// would stop at the same test.
    func testASelectedDirectoryWithNoGitIsNotTheTools() {
        let present = CommandLineTools.present(
            isExecutable: { _ in false },
            selected: { "/Applications/Xcode.app/Contents/Developer\n" })
        XCTAssertFalse(present)
    }

    func testNoSelectedDirectoryIsNotTheTools() {
        XCTAssertFalse(CommandLineTools.present(isExecutable: { _ in false }, selected: { nil }))
    }

    func testThePrintedDirectoryIsTrimmedAndJoinedOnce() {
        XCTAssertEqual(CommandLineTools.git(inDeveloperDirectory: "/Library/Developer/CommandLineTools\n"),
                       "/Library/Developer/CommandLineTools/usr/bin/git")
        XCTAssertEqual(CommandLineTools.git(inDeveloperDirectory: "/Library/Developer/CommandLineTools/\n"),
                       "/Library/Developer/CommandLineTools/usr/bin/git",
                       "a trailing slash doubled in the joined path")
    }

    /// An answer that cannot name an absolute directory names nothing: a
    /// relative path is resolved against whatever this process's working
    /// directory is.
    func testAnEmptyOrRelativeAnswerNamesNothing() {
        for printed in ["", "\n", "   ", "usr/local", "./Developer", "Developer\n"] {
            XCTAssertNil(CommandLineTools.git(inDeveloperDirectory: printed),
                         "\(printed.debugDescription) was read as a directory")
        }
    }

    // MARK: - One tick

    private func step(_ wait: CommandLineTools.Wait = .init(), tools: Bool, installer: Bool)
    -> (wait: CommandLineTools.Wait, verdict: CommandLineTools.Verdict, sayNeverSeen: Bool) {
        CommandLineTools.next(wait, toolsPresent: tools, installerRunning: installer)
    }

    /// Rule 1: the tools are there, whatever the installer is doing — Apple's
    /// «Done» button is not waited for.
    func testTheToolsArriveWhateverTheInstallerIsDoing() {
        XCTAssertEqual(step(tools: true, installer: true).verdict, .toolsArrived)
        XCTAssertEqual(step(tools: true, installer: false).verdict, .toolsArrived)
        var seen = CommandLineTools.Wait(); seen.sawInstaller = true
        XCTAssertEqual(step(seen, tools: true, installer: false).verdict, .toolsArrived,
                       "a window closed after the tools landed was read as a failure")
    }

    /// Rules 2 and 3: running, then gone with nothing installed.
    func testAWindowSeenAndThenGoneWithoutToolsIsAClosedWindow() {
        let first = step(tools: false, installer: true)
        XCTAssertEqual(first.verdict, .keepWaiting)
        XCTAssertTrue(first.wait.sawInstaller, "the sighting was not remembered")
        XCTAssertEqual(step(first.wait, tools: false, installer: true).verdict, .keepWaiting)
        XCTAssertEqual(step(first.wait, tools: false, installer: false).verdict, .closedWithoutTools)
    }

    /// Rule 4: an absence is not a failure when no presence was ever read. If
    /// the identity the reading looks for is wrong, this is what stands between
    /// a working install and a false «Failed» over a window still open.
    func testAnInstallerNeverSeenIsNotAClosedWindow() {
        var wait = CommandLineTools.Wait()
        for tick in 1...(CommandLineTools.neverSeenAfter * 3) {
            let result = step(wait, tools: false, installer: false)
            XCTAssertEqual(result.verdict, .keepWaiting,
                           "tick \(tick): an installer that was never read as running was read as closed")
            wait = result.wait
        }
    }

    /// Rule 5: the line is said once, at the threshold, and never before it.
    func testTheNeverSeenWarningIsSaidExactlyOnce() {
        var wait = CommandLineTools.Wait()
        var said: [Int] = []
        for tick in 1...(CommandLineTools.neverSeenAfter * 3) {
            let result = step(wait, tools: false, installer: false)
            if result.sayNeverSeen { said.append(tick) }
            wait = result.wait
        }
        XCTAssertEqual(said, [CommandLineTools.neverSeenAfter],
                       "the warning must be said once, at the threshold")
    }

    /// Said only about an installer that was never seen: one that has been
    /// seen is the identity working.
    func testNothingIsSaidAboutAnInstallerThatWasSeen() {
        var wait = CommandLineTools.Wait()
        wait = step(wait, tools: false, installer: true).wait
        for _ in 1...(CommandLineTools.neverSeenAfter * 2) {
            let result = step(wait, tools: false, installer: true)
            XCTAssertFalse(result.sayNeverSeen)
            wait = result.wait
        }
    }
}
