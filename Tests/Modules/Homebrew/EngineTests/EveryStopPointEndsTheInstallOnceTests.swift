import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

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
/// operation runs it touches nothing.
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
        let transport = LocalTransport()
        let engine: HomebrewEngine
        /// Subscribed before anything is pressed, so it holds every state the
        /// engine sent and not only the last.
        let tape: AsyncStream<EngineEvent>

        init(holdsDialog: Bool = false) {
            tools = FakeCommandLineTools()
            privileged = ScriptedPrivileged(reply: .done, holds: holdsDialog)
            engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: transport, marker: InMemoryOpMarker(),
                                    tools: tools, ticker: ticker)
            tape = transport.events
        }

        /// Every `opState` sent since the rig was built, in order.
        func states() async -> [OpState] {
            transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
            var out: [OpState] = []
            for await event in tape {
                if event.name == "test.sentinel" { break }
                if event.name == HomebrewEvent.opState.rawValue,
                   let s = try? JSONDecoder().decode(OpState.self, from: event.payload) { out.append(s) }
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

                // The gate: the next press, on a Mac that now has the tools, reaches the dialog.
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
        XCTAssertEqual(rig.runner.handles.count, 2, "the gate stayed shut after the switch-off")
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
        rig.engine.install(name: "wget", isCask: false)
        XCTAssertEqual(rig.runner.handles.count, 1, "the gate stayed shut after the switch-off")
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
