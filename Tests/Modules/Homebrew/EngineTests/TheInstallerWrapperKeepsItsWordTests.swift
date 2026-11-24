import Foundation
import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **The `install.sh` wrapper under every input its own test does not feed it.**
///
/// `AStopReachesTheInstallerItselfTests` stops the wrapper once, while the
/// installer is running. The wrapper also has to: end a Stop that lands in the
/// download, survive a second Stop, and remove the script exactly once — and a
/// Stop can land at *any* moment of the wrapper's life, not only the one after
/// the installer has settled.
///
/// The command is the engine's own (taken from `installBrew` against fakes),
/// rehosted the way `TheDownloadedInstallerIsTidiedAwayTests` does it — the
/// `https://` word becomes a `file://` URL, `mktemp` is told where to write —
/// and run through the real `ShellProcessRunner.stream`, whose handle is what
/// Stop terminates. Nothing here reaches the network, root, or the real
/// installer; every installer is a stand-in written by the test.
final class TheInstallerWrapperKeepsItsWordTests: XCTestCase {

    // MARK: - Stop

    /// A Stop that lands while the script is still being downloaded ends the
    /// download, runs nothing and leaves nothing. The download is held open by
    /// the test: the source is a pipe the test writes half a script into.
    func testAStopDuringTheDownloadEndsItAndLeavesNothing() async throws {
        let g = try ground("wrapper-stop-download")
        let fifo = g.root.appendingPathComponent("install.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let ran = g.root.appendingPathComponent("ran")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: fifo, temporaries: g.temporaries))

        // Opening for writing returns once curl has opened it for reading.
        let box = Run()
        DispatchQueue.global().async {
            let fd = Darwin.open(fifo.path, O_WRONLY)
            box.exit(fd)
        }
        await waitUntilReached("precondition: the download started", within: .seconds(10)) { box.status != nil }
        let fd = try XCTUnwrap(box.status)
        defer { Darwin.close(fd) }
        let half = "#!/bin/bash\n/usr/bin/touch \(ran.path)\n# more to come"
        _ = half.withCString { Darwin.write(fd, $0, strlen($0)) }
        try await Task.sleep(for: .milliseconds(200))      // curl has read it and waits for the rest

        handle.terminate()

        XCTAssertEqual(run.finished(within: 10), .success,
                       "the stream never ended: the download still holds the pipe")
        XCTAssertEqual(run.status, 143, "a Stop in the download is not read as the person's Stop")
        await grace(0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ran.path), "the half-downloaded script was run")
        XCTAssertEqual(g.leftovers, [], "a Stop in the download left the script in the temporary folder")
    }

    /// Two Stops in a row — a second press, or Stop and a switch-off — while the
    /// installer runs: one exit, 143, everything the installer started gone,
    /// and the EXIT trap's `rm` run exactly once (counted off the shell's own
    /// trace of the engine's command).
    func testASecondStopEndsItOnceAndRemovesTheScriptOnce() async throws {
        let g = try ground("wrapper-stop-twice")
        let installer = try g.installer("/bin/sleep 60 &\necho $! >> \(g.pids.path)\necho started\nwait")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: installer,
                                               temporaries: g.temporaries), trace: true)
        await waitUntilReached("precondition: the installer and its child started", within: .seconds(10)) {
            run.lines.contains("started") && g.recordedPIDs.count == 2
        }

        handle.terminate()
        handle.terminate()

        XCTAssertEqual(run.finished(within: 10), .success,
                       "the stream never ended: something the wrapper started still holds its pipe")
        XCTAssertEqual(run.status, 143)
        await waitUntilReached("nothing still running after two Stops", within: .seconds(5)) { g.alive().isEmpty }
        XCTAssertEqual(g.leftovers, [])
        let removals = run.lines.filter { $0.range(of: #"^\++ /bin/rm -f "#, options: .regularExpression) != nil }
        XCTAssertEqual(removals.count, 1, "the EXIT trap ran \(removals.count) times: \(run.lines)")
        await grace(0.2)
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

// MARK: - Harness, shared by the two classes above

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

private extension XCTestCase {

    func ground(_ label: String) throws -> Ground {
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
}
