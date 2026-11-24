import Foundation
import HelmTestSupport
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

    private struct Rig {
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done, holds: false)
        let runner = ScriptedRunner(streams: .hold)
        let news = EngineNews<HomebrewNews>()
        let engine: HomebrewEngine
        let tape: AsyncStream<HomebrewNews>

        init() {
            engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    news: news, marker: InMemoryOpMarker(),
                                    tools: tools, ticker: ticker)
            tape = news.stream()
        }

        func terminalStates() async -> [OpState] { await replay(news, from: tape).states.filter { $0.phase != .running } }
    }

    override func setUp() {
        super.setUp()
        _ = HelmLog.shared.recentEntries()
        tailTheLog()
    }

    private var homebrewLines: [String] {
        loggedLines(HomebrewEngine.moduleID)
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
        rig.runner.finishAll(code: 0)

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

    /// An installer that answers the Stop by failing in its own way — exit 1
    /// from its own TERM handler. The Stop ended it, so the page reads 143.
    func testAnInstallerThatAnswersAStopWithItsOwnFailureReadsAsStopped() async throws {
        let g = try ground("stop-own-failure",
                           installer: "trap 'exit 1' TERM\ntouch $MARK\necho installing\n"
                                    + "while :; do /bin/sleep 0.05; done")
        let (handle, run) = start(try rehosted(try composedInstaller(), source: g.installer, temporaries: g.temporaries))
        await waitUntilReached("precondition: the installer started", within: .seconds(10)) { run.lines.contains("installing") }

        handle.terminate()

        XCTAssertEqual(run.finished(within: 10), .success, "the stream never ended")
        XCTAssertEqual(run.status, 143, "a Stop that ended the installer read as its own failure")
        XCTAssertEqual(g.leftovers, [], "the downloaded installer stayed behind")
    }

    /// **A Stop at every moment of the wrapper's life, against an installer
    /// that cannot be stopped once it has run its first line.** Either the
    /// installer ran and the wrapper reports its 0, or it never ran and the
    /// wrapper reports non-zero, and the temporary folder is empty either way. A
    /// 143 over an installer that ran claims a stop that did not happen; a 0
    /// over one that did not run reports an install that never happened.
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
