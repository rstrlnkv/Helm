import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **A Stop that finds the installer already past the point where it can be
/// stopped reads as what the installer did.**
///
/// The wrapper ends with `exit 143` when a Stop was pressed, and a wrapper
/// whose installer answered 0 used to run that trap after the installer's
/// exit: Homebrew was installed and the page said "stopped". The 143 belongs
/// to a press that stopped something. The installer here ignores TERM (and so
/// does the `sleep` it starts, which inherits the disposition), so the Stop
/// lands while it is running and cannot end it — the same wrapper state as a
/// press that arrives a moment after the installer's own exit, without a race
/// to hit.
///
/// The command is the engine's own, rehosted the way
/// `TheInstallerWrapperKeepsItsWordTests` does it; nothing here reaches the
/// network, root or the real installer.
final class AStopAfterTheInstallerHasSucceededStillReadsAsInstalledTests: XCTestCase {

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

    /// Runs the wrapper against an installer with this body, presses Stop once
    /// it has printed `installed`, and reports how the wrapper ended.
    private func stopped(installerBody: String, label: String) throws -> (status: Int32?, left: [String]) {
        let root = scratchDirectory(label)
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let installer = root.appendingPathComponent("install.sh")
        try "#!/bin/bash\n\(installerBody)\n".write(to: installer, atomically: true, encoding: .utf8)
        let command = try rehosted(try composedInstaller(), source: installer, temporaries: temporaries)

        let run = Run()
        let handle = ShellProcessRunner().stream("/bin/bash", ["-c", command], env: [:], reach: .wholeGroup,
                                                 onLine: { run.line($0) }, onExit: { run.exit($0) })
        let deadline = Date().addingTimeInterval(10)
        while !run.lines.contains("installed"), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(run.lines.contains("installed"), "precondition: the installer never started")
        handle.terminate()
        XCTAssertEqual(run.done.wait(timeout: .now() + 10), .success, "the stream never ended")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: temporaries.path)) ?? []
        return (run.status, left)
    }

    func testAStopWhileTheInstallerRunsToItsOwnSuccessReadsAsSuccess() throws {
        let outcome = try stopped(installerBody: "trap '' TERM; echo installed; /bin/sleep 0.4; exit 0",
                                  label: "stop-over-success")
        XCTAssertEqual(outcome.status, 0, "an installer that finished with 0 was reported as stopped")
        XCTAssertEqual(outcome.left, [], "the downloaded installer stayed behind")
    }

    /// The other side of it: a press that ended the installer is still a Stop.
    func testAStopThatEndsTheInstallerStillReadsAsStopped() throws {
        let outcome = try stopped(installerBody: "echo installed; exec /bin/sleep 30", label: "stop-ends-installer")
        XCTAssertEqual(outcome.status, 143, "a Stop that ended the installer did not read as stopped")
        XCTAssertEqual(outcome.left, [], "the downloaded installer stayed behind")
    }
}
