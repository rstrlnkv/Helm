import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **The `install.sh` wrapper under every input its own test does not feed it.**
///
/// `AStopReachesTheInstallerItselfTests` stops the wrapper once, while the
/// installer is running. The wrapper also has to: hand the installer's own
/// exit code through unchanged, stream what the installer prints line by line
/// while it runs, put nothing of the shell's own on the page's console, stop at
/// a failed download, end a Stop that lands in the download, survive a second
/// Stop, and remove the script exactly once — and a Stop can land at *any*
/// moment of the wrapper's life, not only the one after the installer has
/// settled.
///
/// The command is the engine's own (taken from `installBrew` against fakes),
/// rehosted the way `TheDownloadedInstallerIsTidiedAwayTests` does it — the
/// `https://` word becomes a `file://` URL, `mktemp` is told where to write —
/// and run through the real `ShellProcessRunner.stream`, whose handle is what
/// Stop terminates. Nothing here reaches the network, root, or the real
/// installer; every installer is a stand-in written by the test.
final class TheInstallerWrapperKeepsItsWordTests: XCTestCase {

    // MARK: - Harness

    private final class Run: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _status: Int32?
        private var _exits = 0
        private var _lines: [String] = []
        var status: Int32? { lock.lock(); defer { lock.unlock() }; return _status }
        var exits: Int { lock.lock(); defer { lock.unlock() }; return _exits }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
        func line(_ l: String) { lock.lock(); _lines.append(l); lock.unlock() }
        func exit(_ s: Int32) { lock.lock(); _status = s; _exits += 1; lock.unlock(); done.signal() }
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
        let root: URL
        let temporaries: URL
        let pids: URL
        func installer(_ body: String) throws -> URL {
            let url = root.appendingPathComponent("install-\(UUID().uuidString).sh")
            try ("#!/bin/bash\necho $$ >> \(pids.path)\n" + body + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        var leftovers: [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: temporaries.path)) ?? []
        }
        var recordedPIDs: [pid_t] {
            ((try? String(contentsOf: pids, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
        }
        func alive() -> [pid_t] { recordedPIDs.filter { kill($0, 0) == 0 } }
        func killAll() { for p in recordedPIDs where kill(p, 0) == 0 { kill(p, SIGKILL) } }
        func reset() {
            for name in leftovers { try? FileManager.default.removeItem(at: temporaries.appendingPathComponent(name)) }
            try? Data().write(to: pids)
        }
    }

    private func ground(_ label: String) throws -> Ground {
        let root = scratchDirectory(label)
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let pids = root.appendingPathComponent("pids")
        try Data().write(to: pids)
        let g = Ground(root: root, temporaries: temporaries, pids: pids)
        // A red run must not leave a stand-in behind it.
        addTeardownBlock { g.killAll() }
        return g
    }

    private func start(_ command: String, trace: Bool = false) -> (RunningProcess, Run) {
        let run = Run()
        let handle = ShellProcessRunner().stream("/bin/bash", [trace ? "-xc" : "-c", command], env: [:],
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

    /// A line only the shell writes about its own jobs: `[1]+  Done …`,
    /// `[1]+  Exit 3 …`, `[1]+  Terminated: 15 …`.
    private func isJobNotice(_ line: String) -> Bool {
        line.range(of: #"^\[[0-9]+\][+-]? "#, options: .regularExpression) != nil
    }

    // MARK: - Exit status

    /// The installer's own code, whatever it is — not the wrapper's 143, not a
    /// zero borrowed from the `rm` in the EXIT trap.
    func testTheInstallersOwnCodeIsTheWrappersCode() throws {
        let g = try ground("wrapper-codes")
        let command = try composedInstaller()
        for code: Int32 in [0, 1, 3, 42] {
            g.reset()
            let installer = try g.installer("echo 'installer says hello'\nexit \(code)")
            let (_, run) = start(try rehosted(command, source: installer, temporaries: g.temporaries))
            XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success, "exit \(code): the stream never ended")
            XCTAssertEqual(run.status, code, "the installer exited \(code) and the page is told \(String(describing: run.status))")
            XCTAssertEqual(g.recordedPIDs.count, 1, "exit \(code): precondition — the installer ran")
            XCTAssertEqual(g.leftovers, [], "exit \(code): the script was left in the temporary folder")
        }
    }

    /// A download that fails stops the wrapper before any installer runs: its
    /// own non-zero code (an installer run over an empty file would say 0), and
    /// nothing left behind.
    func testAFailedDownloadRunsNothingAndLeavesNothing() throws {
        let g = try ground("wrapper-download-fails")
        let missing = g.root.appendingPathComponent("not-there.sh")
        let (_, run) = start(try rehosted(try composedInstaller(), source: missing, temporaries: g.temporaries))
        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success, "the stream never ended")
        let status = try XCTUnwrap(run.status)
        XCTAssertNotEqual(status, 0, "a failed download reads as a successful install")
        XCTAssertNotEqual(status, 143, "a failed download reads as the person's Stop")
        XCTAssertEqual(g.leftovers, [], "a failed download left a file in the temporary folder")
    }

    // MARK: - Output

    /// Job control does not hold the output back: a line the installer prints
    /// reaches the page while the installer is still running.
    func testALineArrivesWhileTheInstallerIsStillRunning() throws {
        let g = try ground("wrapper-streams")
        let go = g.root.appendingPathComponent("go")
        let installer = try g.installer("""
        echo first
        while [ ! -e \(go.path) ]; do /bin/sleep 0.05; done
        echo second
        """)
        let (handle, run) = start(try rehosted(try composedInstaller(), source: installer, temporaries: g.temporaries))
        defer { handle.terminate() }
        XCTAssertTrue(eventually(10) { run.lines.contains("first") },
                      "a line printed by a running installer never reached the page: \(run.lines)")
        XCTAssertNil(run.status, "precondition: the installer is still running")
        FileManager.default.createFile(atPath: go.path, contents: Data())
        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(run.lines.filter { !isJobNotice($0) }, ["first", "second"])
    }

    /// The console is where a person reads what the tools said. The shell's
    /// own bookkeeping about its background jobs — `[1]+ Done`, `[1]+ Exit 3`,
    /// `[1]+ Terminated: 15`, carrying `"$script"` and the download URL — is
    /// not something any tool said.
    func testTheConsoleCarriesOnlyWhatTheToolsPrinted() throws {
        let g = try ground("wrapper-console")
        let command = try composedInstaller()
        for (what, body) in [("success", "echo installed\nexit 0"), ("failure", "echo broken\nexit 3")] {
            g.reset()
            let installer = try g.installer(body)
            let (_, run) = start(try rehosted(command, source: installer, temporaries: g.temporaries))
            XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success)
            XCTAssertFalse(run.lines.isEmpty, "\(what): precondition — nothing was printed at all")
            XCTAssertEqual(run.lines.filter(isJobNotice), [],
                           "\(what): the shell's job notices reached the console: \(run.lines)")
        }
        g.reset()
        let installer = try g.installer("echo started\n/bin/sleep 30 &\nwait")
        let (handle, run) = start(try rehosted(command, source: installer, temporaries: g.temporaries))
        XCTAssertTrue(eventually(10) { run.lines.contains("started") }, "precondition: the installer never started")
        handle.terminate()
        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(run.lines.filter(isJobNotice), [],
                       "stop: the shell's job notices reached the console: \(run.lines)")
    }

    // MARK: - Stop

    /// A Stop that lands while the script is still being downloaded ends the
    /// download, runs nothing and leaves nothing. The download is held open by
    /// the test: the source is a pipe the test writes half a script into.
    func testAStopDuringTheDownloadEndsItAndLeavesNothing() throws {
        let g = try ground("wrapper-stop-download")
        let fifo = g.root.appendingPathComponent("install.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let ran = g.root.appendingPathComponent("ran")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: fifo, temporaries: g.temporaries))

        // Opening for writing returns once curl has opened it for reading.
        let opened = DispatchSemaphore(value: 0)
        let box = Run()
        DispatchQueue.global().async {
            let fd = Darwin.open(fifo.path, O_WRONLY)
            box.exit(fd)
            opened.signal()
        }
        XCTAssertEqual(opened.wait(timeout: .now() + 10), .success, "precondition: the download never started")
        let fd = try XCTUnwrap(box.status)
        defer { Darwin.close(fd) }
        let half = "#!/bin/bash\n/usr/bin/touch \(ran.path)\n# more to come"
        _ = half.withCString { Darwin.write(fd, $0, strlen($0)) }
        Thread.sleep(forTimeInterval: 0.2)                  // curl has read it and waits for the rest

        handle.terminate()

        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success,
                       "the stream never ended: the download still holds the pipe")
        XCTAssertEqual(run.status, 143, "a Stop in the download is not read as the person's Stop")
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ran.path), "the half-downloaded script was run")
        XCTAssertEqual(g.leftovers, [], "a Stop in the download left the script in the temporary folder")
    }

    /// Two Stops in a row — a second press, or Stop and a switch-off — while the
    /// installer runs: one exit, 143, everything the installer started gone,
    /// and the EXIT trap's `rm` run exactly once (counted off the shell's own
    /// trace of the engine's command).
    func testASecondStopEndsItOnceAndRemovesTheScriptOnce() throws {
        let g = try ground("wrapper-stop-twice")
        let installer = try g.installer("/bin/sleep 60 &\necho $! >> \(g.pids.path)\necho started\nwait")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: installer,
                                               temporaries: g.temporaries), trace: true)
        XCTAssertTrue(eventually(10) { run.lines.contains("started") && g.recordedPIDs.count == 2 },
                      "precondition: the installer and its child never started")

        handle.terminate()
        handle.terminate()

        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success,
                       "the stream never ended: something the wrapper started still holds its pipe")
        XCTAssertEqual(run.status, 143)
        XCTAssertTrue(eventually(5) { g.alive().isEmpty }, "still running after two Stops: \(g.alive())")
        XCTAssertEqual(g.leftovers, [])
        let removals = run.lines.filter { $0.range(of: #"^\++ /bin/rm -f "#, options: .regularExpression) != nil }
        XCTAssertEqual(removals.count, 1, "the EXIT trap ran \(removals.count) times: \(run.lines)")
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(run.exits, 1, "the stream ended \(run.exits) times")
    }

    /// **A Stop can land at any moment of the wrapper's life**, not only once
    /// the installer has settled — through `adopt` it lands a moment after the
    /// launch, and a person's press can land as the download hands over to the
    /// installer. Swept across the wrapper's first milliseconds, calibrated on
    /// this Mac: every Stop must end with no installer running, no download
    /// still writing, and nothing in the temporary folder.
    ///
    /// The stand-in installer replaces itself with a twenty-second sleep, so an
    /// installer that outlived the Stop also holds the page's pipe — the stream
    /// not ending is the same defect seen from the page.
    func testNoMomentOfStopLeavesTheInstallerOrItsScriptBehind() throws {
        let g = try ground("wrapper-stop-sweep")
        let command = try rehosted(try composedInstaller(),
                                   source: try g.installer("exec /bin/sleep 20"),
                                   temporaries: g.temporaries)

        // Calibrate: how long from the launch until the installer has started,
        // the shortest of three, read at a millisecond. The two moments the
        // sweep is after — the download launched, the installer launched —
        // both lie inside that span.
        var handover = TimeInterval.infinity
        for _ in 0..<3 {
            g.reset()
            let t0 = Date()
            let (probe, probeRun) = start(command)
            let deadline = Date().addingTimeInterval(10)
            while g.recordedPIDs.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertFalse(g.recordedPIDs.isEmpty, "precondition: the installer never started")
            handover = min(handover, Date().timeIntervalSince(t0))
            probe.terminate()
            XCTAssertEqual(probeRun.done.wait(timeout: .now() + 10), .success)
            g.killAll()
        }

        var outcomes: [String] = []
        var installerStarted = 0
        var installerNeverStarted = 0
        let steps = 200
        for _ in 0..<steps {
            g.reset()
            let delay = Double.random(in: 0...(handover * 1.2))
            let (handle, run) = start(command)
            Thread.sleep(forTimeInterval: delay)
            handle.terminate()
            let ended = run.done.wait(timeout: .now() + 3) == .success
            Thread.sleep(forTimeInterval: 0.03)            // an orphaned download finishes its write
            let alive = g.alive()
            let left = g.leftovers
            if g.recordedPIDs.isEmpty { installerNeverStarted += 1 } else { installerStarted += 1 }
            if !ended || !alive.isEmpty || !left.isEmpty {
                let mode = left.first.flatMap {
                    (try? FileManager.default.attributesOfItem(
                        atPath: g.temporaries.appendingPathComponent($0).path))?[.posixPermissions] as? Int
                }.map { String($0, radix: 8) } ?? "-"
                outcomes.append(String(format: "stop at %.1f ms: ended=%@ exit=%@ installer alive=%@ left=%@ mode=%@",
                                       delay * 1000, ended ? "yes" : "no",
                                       run.status.map { "\($0)" } ?? "none",
                                       "\(alive)", "\(left)", mode))
            }
            g.killAll()
            if !ended { _ = run.done.wait(timeout: .now() + 5) }
        }

        XCTAssertGreaterThan(installerNeverStarted, 0, "precondition: no Stop landed before the installer")
        XCTAssertGreaterThan(installerStarted, 0, "precondition: no Stop landed after the installer started")
        XCTAssertEqual(outcomes, [],
                       "\(outcomes.count) of \(steps) Stops left something behind "
                       + "(handover at \(String(format: "%.1f", handover * 1000)) ms)")
    }
}
