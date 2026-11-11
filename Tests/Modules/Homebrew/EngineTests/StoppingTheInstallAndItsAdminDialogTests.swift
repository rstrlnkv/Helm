// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// The child's handle: it records the SIGTERM and does **not** end the stream,
/// which is what the real one does — the child dies, then EOF, then `onExit`.
private final class Handle: RunningProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var _terminated = false
    var terminated: Bool { lock.lock(); defer { lock.unlock() }; return _terminated }
    func terminate() { lock.lock(); _terminated = true; lock.unlock() }
}

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

/// **Stop is a press against a handle that does not exist yet.**
///
///     public func stop() {
///         lock.lock()
///         guard busy, let handle = current else { lock.unlock(); return }
///
/// `current` is set by `adopt`, which runs *after* the child has been launched.
/// Everything before that point is a window in which the page is showing a
/// running operation with a live Stop button — `emitState(.running)` is the
/// first thing `installBrew` does — and the press falls through the `guard`
/// into a bare `return`: no state, no console line, no log, and `stopRequested`
/// left `false`, so nothing later can tell that the person asked.
///
/// For a package operation the window is a spawn and is measured in
/// milliseconds. For `installBrew` it is **the administrator password dialog**,
/// which is as long as a person takes to find their password — and while it is
/// up, `runAdmin` is blocking the engine's thread with `current` still nil.
/// Pressing Stop there does nothing, says nothing, and is then followed by the
/// module downloading and running the Homebrew installer anyway.
///
/// It is the family of a press that does nothing, visibly forever — here the
/// flag, `stopRequested`, is not written at all, because the check in front of
/// it fails.
///
/// **The fake privileged runner has to be *in the middle of* asking.** Every
/// existing `PrivilegedRunner` fake in this suite returns its answer inline, so
/// "the dialog is on screen and the person has not answered yet" is a state no
/// test could write down — which is why this window has never been tested.
/// `DialogOnScreen` below stops inside `runAdmin` until the test says the
/// person answered, which is what the real one does.
final class AStopBeforeTheChildExistsTests: XCTestCase {

    // MARK: - Fakes

    /// The admin dialog as it really behaves: it appears, and then it waits for
    /// a human. `waitUntilOnScreen()` returns once the engine is inside it;
    /// `answer()` is the person pressing a button.
    private final class DialogOnScreen: PrivilegedRunner, @unchecked Sendable {
        private let appeared = DispatchSemaphore(value: 0)
        private let answered = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _scripts: [String] = []
        private let reply: PrivilegedOutcome

        /// `holds: false` is the dialog somebody answers instantly — the shape
        /// every other fake in this suite has, kept for the control below. The
        /// permit is granted by a `signal` rather than by an initial value:
        /// libdispatch traps when a semaphore is deallocated below the value it
        /// was born with.
        init(reply: PrivilegedOutcome, holds: Bool = true) {
            self.reply = reply
            if !holds { answered.signal() }
        }

        var scripts: [String] { lock.lock(); defer { lock.unlock() }; return _scripts }

        func runAdmin(_ script: String) -> PrivilegedOutcome {
            lock.lock(); _scripts.append(script); lock.unlock()
            appeared.signal()
            answered.wait()
            return reply
        }

        func waitUntilOnScreen(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(appeared.wait(timeout: .now() + 5), .success,
                           "the administrator dialog was never asked for",
                           file: file, line: line)
        }
        func answer() { answered.signal() }
    }

    /// A child that keeps running, and a handle that records the SIGTERM
    /// without ending the stream — the real one does not finish on `terminate`
    /// either: the child dies, *then* EOF, *then* `onExit`.
    ///
    /// `InstallBrewTests`' runner returns `NoProcess()` for every stream, which
    /// makes "the installer was terminated" unrepresentable; a fake simpler
    /// than the port cannot fail the way the port can.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _launched: [(launch: String, args: [String])] = []
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []

        var launched: [(launch: String, args: [String])] {
            lock.lock(); defer { lock.unlock() }; return _launched
        }
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

        /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock()
            _launched.append((launchPath, args))
            _handles.append(handle)
            _exits.append(onExit)
            lock.unlock()
            return handle
        }

        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    // MARK: - Plumbing

    /// The last `opState` the news holds, read through its replay — a
    /// sentinel emitted before subscribing marks where the replay ends, so the
    /// read is deterministic.
    private func lastOpState(_ news: EngineNews<HomebrewNews>) async -> OpState? {
        news.say(.line("test.sentinel"), slot: "test.sentinel")
        var last: OpState?
        for await item in news.stream() {
            if case .line("test.sentinel") = item { break }
            if case .state(let s) = item {
                last = s
            }
        }
        return last
    }

    /// Starts `installBrew` on a thread of its own — it blocks inside the
    /// dialog, exactly as the engine's own queue does — and hands back a way to
    /// wait for it to return.
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
        let privileged = DialogOnScreen(reply: .done)
        let runner = HangingRunner()
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
        XCTAssertTrue(runner.launched.isEmpty, """
            Stop was pressed and the module then downloaded and ran the Homebrew \
            installer anyway: \(runner.launched.map(\.launch))
            """)
    }

    func testAStopPressedAtTheDialogEndsTheOperation() async {
        let privileged = DialogOnScreen(reply: .done)
        let runner = HangingRunner()
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

    /// Once the child exists the press does reach it — so the failures above
    /// are about the window before `adopt`, not about `stop` in general. This
    /// also exercises the capability `InstallBrewTests`' `NoProcess()` runner
    /// cannot: the Homebrew installer itself being terminated.
    func testOnceTheInstallerIsRunningStopReachesIt() {
        let privileged = DialogOnScreen(reply: .done, holds: false)
        let runner = HangingRunner()
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
        let privileged = DialogOnScreen(reply: .done)
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        privileged.answer()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")

        XCTAssertEqual(runner.launched.count, 1,
                       "nobody pressed Stop and the installer did not run")
        XCTAssertEqual(runner.launched.first?.launch, "/bin/bash")
    }
}

/// **The other side of the window `AStopBeforeTheChildExistsTests` closes.**
///
/// That one is a press that lands *before* the launch, which the launch itself
/// now reads. This one lands after that reading and before the engine owns a
/// handle — while `runner.stream` is in flight, which for the real runner is a
/// `posix_spawn` and a pipe. `stop` finds `current` still nil, so it terminates
/// nothing; a moment later `adopt` is handed the very child the person asked to
/// end. Without the check there, the press is recorded, the page says
/// «Stopped», and `brew install` goes on running to completion.
///
/// It is milliseconds wide and it is not unreachable: `stop` arrives on the
/// news from a button press, on a different thread from the one inside
/// `runOp`, and the two are not ordered by anything else.
///
/// **The fake presses the button from inside `stream`,** which is the only way
/// to be exactly there. A fake that merely returns a handle cannot represent
/// «the press landed during the spawn», so no test of this could exist however
/// carefully it was written.
final class AStopDuringTheLaunchItselfIsNotLostTests: XCTestCase {

    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
    }

    /// A runner that lets the test act *while the launch is happening*.
    private final class RunnerThatIsInterrupted: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _handles: [Handle] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        /// Called after the child exists and before the handle is handed back.
        var duringLaunch: (@Sendable () -> Void)?

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

        /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); lock.unlock()
            duringLaunch?()
            return handle
        }
    }

    func testAStopPressedWhileTheChildIsBeingLaunchedStillReachesIt() {
        let runner = RunnerThatIsInterrupted()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: EngineNews(),
                                    marker: InMemoryOpMarker())
        runner.duringLaunch = { [weak engine] in engine?.stop() }

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
        let runner = RunnerThatIsInterrupted()
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
/// installer. The wrapper used to die on the TERM without reaching its `rm`, so
/// the downloaded script stayed in the temporary folder; and a signal that
/// reaches only the wrapper leaves the inner `bash "$script"` running orphaned,
/// writing into `/opt/homebrew` after the page said stopped. Which of the two
/// happens through `Process.terminate()` is not the wrapper's to decide, so the
/// checks below ask for every part of the outcome: the stream ends, nothing the
/// installer started is alive, and the script is gone.
///
/// Nothing here reaches the network or root. The command is the engine's own
/// (composed by driving `installBrew` against a fake runner, not spelled a
/// second time), rehosted as `TheDownloadedInstallerIsTidiedAwayTests` does —
/// the `https://` word becomes a `file://` URL and `mktemp` is told where to
/// write — and launched through the real `ShellProcessRunner.stream`, whose
/// handle is what Stop terminates. The stand-in installer records its own
/// process id and that of a child it starts, then waits: a harmless script that
/// does what the real one does to the process tree.
final class AStopReachesTheInstallerItselfTests: XCTestCase {

    private struct AllowingPrivileged: PrivilegedRunner {
        func runAdmin(_ script: String) -> PrivilegedOutcome { .done }
    }

    /// Keeps the command the engine streams and never finishes it.
    private final class RecordingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _args: [[String]] = []
        var args: [[String]] { lock.lock(); defer { lock.unlock() }; return _args }
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String])
        -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _args.append(args); lock.unlock()
            return NoProcess()
        }
    }

    private final class Exit: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _status: Int32?
        var status: Int32? { lock.lock(); defer { lock.unlock() }; return _status }
        func set(_ s: Int32) { lock.lock(); _status = s; lock.unlock(); done.signal() }
    }

    private func composedInstaller() throws -> String {
        let runner = RecordingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: AllowingPrivileged(), user: "tester",
                                    news: EngineNews())
        engine.installBrew()
        return try XCTUnwrap(try XCTUnwrap(runner.args.first, "the engine launched nothing").last)
    }

    private func rehosted(_ command: String, installer: URL, temporaries: URL) throws -> String {
        let url = try XCTUnwrap(command.split(separator: " ").first { $0.hasPrefix("https://") },
                                "the command downloads nothing over https any more")
        return command
            .replacingOccurrences(of: String(url), with: "file://\(installer.path)")
            .replacingOccurrences(of: "/usr/bin/mktemp",
                                  with: "/usr/bin/mktemp -p \(temporaries.path) -t helm")
    }

    private func pid(in file: URL) -> pid_t? {
        (try? String(contentsOf: file, encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    /// Waits on the wall clock for `condition`; a condition polled is the only
    /// honest wait for a process this test does not own the end of.
    private func eventually(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }

    func testStopKillsTheInstallerAndWhatItStartedAndRemovesTheScript() throws {
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

        let command = try rehosted(composedInstaller(), installer: installer, temporaries: temporaries)
        let exit = Exit()
        let handle = ShellProcessRunner().stream("/bin/bash", ["-c", command], env: [:],
                                                 onLine: { _ in }, onExit: { exit.set($0) })

        XCTAssertTrue(eventually(10) { pid(in: innerPID) != nil && pid(in: grandchildPID) != nil },
                      "precondition: the stand-in installer never started")
        let inner = try XCTUnwrap(pid(in: innerPID))
        let grandchild = try XCTUnwrap(pid(in: grandchildPID))
        XCTAssertTrue(isAlive(inner) && isAlive(grandchild), "precondition: both are running")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaries.path).count, 1,
                       "precondition: the downloaded script is on disk while the installer runs")

        handle.terminate()                                   // what Stop does

        XCTAssertEqual(exit.done.wait(timeout: .now() + 10), .success,
                       "the stream never ended: something the wrapper started still holds its pipe")
        XCTAssertTrue(eventually(5) { !isAlive(inner) },
                      "the installer kept running after Stop")
        XCTAssertTrue(eventually(5) { !isAlive(grandchild) },
                      "a process the installer started kept running after Stop")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaries.path), [],
                       "the downloaded installer was left in the temporary folder after Stop")
    }
}

/// **Every place a Stop or a switch-off can land in `installBrew` ends the
/// operation exactly once, raises nothing after it, and leaves the gate open.**
///
/// `TheGapsAroundTheWaitRaiseNoDialogTests` asks whether a dialog rises after
/// an ending. This asks the three things a page needs from the same moments:
/// that the ending was said once — two terminal states from one operation is
/// two `concludeOp`s, which closes the activity phase twice and runs the
/// refresh twice — that it was said as the person's stop, and that the next
/// press is admitted. Each ending fires from inside the port call the engine
/// really makes at that moment.
///
/// The second half is `deactivate()` reaching past the wait: while
/// `install.sh` runs it ends it the way Stop does, while the password dialog
/// is up it leaves nothing to launch after it, and while an ordinary package
/// operation runs it terminates nothing, and no operation starts until the
/// module is activated again.
final class EveryStopPointEndsTheInstallOnceTests: XCTestCase {

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    /// A child the way the real handle is: terminating it only records the
    /// signal — the exit arrives afterwards, when the test says the child died.
    private final class KillableRunner: ProcessRunner, @unchecked Sendable {
        final class Handle: RunningProcess, @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var terminations: Int { lock.lock(); defer { lock.unlock() }; return n }
            func terminate() { lock.lock(); n += 1; lock.unlock() }
        }
        private let lock = NSLock()
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        private var _args: [[String]] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
        var args: [[String]] { lock.lock(); defer { lock.unlock() }; return _args }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); _exits.append(onExit); _args.append(args); lock.unlock()
            return handle
        }
        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    /// Every port named: Apple's tools, time, root, the runner, the marker.
    private struct Rig {
        let tools: FakeCommandLineTools
        let ticker = FakeWaitTicker()
        let privileged: ScriptedPrivileged
        let runner = KillableRunner()
        let news = EngineNews<HomebrewNews>()
        let engine: HomebrewEngine
        /// Subscribed before anything is pressed, so it holds every state the
        /// engine sent and not only the last.
        let tape: AsyncStream<HomebrewNews>

        init(holdsDialog: Bool = false) {
            tools = FakeCommandLineTools()
            privileged = ScriptedPrivileged(reply: .done, holds: holdsDialog)
            engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: news, marker: InMemoryOpMarker(),
                                    tools: tools, ticker: ticker)
            tape = news.stream()
        }

        /// Every `opState` sent since the rig was built, in order.
        func states() async -> [OpState] {
            news.say(.line("test.sentinel"), slot: "test.sentinel")
            var out: [OpState] = []
            for await item in tape {
                if case .line("test.sentinel") = item { break }
                if case .state(let s) = item { out.append(s) }
            }
            return out
        }
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
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var homebrewLines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == HomebrewEngine.moduleID }.map(\.message)
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

    private func arm(_ rig: Rig, at point: Point, with ending: Ending) -> Count {
        let hit = Count()
        let reads = Count()
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
                XCTAssertTrue(rig.runner.args.isEmpty, "\(what): the installer was launched")
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
                rig.runner.exitAll(code: 0)
            }
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
        rig.runner.exitAll(code: 143)                           // the wrapper's TERM trap
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
        rig.runner.exitAll(code: 143)

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

        XCTAssertTrue(rig.runner.args.isEmpty, "install.sh ran for a module switched off during the dialog")
        let terminal = await rig.states().filter { $0.phase != .running }
        XCTAssertEqual(terminal.count, 1, "ended \(terminal.count) times: \(terminal)")
        XCTAssertEqual(terminal.first?.reason, .stopped)
        rig.engine.activate()
        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 1, "the gate stayed shut after the module came back")
    }

    // MARK: - A switch-off during anything else

    /// The switch-off reaches the install and nothing else: an upgrade the
    /// person started goes on — it was never the module's to stop — and its
    /// ending is its own.
    func testASwitchOffDuringAPackageOperationLeavesItAlone() async {
        let rig = Rig()
        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 1, "precondition: the package operation is running")

        rig.engine.deactivate()

        XCTAssertEqual(rig.runner.handles.first?.terminations, 0,
                       "a switch-off terminated an ordinary package operation")
        rig.runner.exitAll(code: 0)
        let terminal = await rig.states().filter { $0.phase != .running }
        XCTAssertEqual(terminal.map(\.phase), [.done], "the operation's own ending was replaced: \(terminal)")
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
        XCTAssertTrue(rig.runner.calls.isEmpty)

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
            let engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: RecordingStreamRunner(),
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
/// `StoppingTheWaitRaisesNoDialogTests` holds the ending that finds the token.
/// These hold the one that does not — a Stop or a switch-off landing while the
/// request is being filed, before it is filed, or between the tick's verdict
/// and the password dialog — and ask the same question of each: does the
/// person, who has just said no more, get Apple's window or an administrator
/// dialog anyway?
///
/// Every hook fires from inside a port call the engine really makes at that
/// moment, so the ending lands on the thread and at the line it would in the
/// app, not before or after the press.
final class TheGapsAroundTheWaitRaiseNoDialogTests: XCTestCase {

    /// Counts calls from inside a hook; the hooks are not `Sendable`, and run
    /// on whatever thread the engine calls the port from.
    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }

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
        let reads = Count()
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
        XCTAssertTrue(rig.runner.calls.isEmpty, "the installer ran for a module that is off")
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
        host.engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: RecordingStreamRunner(),
                                     privileged: privileged, user: "tester",
                                     news: EngineNews(), marker: InMemoryOpMarker(),
                                     tools: tools, ticker: ticker)
        host.engine?.installBrew()
        XCTAssertEqual(ticker.live, 1, "precondition: the wait is armed")
        tools.gitExecutable = true
        let reads = Count()
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
    /// engine is dropped as well: the press holds the engine until it returns.
    /// It is `deactivate()` that keeps the wait from being armed — it sets the
    /// stop flag under the lock, and `installBrew` reads the flag before it arms
    /// anything, which the first case in this class holds without dropping the
    /// engine. What this case adds is the drop: with the engine gone, no tick is
    /// left live and the dialog stays down.
    func testAnEngineSwitchedOffAndDroppedDuringTheRequestLeavesNoTick() {
        final class Host: @unchecked Sendable { var engine: HomebrewEngine? }
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done)
        let host = Host()
        weak var gone: HomebrewEngine?
        autoreleasepool {
            host.engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: RecordingStreamRunner(),
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
        let reads = Count()
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
        let reads = Count()
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
        XCTAssertTrue(rig.runner.calls.isEmpty)
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
        let engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: RecordingStreamRunner(),
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
/// The engine names a `StopReach` per launch and the real runner acts on it,
/// but every fake in this family implements only the `stream` that has no
/// `reach:` label, so the default in `ProcessRunner`'s extension swallows the reach before any
/// fake can see it: nothing else in the suite goes red if `installBrew` names
/// `.process` or a brew operation names `.wholeGroup`. The first case records
/// the reach the engine names; the rest run the real `ShellProcessRunner` and
/// read what a Stop actually reached — a group whose leader has already gone,
/// and the repeated signal per reach, against a leader that is still there and
/// one that is not.
///
/// The last two cases stop the engine's own `install.sh` wrapper (rehosted as
/// `TheInstallerWrapperKeepsItsWordTests` does it: `file://` source, `mktemp`
/// pointed at a scratch folder) at the one moment that sweep does not reach:
/// the wrapper's EXIT trap, whose `rm` is itself a member of the group a Stop
/// signals. Nothing here reaches the network, root or the real installer.
final class TheStopsReachIsWhatItsOperationNamesTests: XCTestCase {

    // MARK: - The reach the engine names

    /// Records the reach of every launch. Implements both `stream` forms: the
    /// one without `reach:` records `nil`, because a launch that names no reach
    /// is itself the thing this case is looking for.
    private final class ReachRecordingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _reaches: [(args: [String], reach: StopReach?)] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        var reaches: [(args: [String], reach: StopReach?)] { lock.lock(); defer { lock.unlock() }; return _reaches }

        func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) { (0, "") }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            record(args, nil, onExit)
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String], reach: StopReach,
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            record(args, reach, onExit)
        }

        private func record(_ args: [String], _ reach: StopReach?,
                            _ onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _reaches.append((args, reach)); _exits.append(onExit); lock.unlock()
            return NoProcess()
        }

        func finishAll() {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(0) }
        }
    }

    /// Every brew operation's Stop reaches its own process and nothing else —
    /// brew's handler winds down what brew started — and the installer's Stop
    /// reaches the wrapper's whole group. Each operation is finished before
    /// the next is pressed, so the gate never refuses one.
    func testEveryOperationNamesItsReachAndOnlyTheInstallerNamesTheGroup() {
        let runner = ReachRecordingRunner()
        let tools = FakeCommandLineTools()
        tools.gitExecutable = true
        let engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: runner,
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
            let before = runner.reaches.count
            press()
            let launched = runner.reaches.dropFirst(before)
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

    private final class Run: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _status: Int32?
        private var _lines: [String] = []
        var status: Int32? { lock.lock(); defer { lock.unlock() }; return _status }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
        func line(_ l: String) { lock.lock(); _lines.append(l); lock.unlock() }
        func exit(_ s: Int32) { lock.lock(); _status = s; lock.unlock(); done.signal() }
    }

    private func start(_ script: String, reach: StopReach) -> (RunningProcess, Run) {
        let run = Run()
        let handle = ShellProcessRunner().stream("/bin/bash", ["-c", script], env: [:], reach: reach,
                                                 onLine: { run.line($0) }, onExit: { run.exit($0) })
        return (handle, run)
    }

    private func eventually(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

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
    func testAStopAfterTheLeaderIsGoneSignalsNothing() {
        let (handle, run) = start("/bin/sleep 30 >/dev/null 2>&1 & echo member=$!; exit 0", reach: .wholeGroup)
        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success, "precondition: the shell never exited")
        let member = pid(after: "member=", in: run)
        addTeardownBlock { Self.reap([member]) }
        guard let leftover = member else { return XCTFail("precondition: the shell named no member") }
        XCTAssertEqual(run.status, 0)
        let group = getpgid(leftover)
        XCTAssertGreaterThan(group, 1, "precondition: the member has no group")
        XCTAssertNotEqual(getpgid(group), group, "precondition: the leader is still there")

        handle.terminate()
        handle.terminate()
        Thread.sleep(forTimeInterval: 0.6)           // past both repeats
        XCTAssertEqual(kill(leftover, 0), 0,
                       "a Stop pressed after the child had gone signalled the group it left behind")
    }

    /// The repeated signal goes out for the installer's reach while the leader
    /// is still there, never once it has gone, and never for a brew
    /// operation's reach, whose Stop is the one `Process.terminate()` it always
    /// was. A member of the child's group counts every TERM it is sent; the
    /// leader either survives every TERM (a trap that does nothing) or leaves at
    /// the first. Note what the `.process` row reads: one TERM **to the
    /// member** — `Process.terminate()` signals the child's whole group on this
    /// Mac (a member moved into a group of its own is not reached), so
    /// `.process` and `.wholeGroup` differ by the repeats alone.
    func testTheGroupIsSignalledAgainOnlyWhileItsLeaderLives() throws {
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
            XCTAssertTrue(eventually(10) { run.lines.contains { $0.hasPrefix("member=") } },
                          "\(what): precondition — the member never started")
            let leader = pid(after: "leader=", in: run)
            let memberPID = pid(after: "member=", in: run)
            addTeardownBlock { Self.reap([leader, memberPID]) }
            Thread.sleep(forTimeInterval: 0.05)      // the member's trap is set before it prints
            handle.terminate()
            Thread.sleep(forTimeInterval: 0.9)       // both repeats, and the member's trap after each
            counts[what] = ((try? String(contentsOf: count, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline).count
            Self.reap([leader, memberPID])
            _ = run.done.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(counts, ["process, leader lives": 1, "group, leader lives": 3, "group, leader gone": 1],
                       "TERMs a member of the group received per Stop")
    }

    // MARK: - The wrapper's own cleanup is in the group

    private func composedInstaller() throws -> String {
        let rig = WaitRig()
        rig.tools.gitExecutable = true
        rig.engine.installBrew()
        return try XCTUnwrap(try XCTUnwrap(rig.runner.calls.first, "the engine launched nothing").args.last)
    }

    private func rehosted(_ command: String, source: URL, temporaries: URL) throws -> String {
        let url = try XCTUnwrap(command.split(separator: " ").first { $0.hasPrefix("https://") },
                                "the command downloads nothing over https any more")
        return command
            .replacingOccurrences(of: String(url), with: "file://\(source.path)")
            .replacingOccurrences(of: "/usr/bin/mktemp",
                                  with: "/usr/bin/mktemp -p \(temporaries.path) -t helm")
    }

    private func leftovers(_ temporaries: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: temporaries.path)) ?? []
    }

    private func clear(_ temporaries: URL) {
        for name in leftovers(temporaries) {
            try? FileManager.default.removeItem(at: temporaries.appendingPathComponent(name))
        }
    }

    /// An installer that answers TERM by tidying up for a moment before it
    /// exits — the shape of any installer with a cleanup handler. The wrapper
    /// then runs its EXIT trap at about that moment, and the Stop's repeated
    /// signal, sent 0.1 s after the first to the same group, lands on the
    /// trap's own `rm`. Swept across the wind-down times around the repeat:
    /// every Stop must still leave the temporary folder empty.
    func testTheRepeatedSignalDoesNotLandOnTheWrappersOwnCleanup() throws {
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
            let run = Run()
            let handle = ShellProcessRunner().stream(
                "/bin/bash", ["-c", try rehosted(command, source: installer, temporaries: temporaries)], env: [:],
                onLine: { run.line($0) }, onExit: { run.exit($0) })
            guard eventually(10, { run.lines.contains("installer-running") }) else {
                XCTFail("precondition: the installer never started"); handle.terminate(); continue
            }
            Thread.sleep(forTimeInterval: 0.05)      // perl has set its handler
            stoppedInTheInstaller += 1
            handle.terminate()
            XCTAssertEqual(run.done.wait(timeout: .now() + 5), .success, "the stream never ended")
            Thread.sleep(forTimeInterval: 0.5)       // past the second repeat
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
            let run = Run()
            let t0 = Date()
            _ = ShellProcessRunner().stream("/bin/bash", ["-c", command], env: [:],
                                            onLine: { run.line($0) }, onExit: { run.exit($0) })
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
            let run = Run()
            let delay = Double.random(in: (life * 0.6)...(life * 1.05))
            let handle = ShellProcessRunner().stream("/bin/bash", ["-c", command], env: [:],
                                                     onLine: { run.line($0) }, onExit: { run.exit($0) })
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
