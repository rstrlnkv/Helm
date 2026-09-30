import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

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
                                    user: "tester", transport: LocalTransport(),
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
