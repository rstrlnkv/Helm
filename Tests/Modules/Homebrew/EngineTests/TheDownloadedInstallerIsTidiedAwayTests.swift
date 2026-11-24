// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest

/// **The command `installBrew` composes is a program, so it is tested by
/// running it.**
///
/// It downloads the Homebrew installer into a temporary file, runs it, and
/// removes it, under `set -e`. A failed installer must not end the shell before
/// the `rm`: a script left in the temporary directory is a program another
/// process can read and perhaps rewrite before a retry runs it.
///
/// Nothing here reaches the network or root. The string is taken from the
/// engine itself, with two fixtures substituted:
///
///   * the `https://` word becomes a `file://` URL of a script this test wrote,
///     so the exit code is the test's to choose;
///   * `mktemp` is given `-p`, because macOS's `mktemp` ignores `TMPDIR`, and a
///     test that cannot say where the file lands cannot say whether it is gone.
final class TheDownloadedInstallerIsTidiedAwayTests: XCTestCase {

    // MARK: - Plumbing

    /// Runs the engine's command with `script` standing in for the downloaded
    /// installer, and answers what the shell exited with and what it left in the
    /// temporary folder.
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
        process.arguments = ["-c", try rehosted(composedInstaller(), source: installer,
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

    /// The installer failed, and the downloaded script is still removed.
    func testAFailedInstallerIsStillRemoved() throws {
        let result = try runInstaller(exiting(3), label: "brew-installer-failed")

        XCTAssertEqual(result.leftovers, [],
                       "the downloaded installer was left in the temporary folder")
        XCTAssertEqual(result.status, 3,
                       "the installer's exit code stopped reaching the module, which is what "
                       + "tells the person the install failed")
    }

    /// The control: a successful install is removed and reports success, so
    /// «leaves nothing behind» is not met by a command that downloads nothing.
    func testASuccessfulInstallerIsRemovedAndReportsSuccess() throws {
        let result = try runInstaller(exiting(0), label: "brew-installer-ok")

        XCTAssertEqual(result.leftovers, [])
        XCTAssertEqual(result.status, 0)
    }

    /// The fixture is really run: an installer written to exit 3 does, so the
    /// failing case is not a `curl` that fetched nothing.
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
