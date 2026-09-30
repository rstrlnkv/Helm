import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A Stop reads as a Stop only where it stopped something.**
///
/// The wrapper keeps 143 for a press that ended the installer or came before
/// it, and hands through the installer's own code otherwise. Three sides of
/// that, each asked from where the person reads it:
///
/// - the page and the log, when the installer answered 0 after Stop was
///   pressed — the engine against a runner whose exit the test decides;
/// - an installer that answers a Stop with an ordinary failure code of its own
///   — the engine's own command, rehosted, through the real runner;
/// - a Stop at every moment of the wrapper's life against an installer that
///   cannot be stopped once it runs: whatever ran reports 0, whatever did not
///   run reports non-zero, and nothing is left in the temporary folder.
///
/// Nothing here reaches the network, root or the real installer.
final class AStopReadsAsWhatItActuallyStoppedTests: XCTestCase {

    // MARK: - The page and the log

    /// A child the way the real handle is: terminating it only records the
    /// signal, and the exit arrives when the test says so.
    private final class HeldRunner: ProcessRunner, @unchecked Sendable {
        final class Handle: RunningProcess, @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var terminations: Int { lock.lock(); defer { lock.unlock() }; return n }
            func terminate() { lock.lock(); n += 1; lock.unlock() }
        }
        private let lock = NSLock()
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) { (0, "") }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock(); _handles.append(handle); _exits.append(onExit); lock.unlock()
            return handle
        }
        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    private struct Rig {
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done, holds: false)
        let runner = HeldRunner()
        let transport = LocalTransport()
        let engine: HomebrewEngine
        let tape: AsyncStream<EngineEvent>

        init() {
            engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: transport, marker: InMemoryOpMarker(),
                                    tools: tools, ticker: ticker)
            tape = transport.events
        }

        func terminalStates() async -> [OpState] {
            transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
            var out: [OpState] = []
            for await event in tape {
                if event.name == "test.sentinel" { break }
                if event.name == HomebrewEvent.opState.rawValue,
                   let s = try? JSONDecoder().decode(OpState.self, from: event.payload),
                   s.phase != .running { out.append(s) }
            }
            return out
        }
    }

    override func setUp() {
        super.setUp()
        _ = HelmLog.shared.recentEntries()
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

    /// Stop pressed while install.sh runs, and the wrapper then answers 0 —
    /// the installer finished. The page is told "done" and the log says so;
    /// neither says "stopped".
    func testAStopOverAnInstallerThatSucceededIsDoneOnThePageAndInTheLog() async {
        let rig = Rig()
        rig.tools.gitExecutable = true
        rig.engine.installBrew()
        XCTAssertEqual(rig.runner.handles.count, 1, "precondition: install.sh is running")

        rig.engine.stop()
        XCTAssertEqual(rig.runner.handles.first?.terminations, 1, "precondition: the Stop reached the handle")
        XCTAssertTrue(homebrewLines.contains("stop requested"), "precondition: the Stop was taken")
        rig.runner.exitAll(code: 0)

        let terminal = await rig.terminalStates()
        XCTAssertEqual(terminal.count, 1, "ended \(terminal.count) times: \(terminal)")
        XCTAssertEqual(terminal.first?.phase, .done, "an installer that answered 0 is not done on the page: \(terminal)")
        XCTAssertNil(terminal.first?.reason, "a finished install carries a failure reason: \(terminal)")
        XCTAssertEqual(terminal.first?.exitCode, 0)
        XCTAssertTrue(homebrewLines.contains("install Homebrew done"),
                      "the log does not say the install finished: \(homebrewLines)")
        XCTAssertFalse(homebrewLines.contains { $0.contains("stopped on request") },
                       "the log calls a finished install stopped: \(homebrewLines)")
    }

    // MARK: - The wrapper

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

    private struct Ground {
        let temporaries: URL
        let marks: URL
        let installer: URL
        var leftovers: [String] { (try? FileManager.default.contentsOfDirectory(atPath: temporaries.path)) ?? [] }
        var ran: Bool { FileManager.default.fileExists(atPath: marks.path) }
        func reset() {
            for name in leftovers { try? FileManager.default.removeItem(at: temporaries.appendingPathComponent(name)) }
            try? FileManager.default.removeItem(at: marks)
        }
    }

    private func ground(_ label: String, installer body: String) throws -> Ground {
        let root = scratchDirectory(label)
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let marks = root.appendingPathComponent("ran")
        let installer = root.appendingPathComponent("install.sh")
        try "#!/bin/bash\n\(body.replacingOccurrences(of: "$MARK", with: marks.path))\n"
            .write(to: installer, atomically: true, encoding: .utf8)
        return Ground(temporaries: temporaries, marks: marks, installer: installer)
    }

    private func start(_ command: String) -> (RunningProcess, Run) {
        let run = Run()
        let handle = ShellProcessRunner().stream("/bin/bash", ["-c", command], env: [:], reach: .wholeGroup,
                                                 onLine: { run.line($0) }, onExit: { run.exit($0) })
        return (handle, run)
    }

    /// An installer that answers the Stop by failing in its own way — exit 1
    /// from its own TERM handler. The Stop ended it, so the page reads 143.
    func testAnInstallerThatAnswersAStopWithItsOwnFailureReadsAsStopped() throws {
        let g = try ground("stop-own-failure",
                           installer: "trap 'exit 1' TERM\ntouch $MARK\necho installing\n"
                                    + "while :; do /bin/sleep 0.05; done")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: g.installer, temporaries: g.temporaries))
        let deadline = Date().addingTimeInterval(10)
        while !run.lines.contains("installing"), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(run.lines.contains("installing"), "precondition: the installer never started")

        handle.terminate()

        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success, "the stream never ended")
        XCTAssertEqual(run.status, 143, "a Stop that ended the installer read as its own failure")
        XCTAssertEqual(g.leftovers, [], "the downloaded installer stayed behind")
    }

    /// **A Stop at every moment of the wrapper's life, against an installer
    /// that cannot be stopped once it has run its first line.** Every outcome
    /// must be one of two: the installer ran and the wrapper reports its 0, or
    /// the installer never ran and the wrapper reports non-zero — and the
    /// temporary folder is empty either way. A 143 over an installer that ran
    /// is the Stop claiming an install it did not stop; a 0 over one that did
    /// not run is an install reported that never happened.
    func testEveryStopEitherLetTheInstallerFinishOrKeptItFromRunning() throws {
        let g = try ground("stop-sweep-success",
                           installer: "trap '' TERM\ntouch $MARK\necho installed\nexit 0")
        let command = try rehosted(try composedInstaller(), source: g.installer, temporaries: g.temporaries)

        var life = TimeInterval.infinity
        for _ in 0..<3 {
            g.reset()
            let t0 = Date()
            let (_, run) = start(command)
            XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success)
            XCTAssertEqual(run.status, 0, "precondition: without a Stop the wrapper reports the installer's 0")
            life = min(life, Date().timeIntervalSince(t0))
        }

        var wrong: [String] = []
        var ranCount = 0
        var keptCount = 0
        let steps = 200
        for _ in 0..<steps {
            g.reset()
            let delay = Double.random(in: 0...(life * 1.1))
            let (handle, run) = start(command)
            Thread.sleep(forTimeInterval: delay)
            handle.terminate()
            let ended = run.done.wait(timeout: .now() + 5) == .success
            // The wrapper has ended, so no repeat of the signal is still to come
            // (they stop with the leader); a moment for the file system.
            Thread.sleep(forTimeInterval: 0.03)
            let ran = g.ran
            if ran { ranCount += 1 } else { keptCount += 1 }
            let status = run.status
            let right = ended && g.leftovers.isEmpty && (ran ? status == 0 : (status != nil && status != 0))
            if !right {
                wrong.append(String(format: "stop at %.1f ms: ended=%@ ran=%@ exit=%@ left=%@",
                                    delay * 1000, ended ? "yes" : "no", ran ? "yes" : "no",
                                    status.map { "\($0)" } ?? "none", "\(g.leftovers)"))
            }
        }

        XCTAssertGreaterThan(ranCount, 0, "precondition: no Stop landed after the installer had run")
        XCTAssertGreaterThan(keptCount, 0, "precondition: no Stop landed before the installer ran")
        XCTAssertEqual(wrong, [], "\(wrong.count) of \(steps) Stops read as what they did not do "
                       + "(wrapper lives \(String(format: "%.1f", life * 1000)) ms)")
    }
}
