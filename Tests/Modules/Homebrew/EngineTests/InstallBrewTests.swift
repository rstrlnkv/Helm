import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// `installBrew` is the module's most dangerous path and had no test at all: it
/// builds a string a **root shell** evaluates (through the system's own admin
/// dialog) and then downloads and runs an installer off the network. Nothing
/// here executes any of that — the privileged runner and the process runner are
/// fakes that record what they were handed, which is the machine boundary this
/// suite must not cross.
///
/// The events are read back through the news's replay: `EngineNews<HomebrewNews>`
/// keeps the last event per name and replays it to a new subscriber, so what a
/// test sees is exactly what a page opened after the fact would see — the
/// final `opState` and the final console line.
final class InstallBrewTests: XCTestCase {

    // MARK: - Fakes

    /// Records every script it is asked to run as root and answers what the
    /// test says the person answered at the dialog. It never runs anything.
    private final class RecordingPrivileged: PrivilegedRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _scripts: [String] = []
        let answer: PrivilegedOutcome
        init(answer: PrivilegedOutcome) { self.answer = answer }
        var scripts: [String] { lock.lock(); defer { lock.unlock() }; return _scripts }
        func runAdmin(_ script: String) -> PrivilegedOutcome {
            lock.lock(); _scripts.append(script); lock.unlock()
            return answer
        }
    }

    // MARK: - Plumbing

    private func makeEngine(user: String, privileged: RecordingPrivileged,
                            runner: HangingRunner = HangingRunner(),
                            news: EngineNews<HomebrewNews> = EngineNews())
    -> (HomebrewEngine, EngineNews<HomebrewNews>) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: user,
                                    news: news)
        return (engine, news)
    }

    /// The news's replay, split by case: the latest `.state` and
    /// the latest `.line`. A sentinel emitted *before* subscribing marks
    /// where the replay ends, so the read is deterministic — everything the
    /// engine emitted happened synchronously before this call.
    private func replayed(_ news: EngineNews<HomebrewNews>) async -> (state: OpState?, busy: Bool) {
        let items = await replay(news)
        return (items.states.last, items.sawBusy)
    }

    // MARK: - The account name gate

    /// `user` is `NSUserName()`, and on a managed Mac that is whatever the
    /// directory says — including a name that is code once a root shell
    /// evaluates the string it sits in. The check must run *before* the dialog:
    /// a password prompt for a command that would then be refused teaches the
    /// person to type their password into prompts they cannot judge.
    func testAnImplausibleAccountNameNeverReachesTheRootShell() async {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, news) = makeEngine(user: "$(whoami)", privileged: privileged, runner: runner)

        engine.installBrew()

        XCTAssertEqual(privileged.scripts, [],
                       "an account name that is shell code was handed to the admin dialog")
        XCTAssertTrue(runner.streamCalls.isEmpty,
                      "the installer download started for an account the module refused")

        let (state, _) = await replayed(news)
        XCTAssertEqual(state?.phase, .failed,
                       "the refusal is invisible: the page shows a spinner or nothing at all")
        XCTAssertEqual(state?.reason, .unsupportedAccount,
                       "the refusal ends with a bare Failed pill and no sentence")

        // And the gate is released — a refusal that wedges `busy` kills the
        // module until relaunch.
        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamCalls.count, 1,
                       "the refused installBrew left the one-operation gate shut")
    }

    /// The names the guard must refuse are the ones that stop being data in a
    /// root shell line or in sudoers; the ones it must admit are real macOS
    /// short names. Both directions, or the guard could be `return false`. The
    /// hostile side is spelled as literals here, never derived from the
    /// production rule — a test whose two sides read one constant cannot fail.
    func testTheAccountNameGateCutsWhereRootSyntaxBegins() {
        for hostile in ["$(whoami)", "`id`", "a'b", "a;rm -rf /", "ALL", "-flag", "", "имя", "a b"] {
            XCTAssertFalse(AccountName.isPlausible(hostile),
                           "\(hostile.debugDescription) would be pasted into a root shell line")
        }
        for honest in ["tester", "r.strlnkv", "user_2", "mac-mini", "a"] {
            XCTAssertTrue(AccountName.isPlausible(honest),
                          "\(honest.debugDescription) is an ordinary short name and must install")
        }
    }

    // MARK: - The admin dialog

    /// The person pressed Cancel at the password dialog. Nothing may download,
    /// the page must say so, and the next attempt must be admitted.
    func testADeclinedDialogDownloadsNothingAndReleasesTheGate() async {
        let privileged = RecordingPrivileged(answer: .declined)
        let runner = HangingRunner()
        let (engine, news) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.installBrew()

        XCTAssertEqual(privileged.scripts.count, 1, "precondition: the dialog was asked")
        XCTAssertTrue(runner.streamCalls.isEmpty,
                      "the installer ran although the person declined the admin dialog")

        let (state, _) = await replayed(news)
        XCTAssertEqual(state?.phase, .failed, "a declined dialog must land as a failed state")
        XCTAssertEqual(state?.reason, .authorizationDeclined,
                       "the page cannot say «cancelled» without the reason — the English console "
                       + "line that used to say so is gone, the words are the page's")
        XCTAssertNil(state?.exitCode, "a cancelled dialog has no exit code to show")

        engine.installBrew()
        XCTAssertEqual(privileged.scripts.count, 2,
                       "declining the dialog wedged the gate: install Homebrew works once per launch")
    }

    /// What the root shell is handed: every tool by absolute path — the string
    /// is evaluated by a shell whose `PATH` any user process can rewrite via
    /// `launchctl setenv`, so a bare `mkdir` is whichever `mkdir` was planted —
    /// and the account name inside single quotes, where expansion stops.
    func testTheRootStringNamesToolsAbsolutelyAndQuotesTheAccount() {
        let privileged = RecordingPrivileged(answer: .declined)
        let (engine, _) = makeEngine(user: "helm.tester", privileged: privileged)

        engine.installBrew()

        guard let script = privileged.scripts.first else {
            return XCTFail("no script reached the privileged runner at all")
        }
        XCTAssertTrue(script.contains("/bin/mkdir -p /opt/homebrew"),
                      "mkdir is not absolute — a planted PATH decides what runs as root: \(script)")
        XCTAssertTrue(script.contains("/usr/sbin/chown"),
                      "chown is not absolute: \(script)")
        XCTAssertTrue(script.contains("'helm.tester':admin"),
                      "the account name is not single-quoted where the root shell reads it: \(script)")
        // The name appears exactly once, and that occurrence is the quoted one —
        // a second, bare occurrence would be the one that expands.
        XCTAssertEqual(script.components(separatedBy: "helm.tester").count - 1, 1,
                       "the account name appears more than once in the root string: \(script)")
    }

    // MARK: - The installer stage

    /// Download to a file, then run the file — never `eval "$(curl …)"`, where
    /// a failed download evaluates the empty string, exits 0, and the module
    /// reports a successful install of nothing. And `NONINTERACTIVE=1`, because
    /// there is no terminal for the installer to ask its questions in: without
    /// it the child waits for a keypress that can never come, forever, holding
    /// the busy gate (the operation has no deadline of its own; a Stop ends
    /// it, and so does switching the module off, which terminates the wrapper
    /// through `deactivate()`).
    func testTheInstallerIsDownloadedToAFileNeverEvaledFromTheNet() {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, _) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.installBrew()

        guard let call = runner.streamCalls.first else {
            return XCTFail("the installer stage never started after an accepted dialog")
        }
        XCTAssertEqual(call.launch, "/bin/bash")
        XCTAssertEqual(call.args.first, "-c")
        let script = call.args.dropFirst().joined()
        XCTAssertTrue(script.contains("-o"), "curl does not write to a file: \(script)")
        XCTAssertFalse(script.contains("eval"),
                       "the download is evaluated directly — an empty download exits 0: \(script)")
        XCTAssertTrue(script.contains("curl"), "nothing downloads the installer: \(script)")
        XCTAssertEqual(call.env["NONINTERACTIVE"], "1",
                       "the installer will stop at its own prompt with no terminal to answer it")
        XCTAssertEqual(call.env["HOMEBREW_NO_SUDO"], "1",
                       "the installer probes for sudo and, on a Mac with a NOPASSWD rule, calls one "
                       + "that has nothing to ask on")
        XCTAssertEqual(call.env, HomebrewEngine.installerEnvironment,
                       "the stream got an environment the engine does not declare")
    }

    /// The installer stage is not run as root: the admin dialog covers only the
    /// `mkdir`/`chown` preparation, and the download runs as the user. A root
    /// `curl | bash` of a network script would be the single worst line in the
    /// app.
    func testTheDownloadedInstallerRunsAsTheUserNotThroughTheDialog() {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, _) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.installBrew()

        XCTAssertEqual(privileged.scripts.count, 1,
                       "the privileged runner was asked more than once — something beyond "
                       + "the preparation reached root: \(privileged.scripts)")
        for script in privileged.scripts {
            XCTAssertFalse(script.contains("curl"),
                           "a network download is being handed to a root shell: \(script)")
            XCTAssertFalse(script.contains("bash"),
                           "a script interpreter is being handed to a root shell: \(script)")
        }
    }

    // MARK: - The one-operation gate

    /// `installBrew` shares the gate with the package operations, in both
    /// directions — and the refusal of a second `installBrew` happens *before*
    /// the dialog, or a person watching one install sees a second password
    /// prompt appear over it.
    func testInstallBrewHoldsTheGateAndIsRefusedBeforeASecondDialog() async {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, news) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.installBrew()
        XCTAssertEqual(runner.streamCalls.count, 1, "precondition: the installer is in flight")

        engine.installBrew()
        XCTAssertEqual(privileged.scripts.count, 1,
                       "a second admin dialog appeared while the first install was running")

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamCalls.count, 1,
                       "a brew operation ran beside the Homebrew installer")

        runner.finishAll(code: 0)
        let (state, _) = await replayed(news)
        XCTAssertEqual(state?.phase, .done)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamCalls.count, 2,
                       "the finished installer left the gate shut")
    }

    /// And the package operations hold it against `installBrew` too: while a
    /// `brew install` streams, pressing Install Homebrew must not put a
    /// password dialog on the screen.
    func testARunningOperationRefusesInstallBrewBeforeTheDialog() {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, _) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamCalls.count, 1, "precondition: the operation started")

        engine.installBrew()

        XCTAssertEqual(privileged.scripts, [],
                       "an admin password dialog appeared while a brew operation was running")
        XCTAssertEqual(runner.streamCalls.count, 1)
    }

    /// A failed installer reports the exit code it failed with, and the gate
    /// opens again — the retry is the whole recovery story here.
    func testAFailedInstallerReportsItsExitCodeAndReleasesTheGate() async {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, news) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.installBrew()
        runner.finishAll(code: 7)

        let (state, _) = await replayed(news)
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.exitCode, 7, "the page cannot say what happened without the code")
        XCTAssertEqual(state?.reason, .installerFailed,
                       "a failed installer is named, so the page does not draw a bare code")

        engine.installBrew()
        XCTAssertEqual(privileged.scripts.count, 2, "a failed install left the gate shut")
    }

    // MARK: - The busy refusal is visible

    /// The refusal of a second operation writes a line to the console — and it
    /// must **not** forge a `.failed` state: `opState` is level-triggered and
    /// replayed to late subscribers, so a `.failed` emitted about the *refused*
    /// press would tell a page reopened mid-operation that the running install
    /// had failed.
    func testABusyRefusalSaysSoWithoutForgingAFailedState() async {
        let privileged = RecordingPrivileged(answer: .done)
        let runner = HangingRunner()
        let (engine, news) = makeEngine(user: "tester", privileged: privileged, runner: runner)

        engine.install(name: "wget", isCask: false)
        engine.upgradeAll()   // refused: the install is still streaming

        let (state, busy) = await replayed(news)
        XCTAssertEqual(state?.phase, .running,
                       "the refusal overwrote the running state — a reopened page shows "
                       + "the live install as over")
        XCTAssertTrue(busy, "the refusal left no console line: the press did nothing visibly")
    }
}
