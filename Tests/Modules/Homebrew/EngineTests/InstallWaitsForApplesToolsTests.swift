import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **Install Homebrew on a Mac without Apple's Command Line Tools**, from the
/// press to the password dialog. `install.sh` installs the tools itself only
/// when `sudo` can ask on a terminal, and Helm runs it with neither, so the
/// engine files Apple's own request, waits for `git` to appear, and only then
/// raises the one root step. Nothing here starts a process, opens a window or
/// asks for a password: Apple's tools, time and root are three fakes for the
/// three sides of the boundary (`CommandLineToolsFakes.swift`).
final class InstallWaitsForApplesToolsTests: XCTestCase {

    // MARK: - The ordinary Mac

    /// A Mac that has the tools goes straight to the password, as it always
    /// did — and starts nothing on the way: no request, no `xcode-select`, no
    /// tick.
    func testAMacWithTheToolsGoesStraightToThePassword() async {
        let rig = WaitRig()
        rig.tools.gitExecutable = true

        rig.engine.installBrew()

        XCTAssertEqual(rig.privileged.scripts.count, 1, "the tools were there and the password was not asked")
        XCTAssertEqual(rig.tools.requestCount, 0, "Apple's installer was asked for a Mac that has the tools")
        XCTAssertEqual(rig.tools.selectedAsked, 0, "a process was started to find what a stat already said")
        XCTAssertEqual(rig.ticker.scheduled, 0, "a wait was armed for a Mac that has nothing to wait for")
        XCTAssertEqual(rig.runner.calls.count, 1)
    }

    /// The tools Xcode brings count too: `xcode-select -p` is asked only when
    /// the fixed path is not there, and it points at a `git`.
    func testAMacWhoseToolsAreXcodesAlsoGoesStraightOn() {
        let rig = WaitRig()
        let developer = "/Applications/Xcode.app/Contents/Developer"
        rig.tools.selected = developer + "\n"
        rig.tools.executables = [developer + "/usr/bin/git"]

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 0)
        XCTAssertEqual(rig.privileged.scripts.count, 1)
    }

    // MARK: - Asking, and waiting

    /// One request, a wait that names what it waits for, and no password: the
    /// dialog is for after the tools.
    func testWithoutTheToolsThePressFilesOneRequestAndWaitsWithoutAPassword() async {
        let rig = WaitRig()

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 1)
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the password was asked for while Apple's window was still to come")
        XCTAssertTrue(rig.runner.calls.isEmpty)
        XCTAssertEqual(rig.ticker.live, 1, "nothing is looking for the tools")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .running)
        XCTAssertEqual(state?.waiting, .commandLineTools,
                       "the page cannot say what it is waiting for")
    }

    /// The window is already open — a second press after coming back to
    /// Settings. A second request would ask for a second window.
    func testAnInstallerAlreadyOpenIsNotAskedForAgain() async {
        let rig = WaitRig()
        rig.tools.installerRunning = true

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 0, "Apple's installer was asked for while it was open")
        XCTAssertEqual(rig.ticker.live, 1)
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.waiting, .commandLineTools)
    }

    /// A second press during the wait meets the busy gate before anything
    /// else: no second request and no dialog.
    func testASecondPressDuringTheWaitIsRefusedByTheGate() async {
        let rig = WaitRig()
        rig.engine.installBrew()

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 1, "a second press filed a second request")
        XCTAssertTrue(rig.privileged.scripts.isEmpty)
        XCTAssertEqual(rig.ticker.live, 1, "a second wait was armed beside the first")
        let (state, log) = await rig.replayed()
        XCTAssertEqual(state?.waiting, .commandLineTools,
                       "the refusal overwrote the waiting state")
        XCTAssertNotNil(log, "the refused press left no line")
    }

    /// A tick that finds the window open and no tools keeps waiting: one
    /// tick, one re-arm, no dialog.
    func testATickThatFindsNothingNewKeepsWaiting() {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true

        XCTAssertTrue(rig.ticker.fire())

        XCTAssertEqual(rig.ticker.live, 1, "the wait was not re-armed")
        XCTAssertTrue(rig.privileged.scripts.isEmpty)
    }

    // MARK: - The tools arrive

    /// The tools land: the wait ends, the tools are read again one line before
    /// the dialog, the dialog is raised once, and the installer streams with
    /// the environment the engine declares.
    func testWhenTheToolsArriveThePasswordFollowsAFreshReading() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.ticker.fire()
        rig.tools.gitExecutable = true

        rig.ticker.fire()

        XCTAssertEqual(rig.privileged.scripts.count, 1)
        let entries = rig.journal.entries
        XCTAssertEqual(Array(entries.suffix(2)), ["read", "admin"],
                       "the dialog was not directly preceded by a reading of the tools: \(entries)")
        XCTAssertEqual(rig.runner.calls.count, 1)
        XCTAssertEqual(rig.runner.calls.first?.env, HomebrewEngine.installerEnvironment)
        XCTAssertEqual(rig.ticker.live, 0, "a tick is still armed after the wait ended")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .running)
        XCTAssertNil(state?.waiting, "the page still says it is waiting for the tools")
    }

    /// The tools are read again one line before the dialog and not taken on the
    /// word of the tick that ended the wait: they may have been removed since,
    /// and a password is not spent on a `mkdir` for an installer that will stop
    /// at its own `git` check. The second reading answers no; no dialog rises.
    func testTheToolsAreReadAgainJustBeforeTheDialog() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.tools.gitExecutable = true
        var reads = 0
        rig.tools.onRead = { [tools = rig.tools] in
            reads += 1
            if reads == 2 { tools.gitExecutable = false }   // the tick read #1; this is the fresh one
        }

        rig.ticker.fire()

        XCTAssertGreaterThanOrEqual(reads, 2, "precondition: the tools were read again at all")
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the dialog rose on a reading older than the act")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .toolsNotInstalled)
    }

    /// The window is gone *because* it finished installing: the installer is
    /// read before `git`, so "not running" cannot precede a `git` that is not
    /// yet there. Read the other way round this tick would call a successful
    /// install a closed window.
    func testAWindowThatFinishesBetweenTheTwoReadingsIsAnArrival() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.ticker.fire()
        // The window finishes installing and closes at the moment it is asked.
        rig.tools.onInstallerRead = { [tools = rig.tools] in
            tools.gitExecutable = true
            tools.installerRunning = false
        }
        rig.tools.installerRunning = false

        rig.ticker.fire()

        let (state, _) = await rig.replayed()
        XCTAssertNotEqual(state?.reason, .toolsNotInstalled,
                          "a window that had just finished installing was read as closed with nothing")
        XCTAssertEqual(rig.privileged.scripts.count, 1)
    }

    // MARK: - The window closes without the tools

    /// Cancel, Disagree, Stop, a failure on Apple's side: the window was seen
    /// and is gone and there is no `git`. A named outcome, no password, and the
    /// gate opens — the next press asks again.
    func testAWindowSeenAndClosedWithoutToolsIsANamedFailureAndReleasesTheGate() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.ticker.fire()
        rig.tools.installerRunning = false

        rig.ticker.fire()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .toolsNotInstalled)
        XCTAssertNil(state?.exitCode, "no child ran, so there is no code to show")
        XCTAssertTrue(rig.privileged.scripts.isEmpty, "a password was asked for after the tools were refused")
        XCTAssertEqual(rig.ticker.live, 0)

        rig.engine.installBrew()
        XCTAssertEqual(rig.tools.requestCount, 2,
                       "the failed press left the gate shut, or was not asked again")
    }

    /// An installer that is never read as running is not a closed one: the wait
    /// goes on until the tools arrive or the person stops it.
    func testAnInstallerNeverSeenLeavesTheWaitRunning() {
        let rig = WaitRig()
        rig.engine.installBrew()

        for _ in 1...(CommandLineTools.neverSeenAfter + 5) { XCTAssertTrue(rig.ticker.fire()) }

        XCTAssertEqual(rig.ticker.live, 1, "the wait ended over a window nobody saw close")
        XCTAssertTrue(rig.privileged.scripts.isEmpty)
    }

    // MARK: - The request itself is refused

    func testARefusedRequestWithNoToolsIsANamedFailure() async {
        for answer in [ToolsRequest.refused(1), .timedOut] {
            let rig = WaitRig()
            rig.tools.request = answer

            rig.engine.installBrew()

            let (state, _) = await rig.replayed()
            XCTAssertEqual(state?.phase, .failed, "\(answer)")
            XCTAssertEqual(state?.reason, .toolsNotInstalled, "\(answer)")
            XCTAssertEqual(rig.ticker.scheduled, 0, "\(answer): a wait was armed over a refused request")
            XCTAssertTrue(rig.privileged.scripts.isEmpty, "\(answer)")
        }
    }

    /// The request was refused because the tools had arrived by another road
    /// meanwhile: the person is not turned away from a Mac that has them.
    func testARefusedRequestOnAMacThatHasTheToolsByNowGoesOn() {
        let rig = WaitRig()
        rig.tools.request = .refused(1)
        rig.tools.onRequest = { [tools = rig.tools] in tools.gitExecutable = true }

        rig.engine.installBrew()

        XCTAssertEqual(rig.privileged.scripts.count, 1)
    }

    // MARK: - The wire

    /// A payload from the release before this field existed decodes with no
    /// waiting: the synthesised decoding reads the optional if present.
    func testAnOlderStateDecodesWithoutAWaitingField() throws {
        let old = Data(#"{"phase":"running","label":"install wget"}"#.utf8)
        let state = try JSONDecoder().decode(OpState.self, from: old)
        XCTAssertEqual(state.phase, .running)
        XCTAssertNil(state.waiting)
    }
}
