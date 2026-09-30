import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

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
                                     transport: LocalTransport(), marker: InMemoryOpMarker(),
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
    /// anything, which the first case in this file holds without dropping the
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
                                         transport: LocalTransport(), marker: InMemoryOpMarker(),
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
                                    transport: LocalTransport(), marker: InMemoryOpMarker(),
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
