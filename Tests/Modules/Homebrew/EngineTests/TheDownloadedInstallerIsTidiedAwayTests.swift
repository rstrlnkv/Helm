// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **The command `installBrew` composes is a program, so it is tested by
/// running it.**
///
/// It downloads the Homebrew installer into a temporary file, runs it, and
/// removes it — and the whole string opens with `set -e`, which ends the shell
/// at the first command that fails. An installer that exits non-zero is
/// therefore the last thing the shell does: the `rm` after it never runs, and
/// the downloaded script stays in the temporary directory, where it is a
/// program somebody else's process can read and (with the right umask on the
/// folder) rewrite before a retry runs it again.
///
/// Nothing here reaches the network or root. The composed string is taken from
/// the engine itself — not spelled a second time here, which is how the two
/// sides of a test come to agree with each other and with nothing else — and
/// two fixtures are substituted into it:
///
///   * the `https://` word becomes a `file://` URL of a script this test wrote,
///     so `curl` fetches a local file and the exit code is the test's to choose;
///   * `mktemp` is given `-p`, because macOS's `mktemp` ignores `TMPDIR`
///     (measured: it answers out of `/var/folders/…/T` whatever the environment
///     says), and a test that cannot say where the file lands cannot say whether
///     it is still there.
///
/// Everything the defect lives in — `set -e`, the ordering, how the exit code is
/// carried past the `rm` — is run exactly as the engine composed it.
final class TheDownloadedInstallerIsTidiedAwayTests: XCTestCase {

    // MARK: - Fakes

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    /// Says yes at the dialog and records nothing else: the preparation script
    /// is another test's subject.
    private struct AllowingPrivileged: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { true }
    }

    /// Keeps what it was asked to stream and never finishes it — the engine's
    /// busy gate stays shut, which is what the other tests here rely on and
    /// what stops this one from racing its own teardown.
    private final class RecordingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _args: [[String]] = []
        var args: [[String]] { lock.lock(); defer { lock.unlock() }; return _args }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            lock.lock(); _args.append(args); lock.unlock()
            return NoProcess()
        }
    }

    // MARK: - Plumbing

    /// The string the engine would have handed to `/bin/bash -c`.
    private func composedInstaller() throws -> String {
        let runner = RecordingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: AllowingPrivileged(), user: "tester",
                                    transport: LocalTransport())
        engine.installBrew()
        let args = try XCTUnwrap(runner.args.first, "the engine launched nothing")
        XCTAssertEqual(args.first, "-c", "the installer stopped being a `bash -c` string")
        return try XCTUnwrap(args.last)
    }

    /// The engine's own string with the two fixtures in it. The URL is found by
    /// its scheme rather than written out again, so a moved installer changes
    /// nothing here.
    private func rehosted(_ command: String, installer: URL, temporaries: URL) throws -> String {
        let url = try XCTUnwrap(command.split(separator: " ")
                                    .first { $0.hasPrefix("https://") },
                                "the command downloads nothing over https any more")
        return command
            .replacingOccurrences(of: String(url), with: "file://\(installer.path)")
            .replacingOccurrences(of: "/usr/bin/mktemp",
                                  with: "/usr/bin/mktemp -p \(temporaries.path) -t helm")
    }

    /// Runs the engine's command with `script` standing in for the downloaded
    /// installer, and answers what the shell exited with and what it left in the
    /// temporary folder.
    ///
    /// One launcher rather than one per test: the three cases differ only in
    /// what the installer they download does, and a second copy of «write the
    /// script, substitute, launch, wait» is how one of them comes to be running
    /// something else than the others.
    private func runInstaller(_ script: String, label: String,
                              file: StaticString = #filePath, line: UInt = #line)
    throws -> (status: Int32, leftovers: [String]) {
        let root = scratchDirectory(label, file: file, line: line)
        let temporaries = root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)
        let installer = root.appendingPathComponent("install.sh")
        try script.write(to: installer, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", try rehosted(composedInstaller(), installer: installer,
                                                temporaries: temporaries)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        return (process.terminationStatus,
                try FileManager.default.contentsOfDirectory(atPath: temporaries.path))
    }

    /// An installer that does nothing but end with `code`.
    private func exiting(_ code: Int32) -> String { "#!/bin/bash\nexit \(code)\n" }

    // MARK: - The tidying

    /// The defect: the installer failed, so `set -e` ended the shell before the
    /// `rm`, and the downloaded script is still on disk.
    func testAFailedInstallerIsStillRemoved() throws {
        let result = try runInstaller(exiting(3), label: "brew-installer-failed")

        XCTAssertEqual(result.leftovers, [],
                       "the downloaded installer was left in the temporary folder")
        XCTAssertEqual(result.status, 3,
                       "the installer's exit code stopped reaching the module, which is what "
                       + "tells the person the install failed")
    }

    /// The control: the path that always worked still works, in both halves.
    /// Without it, «leaves nothing behind» is satisfied by a command that
    /// downloads nothing.
    func testASuccessfulInstallerIsRemovedAndReportsSuccess() throws {
        let result = try runInstaller(exiting(0), label: "brew-installer-ok")

        XCTAssertEqual(result.leftovers, [])
        XCTAssertEqual(result.status, 0)
    }

    /// And the fixture is proven on the machine rather than assumed: an
    /// installer this test writes to exit 3 is really run, so the failing case
    /// above is a failing installer and not a `curl` that fetched nothing.
    /// Without this, a broken substitution would make both tests above pass on
    /// a command that never ran anything.
    func testTheFixtureReallyRunsTheScriptItWrote() throws {
        let witness = scratchDirectory("brew-installer-witness").appendingPathComponent("it-ran")

        let result = try runInstaller("#!/bin/bash\n/usr/bin/touch \(witness.path)\nexit 5\n",
                                      label: "brew-installer-fixture")

        XCTAssertTrue(FileManager.default.fileExists(atPath: witness.path),
                      "the downloaded script was never executed, so neither test above is "
                      + "measuring what it says it is")
        XCTAssertEqual(result.status, 5)
    }
}
