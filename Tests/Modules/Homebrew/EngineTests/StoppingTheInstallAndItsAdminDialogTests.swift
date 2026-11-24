// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A Stop pressed before the engine holds a child's handle still ends the
/// operation.**
///
/// `current` is set by `adopt`, after the launch. For `installBrew` the time
/// before it is the administrator password dialog, as long as a person takes to
/// find their password, with the page already showing a live Stop button. A
/// press there must be recorded, end the operation as stopped, and keep the
/// installer from being downloaded and run after the dialog.
///
/// `ScriptedPrivileged(holds: true)` stops inside `runAdmin` until the test says
/// the person answered, as the real dialog does; a fake that answers inline
/// cannot represent "the dialog is up and unanswered".
final class AStopBeforeTheChildExistsTests: XCTestCase {

    // MARK: - Plumbing

    /// Starts `installBrew` on a thread of its own, since it blocks inside the
    /// dialog, and hands back a way to wait for it to return.
    private func startInstallBrew(_ engine: HomebrewEngine) -> DispatchSemaphore {
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            engine.installBrew()
            returned.signal()
        }
        return returned
    }

    // MARK: - The window

    func testAStopPressedAtTheDialogDoesNotThenRunTheInstaller() {
        let privileged = ScriptedPrivileged(reply: .done, holds: true)
        let runner = ScriptedRunner(streams: .hold)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        XCTAssertEqual(privileged.scripts.count, 1,
                       "precondition: the operation is running and the dialog is up")

        engine.stop()          // the person presses Stop while the dialog is up
        privileged.answer()    // …and then types their password

        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")
        XCTAssertTrue(runner.streamCalls.isEmpty, """
            Stop was pressed and the module then downloaded and ran the Homebrew \
            installer anyway: \(runner.streamCalls.map(\.launch))
            """)
    }

    func testAStopPressedAtTheDialogEndsTheOperation() async {
        let privileged = ScriptedPrivileged(reply: .done, holds: true)
        let runner = ScriptedRunner(streams: .hold)
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: news, marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        engine.stop()
        privileged.answer()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")

        let state = await lastOpState(news)
        XCTAssertNotEqual(state?.phase, .running, """
            the page is still showing a running operation with a Stop button \
            that has already been pressed and did nothing
            """)
        XCTAssertEqual(state?.reason, .stopped,
                       "the end the person asked for is not named as one")
    }

    // MARK: - Controls

    /// Control: once the child exists the press reaches it, so a failure above
    /// is about the time before `adopt`, not about `stop` in general.
    func testOnceTheInstallerIsRunningStopReachesIt() {
        let privileged = ScriptedPrivileged(reply: .done)
        let runner = ScriptedRunner(streams: .hold)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())

        engine.installBrew()
        XCTAssertEqual(runner.handles.count, 1, "precondition: the installer is streaming")

        engine.stop()
        XCTAssertTrue(runner.handles[0].terminated,
                      "Stop did not reach the running Homebrew installer")
    }

    /// And a dialog nobody stopped still installs: the guard being asked for
    /// must not become "installBrew never runs the installer".
    func testAnUnstoppedDialogStillRunsTheInstaller() {
        let privileged = ScriptedPrivileged(reply: .done, holds: true)
        let runner = ScriptedRunner(streams: .hold)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        privileged.answer()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")

        XCTAssertEqual(runner.streamCalls.count, 1,
                       "nobody pressed Stop and the installer did not run")
        XCTAssertEqual(runner.streamCalls.first?.launch, "/bin/bash")
    }
}

/// **A Stop that lands while `runner.stream` is launching the child reaches
/// that child.**
///
/// `stop` finds `current` still nil and terminates nothing; `adopt` must then
/// see the recorded press and end the child it is handed, or the page says
/// «Stopped» while `brew install` runs to completion. `stop` comes from a button
/// press on another thread, so nothing orders it against `runOp`.
///
/// The fake presses Stop from inside `stream`, the only way to land exactly
/// there.
final class AStopDuringTheLaunchItselfIsNotLostTests: XCTestCase {

    func testAStopPressedWhileTheChildIsBeingLaunchedStillReachesIt() {
        let runner = ScriptedRunner(streams: .hold)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())
        runner.onStream = { [weak engine] in engine?.stop() }

        engine.install(name: "wget", isCask: false)

        XCTAssertEqual(runner.handles.count, 1, "precondition: the child was launched")
        XCTAssertTrue(runner.handles[0].terminated, """
            Stop was pressed while the child was being launched and reached \
            nothing: `current` was still nil at the press, and the handle that \
            arrived a moment later was adopted as if nobody had asked
            """)
    }

    /// The control: a launch nobody interrupted keeps its child. Without it the
    /// assertion above holds on an engine that terminates everything it starts.
    func testAnUninterruptedLaunchKeepsItsChild() {
        let runner = ScriptedRunner(streams: .hold)
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())

        engine.install(name: "wget", isCask: false)

        XCTAssertEqual(runner.handles.count, 1)
        XCTAssertFalse(runner.handles[0].terminated,
                       "nobody pressed Stop and the child was terminated anyway")
    }
}

/// **Stop during `install.sh` has to reach `install.sh`.**
///
/// The handle Stop holds is the `bash -c` that wraps the download and the
/// installer. A signal that reaches only the wrapper leaves the inner
/// `bash "$script"` writing into `/opt/homebrew` after the page said stopped,
/// and a wrapper that dies before its `rm` leaves the script in the temporary
/// folder. So the checks ask for the whole outcome: the stream ends, nothing the
/// installer started is alive, and the script is gone.
///
/// Nothing here reaches the network or root. The command is the engine's own,
/// rehosted as `TheDownloadedInstallerIsTidiedAwayTests` does, and launched
/// through the real `ShellProcessRunner.stream`. The stand-in installer records
/// its own pid and that of a child it starts, then waits.
final class AStopReachesTheInstallerItselfTests: XCTestCase {

    private func pid(in file: URL) -> pid_t? {
        (try? String(contentsOf: file, encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    func testStopKillsTheInstallerAndWhatItStartedAndRemovesTheScript() async throws {
        let root = scratchDirectory("brew-installer-stop")
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let innerPID = root.appendingPathComponent("installer.pid")
        let grandchildPID = root.appendingPathComponent("grandchild.pid")
        let installer = root.appendingPathComponent("install.sh")
        try """
        #!/bin/bash
        echo $$ > \(innerPID.path)
        /bin/sleep 60 &
        echo $! > \(grandchildPID.path)
        wait
        """.write(to: installer, atomically: true, encoding: .utf8)

        // A red run must not leave a minute-long sleep behind it.
        addTeardownBlock {
            for file in [innerPID, grandchildPID] {
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                if let p = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   kill(p, 0) == 0 { kill(p, SIGKILL) }
            }
        }

        let command = try rehosted(composedInstaller(), source: installer, temporaries: temporaries)
        let (handle, run) = start(command)

        await waitUntilReached("precondition: the stand-in installer started", within: .seconds(10)) {
            pid(in: innerPID) != nil && pid(in: grandchildPID) != nil
        }
        let inner = try XCTUnwrap(pid(in: innerPID))
        let grandchild = try XCTUnwrap(pid(in: grandchildPID))
        XCTAssertTrue(isAlive(inner) && isAlive(grandchild), "precondition: both are running")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaries.path).count, 1,
                       "precondition: the downloaded script is on disk while the installer runs")

        handle.terminate()                                   // what Stop does

        XCTAssertEqual(run.finished(within: 10), .success,
                       "the stream never ended: something the wrapper started still holds its pipe")
        await waitUntilReached("the installer stopped running after Stop", within: .seconds(5)) { !isAlive(inner) }
        await waitUntilReached("a process the installer started stopped running after Stop", within: .seconds(5)) { !isAlive(grandchild) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaries.path), [],
                       "the downloaded installer was left in the temporary folder after Stop")
    }
}

/// **Every place a Stop or a switch-off can land in `installBrew` ends the
/// operation exactly once, raises nothing after it, and leaves the gate open.**
///
/// Two terminal states from one operation are two `concludeOp`s, which close the
/// activity phase twice and run the refresh twice. Each ending fires from inside
/// the port call the engine makes at that moment.
///
/// `deactivate()` while `install.sh` runs ends it the way Stop does; while the
/// password dialog is up it leaves nothing to launch after it.
final class EveryStopPointEndsTheInstallOnceTests: XCTestCase {

    /// Every port named: Apple's tools, time, root, the runner, the marker.
    private struct Rig {
        let tools: FakeCommandLineTools
        let ticker = FakeWaitTicker()
        let privileged: ScriptedPrivileged
        let runner = ScriptedRunner(streams: .hold)
        let news = EngineNews<HomebrewNews>()
        let engine: HomebrewEngine
        /// Subscribed before anything is pressed, so it holds every state the
        /// engine sent and not only the last.
        let tape: AsyncStream<HomebrewNews>

        init(holdsDialog: Bool = false) {
            tools = FakeCommandLineTools()
            privileged = ScriptedPrivileged(reply: .done, holds: holdsDialog)
            engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: news, marker: InMemoryOpMarker(),
                                    tools: tools, ticker: ticker)
            tape = news.stream()
        }

        /// Every `opState` sent since the rig was built, in order.
        func states() async -> [OpState] { await replay(news, from: tape).states }
    }

    private enum Ending: CaseIterable { case stop, switchOff }

    private func end(_ engine: HomebrewEngine?, _ ending: Ending) {
        switch ending {
        case .stop: engine?.stop()
        case .switchOff: engine?.deactivate()
        }
    }

    override func setUp() {
        super.setUp()
        _ = HelmLog.shared.recentEntries()          // seed from the file now, not later
        tailTheLog()
    }

    private var homebrewLines: [String] {
        loggedLines(HomebrewEngine.moduleID)
    }

    // MARK: - Each read point

    /// Where the ending lands, named by the port call it lands inside.
    private enum Point: CaseIterable {
        /// The press's own reading of the tools (no tools on this Mac).
        case pressReading
        /// The look at whether Apple's window is already open.
        case windowLook
        /// `xcode-select --install` being filed.
        case request
        /// The reading one line before the dialog (tools present at the press).
        case readingBeforeDialog
        /// The tick's closed-window verdict re-reading the tools in full.
        case closedWindowReReading
    }

    private func arm(_ rig: Rig, at point: Point, with ending: Ending) -> LockedCount {
        let hit = LockedCount()
        let reads = LockedCount()
        let fire = { [weak engine = rig.engine] in _ = hit.next(); self.end(engine, ending) }
        switch point {
        case .pressReading:
            rig.tools.onRead = { [tools = rig.tools] in tools.onRead = nil; fire() }
        case .windowLook:
            rig.tools.onInstallerRead = { [tools = rig.tools] in tools.onInstallerRead = nil; fire() }
        case .request:
            rig.tools.onRequest = { [tools = rig.tools] in tools.onRequest = nil; fire() }
        case .readingBeforeDialog:
            rig.tools.gitExecutable = true
            rig.tools.onRead = { [tools = rig.tools] in
                guard reads.next() == 2 else { return }
                tools.onRead = nil; fire()
            }
        case .closedWindowReReading:
            // Read 1 the press's, 2 and 3 the two ticks', 4 the verdict's re-reading.
            rig.tools.onRead = { [tools = rig.tools] in
                guard reads.next() == 4 else { return }
                tools.onRead = nil; fire()
            }
        }
        return hit
    }

    private func drive(_ rig: Rig, to point: Point) {
        rig.engine.installBrew()
        guard point == .closedWindowReReading else { return }
        rig.tools.installerRunning = true
        rig.ticker.fire()                                   // the window is seen
        rig.tools.installerRunning = false
        rig.ticker.fire()                                   // and closed
    }

    func testEveryEndingAtEveryReadPointEndsOnceAsStoppedAndReopensTheGate() async {
        for point in Point.allCases {
            for ending in Ending.allCases {
                let what = "\(ending) at \(point)"
                let rig = Rig()
                let hit = arm(rig, at: point, with: ending)

                drive(rig, to: point)

                XCTAssertEqual(hit.value, 1, "\(what): precondition — the ending never landed")
                XCTAssertTrue(rig.privileged.scripts.isEmpty, "\(what): the administrator dialog rose")
                XCTAssertTrue(rig.runner.streamed.isEmpty, "\(what): the installer was launched")
                XCTAssertEqual(rig.ticker.live, 0, "\(what): a wait is still armed")
                let expectedRequests = [.request, .closedWindowReReading].contains(point) ? 1 : 0
                XCTAssertEqual(rig.tools.requestCount, expectedRequests,
                               "\(what): Apple's window was asked for after the ending")

                // The gate: the module comes back, and the next press, on a Mac that now has the tools, reaches the dialog.
                rig.engine.activate()
                rig.tools.onRead = nil; rig.tools.onInstallerRead = nil; rig.tools.onRequest = nil
                rig.tools.gitExecutable = true
                rig.engine.installBrew()
                XCTAssertEqual(rig.privileged.scripts.count, 1, "\(what): the gate stayed shut")

                let terminal = await rig.states().filter { $0.phase != .running }
                // The second press's own ending has not come yet (its child is live).
                XCTAssertEqual(terminal.count, 1,
                               "\(what): the operation was ended \(terminal.count) times: \(terminal)")
                XCTAssertEqual(terminal.first?.reason, .stopped, "\(what): not said as a stop: \(terminal)")
                XCTAssertNil(terminal.first?.exitCode, "\(what): an exit code for a child that never ran")
                rig.runner.finishAll(code: 0)
            }
        }
    }

    /// The two endings of a wait say different sentences in the log, and a
    /// person reading it tells them apart by those words.
    func testEachEndingOfTheWaitSaysItsOwnSentenceInTheLog() {
        for (ending, sentence) in [(Ending.stop, "install Homebrew stopped waiting"),
                                   (Ending.switchOff, "install Homebrew stopped waiting: module switched off")] {
            HelmLog.shared.clearTail()
            let rig = Rig()
            rig.engine.installBrew()
            XCTAssertEqual(rig.ticker.live, 1, "\(ending): precondition — the install is waiting")

            end(rig.engine, ending)

            XCTAssertTrue(homebrewLines.contains(sentence), "\(ending): \(homebrewLines)")
        }
    }

    // MARK: - A switch-off while install.sh runs

    /// `deactivate()` with the installer running ends it the way Stop does:
    /// one TERM to the handle, the exit read as the person's stop, the log
    /// line said, and the gate open for the next press.
    func testASwitchOffDuringTheInstallerEndsItAsStopped() async {
        let rig = Rig()
        rig.tools.gitExecutable = true
        rig.engine.installBrew()
        XCTAssertEqual(rig.runner.handles.count, 1, "precondition: install.sh is running")

        rig.engine.deactivate()

        XCTAssertEqual(rig.runner.handles.first?.terminations, 1,
                       "a module switched off left install.sh running")
        rig.runner.finishAll(code: 143)                           // the wrapper's TERM trap
        let terminal = await rig.states().filter { $0.phase != .running }
        XCTAssertEqual(terminal.count, 1, "ended \(terminal.count) times: \(terminal)")
        XCTAssertEqual(terminal.first?.reason, .stopped,
                       "a switch-off read as the installer failing: \(terminal)")
        XCTAssertEqual(terminal.first?.exitCode, 143)
        XCTAssertTrue(homebrewLines.contains("install Homebrew stopped on request, exit 143"),
                      "the log does not say who ended it: \(homebrewLines)")

        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 1, "an operation was launched for a module that is off")
        rig.engine.activate()
        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 2, "the gate stayed shut after the module came back")
    }

    /// A second switch-off, or a Stop after it, while the installer is still
    /// dying: the handle is asked again, the operation still ends once.
    func testASecondEndingWhileTheInstallerDiesEndsItOnce() async {
        let rig = Rig()
        rig.tools.gitExecutable = true
        rig.engine.installBrew()

        rig.engine.deactivate()
        rig.engine.stop()
        rig.engine.deactivate()
        rig.runner.finishAll(code: 143)

        let terminal = await rig.states().filter { $0.phase != .running }
        XCTAssertEqual(terminal.count, 1, "ended \(terminal.count) times: \(terminal)")
        XCTAssertEqual(terminal.first?.reason, .stopped)
    }

    /// `deactivate()` while the password dialog is up: there is no wait and no
    /// child, and the dialog cannot be withdrawn — but whatever it answers,
    /// nothing is launched after it for a module that is off.
    func testASwitchOffWhileTheDialogIsUpLaunchesNothingAfterIt() async {
        let rig = Rig(holdsDialog: true)
        rig.tools.gitExecutable = true
        let pressed = expectation(description: "the press returned")
        DispatchQueue.global().async { [engine = rig.engine] in engine.installBrew(); pressed.fulfill() }
        rig.privileged.waitUntilOnScreen()

        rig.engine.deactivate()
        rig.privileged.answer()
        await fulfillment(of: [pressed], timeout: 5)

        XCTAssertTrue(rig.runner.streamed.isEmpty, "install.sh ran for a module switched off during the dialog")
        let terminal = await rig.states().filter { $0.phase != .running }
        XCTAssertEqual(terminal.count, 1, "ended \(terminal.count) times: \(terminal)")
        XCTAssertEqual(terminal.first?.reason, .stopped)
        rig.engine.activate()
        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 1, "the gate stayed shut after the module came back")
    }
}

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
        XCTAssertEqual(rig.runner.streamed.count, 1)
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
        XCTAssertTrue(rig.runner.streamed.isEmpty)
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
        let (state, busy) = await rig.replayed()
        XCTAssertEqual(state?.waiting, .commandLineTools,
                       "the refusal overwrote the waiting state")
        XCTAssertTrue(busy, "the refused press left no line")
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
        let entries = rig.journal.value
        XCTAssertEqual(Array(entries.suffix(2)), ["read", "admin"],
                       "the dialog was not directly preceded by a reading of the tools: \(entries)")
        XCTAssertEqual(rig.runner.streamed.count, 1)
        XCTAssertEqual(rig.runner.streamCalls.first?.env, HomebrewEngine.installerEnvironment)
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
}

/// Ending the wait for Apple's tools by any road — Stop, a module switched off,
/// an engine that is going — releases the tick, and a tick that lands anyway
/// finds nothing to act on. The road it must never lead to is a password dialog:
/// from a page the person stopped, from a module that is off, or on behalf of an
/// operation that is over.
final class StoppingTheWaitRaisesNoDialogTests: XCTestCase {

    /// «Stop waiting» is the existing `.stop`: no new act. The
    /// operation ends as stopped, the tick is released, and a tick that was
    /// already in flight does not go on to the dialog.
    func testStopWaitingEndsTheOperationAndNoTickRaisesTheDialog() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        XCTAssertEqual(rig.ticker.live, 1, "precondition: the wait is armed")

        rig.engine.stop()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertNil(state?.waiting)
        XCTAssertEqual(rig.ticker.live, 0, "Stop left a tick armed")

        rig.tools.gitExecutable = true          // Apple's window finishes anyway
        rig.ticker.fireInFlight(0)              // the tick that was already on its way
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the password dialog rose after the person stopped waiting")
        XCTAssertTrue(rig.runner.streamed.isEmpty)

        rig.engine.installBrew()
        XCTAssertEqual(rig.privileged.scripts.count, 1,
                       "the stopped operation left the gate shut, or the next press was not admitted")
    }

    /// A tick from an old wait, in flight when the person stopped and pressed
    /// again, must not act for the new one: the token in the field is the *new*
    /// wait's, and only the generation says the tick is not its own.
    func testATickFromAnEarlierWaitCannotActForTheNextOne() {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.engine.stop()
        rig.engine.installBrew()
        XCTAssertEqual(rig.ticker.live, 1, "precondition: a second wait is armed")
        rig.tools.gitExecutable = true

        rig.ticker.fireInFlight(0)

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a tick of the stopped wait ended the new one and raised its dialog")
        XCTAssertEqual(rig.ticker.live, 1, "the old tick disarmed the new wait")
    }

    /// A module switched off in the middle of the wait: the same ending, the
    /// gate opens, and no tick is left to raise a dialog from a module that is off.
    func testSwitchingTheModuleOffMidWaitEndsItAndOpensTheGate() async {
        let rig = WaitRig()
        rig.engine.installBrew()

        rig.engine.deactivate()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.live, 0, "a tick outlived the module's deactivation")
        rig.tools.gitExecutable = true
        rig.ticker.fireInFlight(0)
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a module that is switched off raised the administrator dialog")

        rig.engine.activate()
        rig.engine.installBrew()
        XCTAssertEqual(rig.privileged.scripts.count, 1, "deactivation left the gate shut")
    }

    /// The backstop for the routes that never call `deactivate()`: an engine
    /// that is dropped releases its tick, and a tick that lands afterwards
    /// finds no engine.
    func testDroppingTheEngineMidWaitReleasesTheTick() {
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done)
        weak var weakEngine: HomebrewEngine?
        autoreleasepool {
            let engine = HomebrewEngine(locator: FixedLocator(), runner: ScriptedRunner(streams: .hold),
                                        privileged: privileged, user: "tester",
                                        news: EngineNews(), marker: InMemoryOpMarker(),
                                        tools: tools, ticker: ticker)
            engine.installBrew()
            weakEngine = engine
            XCTAssertEqual(ticker.live, 1, "precondition: the wait is armed")
        }

        XCTAssertNil(weakEngine, "the wait keeps the engine alive: the token's block holds it strongly")
        XCTAssertEqual(ticker.live, 0, "the engine went and its tick is still armed")
        tools.gitExecutable = true
        ticker.fireInFlight(0)
        XCTAssertTrue(privileged.scripts.isEmpty, "a tick reached a dialog through an engine that was gone")
    }

    /// A Stop that lands while the request is still being filed — before the
    /// wait exists, so there is no token to take. It leaves the flag, and the
    /// press reads it: no wait is armed, and the operation ends as stopped.
    func testAStopWhileTheRequestIsBeingFiledArmsNoWait() async {
        let rig = WaitRig()
        rig.tools.onRequest = { [engine = rig.engine] in engine.stop() }

        rig.engine.installBrew()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.scheduled, 0, "a wait was armed after the person had stopped")
        XCTAssertTrue(rig.privileged.scripts.isEmpty)
    }

    /// A Stop that lands while a tick is reading — the token is the tick's to
    /// keep or the press's to take, and whoever loses does nothing.
    func testAStopWhileATickIsReadingEndsTheOperationAndTheTickDoesNothing() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.tools.gitExecutable = true
        rig.tools.onInstallerRead = { [engine = rig.engine] in engine.stop() }

        rig.ticker.fire()

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a Stop pressed during the tick did not stop the dialog")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.live, 0)
    }

    /// A Stop that lands after the busy gate is taken and before the dialog,
    /// with the tools already there — no wait exists and no token can be taken,
    /// so the press leaves only the flag. The dialog is still not to be raised.
    func testAStopBetweenThePressAndTheDialogRaisesNoDialog() async {
        let rig = WaitRig()
        rig.tools.gitExecutable = true
        rig.tools.onRead = { [engine = rig.engine, tools = rig.tools] in
            tools.onRead = nil
            engine.stop()
        }

        rig.engine.installBrew()

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a Stop pressed before the dialog did not stop the dialog")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
    }
}

/// The moments around the wait for Apple's tools where an ending can land and
/// find nothing to take: no wait armed yet, or the wait already taken by the
/// tick that is on its way to the dialog.
///
/// After such an ending the person gets neither Apple's window nor an
/// administrator dialog. Every hook fires from inside a port call the engine
/// makes at that moment, so the ending lands on the thread and at the line it
/// would in the app.
final class TheGapsAroundTheWaitRaiseNoDialogTests: XCTestCase {

    // MARK: - A switch-off that finds no wait to take

    /// `deactivate()` while `xcode-select --install` is still being filed (the
    /// real port gives it thirty seconds). There is no token yet, so the
    /// switch-off takes nothing — and the press must not then arm a wait whose
    /// tick raises the password dialog for a module that is off.
    func testASwitchOffWhileTheRequestIsBeingFiledArmsNoWait() async {
        let rig = WaitRig()
        rig.tools.onRequest = { [weak engine = rig.engine] in engine?.deactivate() }

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 1, "precondition: the press reached the request")
        XCTAssertEqual(rig.ticker.live, 0,
                       "a wait was armed for a module that was switched off while the request was filed")
        rig.tools.gitExecutable = true          // Apple's window finishes
        rig.ticker.fire()
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a module switched off mid-request raised the administrator dialog")
        let (state, _) = await rig.replayed()
        XCTAssertNotEqual(state?.phase, .running,
                          "a switched-off module's operation is still running on its page")
    }

    /// The tick has taken the token (verdict: the tools arrived) and is on its
    /// way to the dialog; `deactivate()` lands during the fresh reading taken
    /// one line before it. The switch-off finds no token, so the dialog is up
    /// for a module that is off.
    func testASwitchOffBetweenTheVerdictAndTheDialogRaisesNoDialog() {
        let rig = WaitRig()
        rig.engine.installBrew()
        XCTAssertEqual(rig.ticker.live, 1, "precondition: the wait is armed")
        rig.tools.gitExecutable = true
        let reads = LockedCount()
        // Read 1 is the tick's own look at `git`; read 2 is the reading one
        // line before the dialog, after the tick has taken the token.
        rig.tools.onRead = { [weak engine = rig.engine, tools = rig.tools] in
            guard reads.next() == 2 else { return }
            tools.onRead = nil
            engine?.deactivate()
        }

        rig.ticker.fire()

        XCTAssertGreaterThanOrEqual(reads.next(), 3, "precondition: the fresh reading was taken")
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the administrator dialog rose after the module was switched off")
        XCTAssertTrue(rig.runner.streamed.isEmpty, "the installer ran for a module that is off")
    }

    /// The same moment on the host's own route: `ModuleHost.disable` calls
    /// `deactivate()` and drops the engine. The tick holds the engine for as
    /// long as it runs, so dropping it is no backstop here.
    func testAnEngineSwitchedOffAndDroppedBetweenTheVerdictAndTheDialogRaisesNoDialog() {
        final class Host: @unchecked Sendable { var engine: HomebrewEngine? }
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done)
        let host = Host()
        host.engine = HomebrewEngine(locator: FixedLocator(), runner: ScriptedRunner(streams: .hold),
                                     privileged: privileged, user: "tester",
                                     news: EngineNews(), marker: InMemoryOpMarker(),
                                     tools: tools, ticker: ticker)
        host.engine?.installBrew()
        XCTAssertEqual(ticker.live, 1, "precondition: the wait is armed")
        tools.gitExecutable = true
        let reads = LockedCount()
        tools.onRead = { [host, tools] in
            guard reads.next() == 2 else { return }
            tools.onRead = nil
            host.engine?.deactivate()
            host.engine = nil
        }

        ticker.fire()

        XCTAssertNil(host.engine, "precondition: the host let the engine go")
        XCTAssertTrue(privileged.scripts.isEmpty,
                      "a module the host had switched off and dropped raised the administrator dialog")
    }

    /// The switch-off during the request on the host's own route, where the
    /// engine is dropped as well (the press holds it until it returns): with the
    /// engine gone, no tick is left live and the dialog stays down.
    func testAnEngineSwitchedOffAndDroppedDuringTheRequestLeavesNoTick() {
        final class Host: @unchecked Sendable { var engine: HomebrewEngine? }
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done)
        let host = Host()
        weak var gone: HomebrewEngine?
        autoreleasepool {
            host.engine = HomebrewEngine(locator: FixedLocator(), runner: ScriptedRunner(streams: .hold),
                                         privileged: privileged, user: "tester",
                                         news: EngineNews(), marker: InMemoryOpMarker(),
                                         tools: tools, ticker: ticker)
            gone = host.engine
            tools.onRequest = { [host] in
                host.engine?.deactivate()
                host.engine = nil
            }
            // Held for the press, as `offTheCooperativePool { self.installBrew() }` holds it.
            let pressing = host.engine
            pressing?.installBrew()
        }

        XCTAssertEqual(tools.requestCount, 1, "precondition: the press reached the request")
        XCTAssertNil(gone, "precondition: the engine went once the press returned")
        XCTAssertEqual(ticker.live, 0, "the dropped engine's wait is still armed")
        tools.gitExecutable = true
        ticker.fire()
        XCTAssertTrue(privileged.scripts.isEmpty)
    }

    // MARK: - A reading narrower than the press's

    /// The tick looks only at the fixed `git`, to spend no process per tick;
    /// the press and the refused-request road read `xcode-select -p` as well.
    /// A window seen and closed on a Mac whose tools are Xcode's by then —
    /// the person cancelled Apple's download and selected an Xcode — is told
    /// «the tools were not installed» over a Mac the press itself would have
    /// gone straight on from.
    func testAWindowClosedOnAMacWhoseToolsAreNowXcodesIsNotToldTheyAreMissing() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.ticker.fire()                              // the window is seen
        let xcode = "/Applications/Xcode.app/Contents/Developer"
        rig.tools.selected = xcode + "\n"
        rig.tools.executables = [xcode + "/usr/bin/git"]
        rig.tools.installerRunning = false             // and closed

        rig.ticker.fire()

        let (state, _) = await rig.replayed()
        XCTAssertNotEqual(state?.reason, .toolsNotInstalled,
                          "the page says the tools are missing on a Mac where the press would find them")
    }

    // MARK: - Every ending without the tools reopens the gate

    /// Each road that ends without Homebrew and without a child: the state is
    /// named *and* the next press is admitted — a second request filed, or the
    /// dialog reached. A named state over a shut gate reads right on the page
    /// and leaves the button doing nothing for the life of the app.
    func testEveryEndingWithoutAChildReopensTheGate() {
        for answer in [ToolsRequest.refused(1), .timedOut] {
            let rig = WaitRig()
            rig.tools.request = answer
            rig.engine.installBrew()
            XCTAssertEqual(rig.tools.requestCount, 1, "\(answer): precondition")
            rig.engine.installBrew()
            XCTAssertEqual(rig.tools.requestCount, 2, "\(answer): the gate stayed shut after the request ended")
        }

        // The tools arrived, then were gone again by the reading before the dialog.
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.gitExecutable = true
        let reads = LockedCount()
        rig.tools.onRead = { [tools = rig.tools] in
            // Read 1 is the tick's and finds `git`; read 2, before the dialog, does not.
            guard reads.next() == 2 else { return }
            tools.onRead = nil
            tools.gitExecutable = false
        }
        rig.ticker.fire()
        XCTAssertTrue(rig.privileged.scripts.isEmpty, "precondition: no dialog over missing tools")
        rig.tools.gitExecutable = true
        rig.engine.installBrew()
        XCTAssertEqual(rig.privileged.scripts.count, 1, "the gate stayed shut after the tools were missed")
    }

    // MARK: - A Stop that finds no wait to take

    /// Stop pressed while the reading one line before the dialog is taken. On
    /// a Mac whose tools are Xcode's that reading is `xcode-select -p`, a
    /// process with ten seconds of deadline; the Stop check sits *before* it,
    /// so a Stop landing inside it is read by nothing until after the dialog.
    func testAStopDuringTheReadingBeforeTheDialogRaisesNoDialog() async {
        let rig = WaitRig()
        rig.tools.gitExecutable = true
        let reads = LockedCount()
        // Read 1 is the press's; read 2 is the one inside the step to the dialog.
        rig.tools.onRead = { [weak engine = rig.engine, tools = rig.tools] in
            guard reads.next() == 2 else { return }
            tools.onRead = nil
            engine?.stop()
        }

        rig.engine.installBrew()

        XCTAssertGreaterThanOrEqual(reads.next(), 3, "precondition: the fresh reading was taken")
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the administrator dialog rose after the person pressed Stop")
        XCTAssertTrue(rig.runner.streamed.isEmpty)
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
    }

    /// Stop pressed before the request is filed — while the press is still
    /// reading whether the tools are there (on a Mac without the fixed `git`
    /// that is `xcode-select -p`) or whether Apple's window is open. The
    /// person said stop, and Apple's window must not open after it.
    func testAStopBeforeTheRequestIsFiledAsksAppleForNothing() async {
        let rig = WaitRig()
        rig.tools.onRead = { [weak engine = rig.engine, tools = rig.tools] in
            tools.onRead = nil
            engine?.stop()
        }

        rig.engine.installBrew()

        XCTAssertEqual(rig.ticker.scheduled, 0, "precondition: no wait outlived the Stop")
        XCTAssertEqual(rig.tools.requestCount, 0,
                       "Apple's installer was asked for after the person pressed Stop")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
    }

    /// The same moment for a module switched off: nothing may be asked of
    /// Apple, and nothing may be left waiting, on behalf of a module that is off.
    func testASwitchOffBeforeTheRequestIsFiledAsksAppleForNothing() {
        let rig = WaitRig()
        rig.tools.onRead = { [weak engine = rig.engine, tools = rig.tools] in
            tools.onRead = nil
            engine?.deactivate()
        }

        rig.engine.installBrew()

        XCTAssertEqual(rig.tools.requestCount, 0,
                       "Apple's installer was asked for after the module was switched off")
        XCTAssertEqual(rig.ticker.live, 0, "a wait was armed for a module that is off")
    }

    // MARK: - No port under the engine's lock

    /// Stands in for `installerIsRunning`'s hop to the main thread: every port
    /// call first asks the engine for something that takes its lock, from
    /// another thread, and waits for the answer. A port called under the lock
    /// is a main thread that never answers — here, a second that runs out.
    private final class LockProbe: @unchecked Sendable {
        private let lock = NSLock()
        weak var engine: HomebrewEngine?
        private var _asked: [String: Int] = [:]
        private var _underLock: Set<String> = []
        var asked: [String: Int] { lock.lock(); defer { lock.unlock() }; return _asked }
        var underLock: Set<String> { lock.lock(); defer { lock.unlock() }; return _underLock }

        func probe(_ name: String) {
            guard let engine else { return }
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { _ = engine.status(); answered.signal() }
            let timedOut = answered.wait(timeout: .now() + 1) == .timedOut
            lock.lock()
            _asked[name, default: 0] += 1
            if timedOut { _underLock.insert(name) }
            lock.unlock()
        }
    }

    private final class ProbedTools: CommandLineToolsPort, @unchecked Sendable {
        let inner: FakeCommandLineTools
        let probe: LockProbe
        init(_ inner: FakeCommandLineTools, _ probe: LockProbe) { self.inner = inner; self.probe = probe }
        func isExecutable(_ path: String) -> Bool { probe.probe("isExecutable"); return inner.isExecutable(path) }
        func selectedDeveloperDirectory() -> String? { probe.probe("selectedDeveloperDirectory"); return inner.selectedDeveloperDirectory() }
        func requestInstall() -> ToolsRequest { probe.probe("requestInstall"); return inner.requestInstall() }
        func installerIsRunning() -> Bool { probe.probe("installerIsRunning"); return inner.installerIsRunning() }
    }

    private final class ProbedPrivileged: PrivilegedRunner, @unchecked Sendable {
        let probe: LockProbe
        init(_ probe: LockProbe) { self.probe = probe }
        func runAdmin(_ script: String) -> PrivilegedOutcome { probe.probe("runAdmin"); return .done }
    }

    /// The press, a tick that keeps waiting, and a tick that goes on to the
    /// dialog: every call of the four tools questions and of root is made at
    /// least once, and none of them with the engine's lock held.
    func testNoPortIsAskedWithTheEngineLockHeld() {
        let probe = LockProbe()
        let fake = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: ScriptedRunner(streams: .hold),
                                    privileged: ProbedPrivileged(probe), user: "tester",
                                    news: EngineNews(), marker: InMemoryOpMarker(),
                                    tools: ProbedTools(fake, probe), ticker: ticker)
        probe.engine = engine

        engine.installBrew()                     // no tools, no window: reads, request, wait
        fake.installerRunning = true
        XCTAssertTrue(ticker.fire(), "precondition: the wait was armed")      // keeps waiting
        fake.gitExecutable = true
        XCTAssertTrue(ticker.fire(), "precondition: the wait went on")        // arrival → dialog

        let asked = probe.asked
        for port in ["isExecutable", "selectedDeveloperDirectory", "requestInstall",
                     "installerIsRunning", "runAdmin"] {
            XCTAssertGreaterThan(asked[port] ?? 0, 0, "precondition: \(port) was never called, so it proves nothing")
        }
        XCTAssertEqual(probe.underLock, [],
                       "called with the engine's lock held — the real installerIsRunning hops to main, "
                       + "and main waiting for that lock is a hang")
    }
}

/// **How far a Stop reaches, measured at both ends of the port.**
///
/// The engine names a `StopReach` per launch and the real runner acts on it.
/// A fake that implements only the `stream` with no `reach:` label never sees
/// the reach, so the first case records it at the port; the rest run the real
/// `ShellProcessRunner` and read what a Stop reached.
///
/// The last two cases stop the engine's own `install.sh` wrapper, rehosted as
/// `TheInstallerWrapperKeepsItsWordTests` does, during its EXIT trap, whose `rm`
/// is itself a member of the group a Stop signals. Nothing here reaches the
/// network, root or the real installer.
final class TheStopsReachIsWhatItsOperationNamesTests: XCTestCase {

    // MARK: - The reach the engine names

    /// Every brew operation's Stop reaches its own process and nothing else —
    /// brew's handler winds down what brew started — and the installer's Stop
    /// reaches the wrapper's whole group. Each operation is finished before
    /// the next is pressed, so the gate never refuses one.
    func testEveryOperationNamesItsReachAndOnlyTheInstallerNamesTheGroup() {
        let runner = ScriptedRunner(streams: .hold)
        let tools = FakeCommandLineTools()
        tools.gitExecutable = true
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: ScriptedPrivileged(reply: .done),
                                    user: "tester", news: EngineNews(),
                                    marker: InMemoryOpMarker(), popularity: NoPopularity(),
                                    weight: NoPackageWeight(), tools: tools, ticker: FakeWaitTicker())
        let presses: [(String, StopReach, () -> Void)] = [
            ("install", .process, { engine.install(name: "wget", isCask: false) }),
            ("install --cask", .process, { engine.install(name: "firefox", isCask: true) }),
            ("uninstall", .process, { engine.uninstall(name: "wget", isCask: false) }),
            ("uninstall --cask", .process, { engine.uninstall(name: "firefox", isCask: true) }),
            ("upgrade", .process, { engine.upgrade(name: "wget") }),
            ("upgrade all", .process, { engine.upgradeAll() }),
            ("install Homebrew", .wholeGroup, { engine.installBrew() }),
        ]
        for (what, expected, press) in presses {
            let before = runner.streamCalls.count
            press()
            let launched = runner.streamCalls.dropFirst(before)
            XCTAssertEqual(launched.count, 1, "\(what): precondition — the press launched \(launched.count) children")
            if let reach = launched.first?.reach {
                XCTAssertEqual(reach, expected, "\(what): a Stop would reach \(reach), not \(expected)")
            } else if !launched.isEmpty {
                XCTFail("\(what): launched through the stream that names no reach — the real runner's default decides it")
            }
            runner.finishAll()
        }
    }

    // MARK: - What a Stop reaches on the real runner

    private func pid(after prefix: String, in run: Run) -> pid_t? {
        run.lines.first { $0.hasPrefix(prefix) }.flatMap { pid_t($0.dropFirst(prefix.count)) }
    }

    private static func reap(_ pids: [pid_t?]) {
        for case let p? in pids where kill(p, 0) == 0 { kill(p, SIGKILL) }
    }

    /// A Stop after the child has exited and been reaped does nothing — even
    /// though its process group is still alive, held by a member the child left
    /// behind. That group id is the only thing a late signal could still
    /// address, and it is not this handle's to signal any more.
    func testAStopAfterTheLeaderIsGoneSignalsNothing() async {
        let (handle, run) = start("/bin/sleep 30 >/dev/null 2>&1 & echo member=$!; exit 0", reach: .wholeGroup)
        XCTAssertEqual(run.finished(within: 10), .success, "precondition: the shell never exited")
        let member = pid(after: "member=", in: run)
        addTeardownBlock { Self.reap([member]) }
        guard let leftover = member else { return XCTFail("precondition: the shell named no member") }
        XCTAssertEqual(run.status, 0)
        let group = getpgid(leftover)
        XCTAssertGreaterThan(group, 1, "precondition: the member has no group")
        XCTAssertNotEqual(getpgid(group), group, "precondition: the leader is still there")

        handle.terminate()
        handle.terminate()
        await grace(0.6)                             // past both repeats
        XCTAssertEqual(kill(leftover, 0), 0,
                       "a Stop pressed after the child had gone signalled the group it left behind")
    }

    /// The repeated signal goes out for the installer's reach while the leader
    /// is still there, never once it has gone, and never for a brew
    /// operation's reach, whose Stop is one `Process.terminate()`. A member of
    /// the child's group counts every TERM it is sent. The `.process` row reads
    /// one TERM to the member: `Process.terminate()` signals the child's whole
    /// group, so `.process` and `.wholeGroup` differ by the repeats alone.
    func testTheGroupIsSignalledAgainOnlyWhileItsLeaderLives() async throws {
        let root = scratchDirectory("stop-repeats")
        var counts: [String: Int] = [:]
        let rows: [(what: String, reach: StopReach, leaderTrap: String)] = [
            ("process, leader lives", .process, ":"),
            ("group, leader lives", .wholeGroup, ":"),
            ("group, leader gone", .wholeGroup, "exit 143"),
        ]
        for (what, reach, leaderTrap) in rows {
            let count = root.appendingPathComponent(what.replacingOccurrences(of: ", ", with: "-").replacingOccurrences(of: " ", with: "-"))
            FileManager.default.createFile(atPath: count.path, contents: Data())
            let memberScript = root.appendingPathComponent("member-\(counts.count).sh")
            try "trap 'echo x >> \(count.path)' TERM\necho member=$$\nwhile :; do /bin/sleep 0.01; done\n"
                .write(to: memberScript, atomically: true, encoding: .utf8)
            let script = """
            trap '\(leaderTrap)' TERM; echo leader=$$
            /bin/bash \(memberScript.path) 2>/dev/null &
            while :; do /bin/sleep 0.01; done
            """
            let (handle, run) = start(script, reach: reach)
            await waitUntilReached("\(what): precondition — the member started", within: .seconds(10)) {
                run.lines.contains { $0.hasPrefix("member=") }
            }
            let leader = pid(after: "leader=", in: run)
            let memberPID = pid(after: "member=", in: run)
            addTeardownBlock { Self.reap([leader, memberPID]) }
            try await Task.sleep(for: .milliseconds(50))  // the member's trap is set before it prints
            handle.terminate()
            await grace(0.9)                         // both repeats, and the member's trap after each
            counts[what] = ((try? String(contentsOf: count, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline).count
            Self.reap([leader, memberPID])
            _ = run.finished(within: 5)
        }
        XCTAssertEqual(counts, ["process, leader lives": 1, "group, leader lives": 3, "group, leader gone": 1],
                       "TERMs a member of the group received per Stop")
    }

    // MARK: - The wrapper's own cleanup is in the group

    private func leftovers(_ temporaries: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: temporaries.path)) ?? []
    }

    private func clear(_ temporaries: URL) {
        for name in leftovers(temporaries) {
            try? FileManager.default.removeItem(at: temporaries.appendingPathComponent(name))
        }
    }

    /// An installer that tidies up for a moment on TERM makes the wrapper's EXIT
    /// trap run about when the Stop's repeated signal (0.1 s after the first)
    /// reaches the group. Swept across wind-down times around the repeat, every
    /// Stop must still leave the temporary folder empty.
    func testTheRepeatedSignalDoesNotLandOnTheWrappersOwnCleanup() async throws {
        let root = scratchDirectory("stop-cleanup-repeat")
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let command = try composedInstaller()
        var outcomes: [String] = []
        var stoppedInTheInstaller = 0
        let steps = 60
        for _ in 0..<steps {
            clear(temporaries)
            let windDown = Double.random(in: 0.080...0.106)
            let installer = root.appendingPathComponent("install-\(UUID().uuidString).sh")
            try """
            #!/bin/bash
            echo installer-running
            exec /usr/bin/perl -e '$SIG{TERM} = sub { $SIG{TERM} = "IGNORE"; select(undef, undef, undef, \(windDown)); exit 1 }; sleep 60'
            """.write(to: installer, atomically: true, encoding: .utf8)
            let (handle, run) = start(try rehosted(command, source: installer, temporaries: temporaries))
            await waitUntilReached("precondition: the installer started", within: .seconds(10)) {
                run.lines.contains("installer-running")
            }
            guard run.lines.contains("installer-running") else { handle.terminate(); continue }
            try await Task.sleep(for: .milliseconds(50))  // perl has set its handler
            stoppedInTheInstaller += 1
            handle.terminate()
            XCTAssertEqual(run.finished(within: 5), .success, "the stream never ended")
            await grace(0.5)                         // past the second repeat
            let left = leftovers(temporaries)
            if !left.isEmpty {
                outcomes.append(String(format: "wind-down %.1f ms: exit=%@ left=%@",
                                       windDown * 1000, run.status.map { "\($0)" } ?? "none", "\(left)"))
            }
        }
        XCTAssertEqual(stoppedInTheInstaller, steps, "precondition: not every Stop landed in the installer")
        XCTAssertEqual(outcomes, [],
                       "\(outcomes.count) of \(steps) Stops left the downloaded installer in the temporary folder")
    }

    /// A Stop that lands as the installer finishes — the person's press, or a
    /// switch-off, in the wrapper's last milliseconds. The installer succeeded;
    /// whatever the page is then told, the script must not stay behind.
    /// Swept across the tail of the wrapper's life, calibrated on this Mac.
    func testAStopAsTheInstallerFinishesLeavesNothingBehind() throws {
        let root = scratchDirectory("stop-cleanup-tail")
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let installer = root.appendingPathComponent("install.sh")
        try "#!/bin/bash\necho installed\nexit 0\n".write(to: installer, atomically: true, encoding: .utf8)
        let command = try rehosted(try composedInstaller(), source: installer, temporaries: temporaries)

        var life = TimeInterval.infinity
        for _ in 0..<5 {
            clear(temporaries)
            let t0 = Date()
            let (_, run) = start(command)
            XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success)
            life = min(life, Date().timeIntervalSince(t0))
            XCTAssertEqual(run.status, 0, "precondition: the installer does not succeed on its own")
        }
        XCTAssertEqual(leftovers(temporaries), [], "precondition: an unstopped run left the script behind")

        var outcomes: [String] = []
        var ranToTheEnd = 0
        let steps = 300
        for _ in 0..<steps {
            clear(temporaries)
            let delay = Double.random(in: (life * 0.6)...(life * 1.05))
            let (handle, run) = start(command)
            Thread.sleep(forTimeInterval: delay)
            handle.terminate()
            XCTAssertEqual(run.done.wait(timeout: .now() + 5), .success, "the stream never ended")
            if run.lines.contains("installed") { ranToTheEnd += 1 }
            Thread.sleep(forTimeInterval: 0.02)
            let left = leftovers(temporaries)
            if !left.isEmpty {
                outcomes.append(String(format: "stop at %.2f ms: exit=%@ installer said=%@ left=%@",
                                       delay * 1000, run.status.map { "\($0)" } ?? "none",
                                       run.lines.contains("installed") ? "installed" : "-", "\(left)"))
            }
        }
        XCTAssertGreaterThan(ranToTheEnd, 0, "precondition: no Stop landed after the installer had finished")
        XCTAssertEqual(outcomes, [],
                       "\(outcomes.count) of \(steps) Stops left the downloaded installer behind "
                       + "(wrapper lives \(String(format: "%.1f", life * 1000)) ms): \(outcomes.prefix(8))")
    }
}
