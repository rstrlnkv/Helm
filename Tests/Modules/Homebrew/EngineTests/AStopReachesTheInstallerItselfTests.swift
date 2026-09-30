// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

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

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

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
                                    transport: LocalTransport())
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
