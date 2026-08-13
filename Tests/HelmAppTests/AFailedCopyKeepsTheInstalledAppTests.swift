// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import HelmApp

/// The one path in Helm that can destroy Helm.
///
/// The swap script used to `rm -rf` the installed bundle and *then* copy the new
/// one in, reading no status from the copy — with the downloaded zip already
/// deleted, the unzipped payload inside a directory the script removes whatever
/// happened, and the process that could have said something terminated before
/// the script did any work. Any refusal of that one `ditto` — a full disk, a
/// payload that will not read, a `/Applications` that stopped being writable
/// between the check and the copy — left the person with no Helm at all, nothing
/// on screen and nothing in the log.
///
/// So the script is driven here, verbatim, against scratch directories: the real
/// text, the real `mv`, the real `ditto`, the real `rm`. **Its one line that
/// reaches outside the swap is the relaunch**, and that is the only thing
/// substituted — `/usr/bin/open` for `/bin/echo`, which also makes the script
/// say which bundle it would have put back in front of the person. The
/// substitution is pinned: if the production text stops containing that exact
/// command, the precondition below fails rather than the run quietly testing a
/// script that no longer opens anything.
final class AFailedCopyKeepsTheInstalledAppTests: XCTestCase {

    private struct Run {
        let status: Int32
        /// What the script handed to the launcher — the bundle the person gets back.
        let opened: String
    }

    /// A pid that is certainly not running, so the script's wait for the app to
    /// quit is over before it starts. Spawned and reaped rather than invented:
    /// a number picked out of the air can belong to somebody.
    private func deadPID() throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try proc.run()
        proc.waitUntilExit()
        return proc.processIdentifier
    }

    /// The note is the app's own (`UpdateHandoff.file`) rather than a path
    /// invented here: what the script is given is what the app gives it, and a
    /// test that made up its own would pass while the two disagreed.
    private var marker: URL { UpdateHandoff.file }

    override func setUp() { super.setUp(); UpdateHandoff.clear() }
    override func tearDown() { UpdateHandoff.clear(); super.tearDown() }

    private func run(new: URL, install: URL, work: URL, in scratch: URL) throws -> Run {
        let text = UpdateSwap.script
        XCTAssertTrue(text.contains("/usr/bin/open \"$INSTALL\""),
                      "the script no longer relaunches through /usr/bin/open, so the "
                      + "substitution below is silently testing something else")
        let harness = text.replacingOccurrences(of: "/usr/bin/open", with: "/bin/echo")
        let scriptURL = scratch.appendingPathComponent("swap.sh")
        try harness.write(to: scriptURL, atomically: true, encoding: .utf8)

        let told = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
            + UpdateSwap.arguments(newApp: new.path,
                                   installPath: install.path,
                                   pid: try deadPID(),
                                   workDir: work.path,
                                   script: scriptURL.path)
        proc.standardOutput = told
        try proc.run()
        // Read before the wait: the script writes one line, but a pipe nobody
        // drains is how a test of a child process hangs for ever.
        let opened = String(bytes: told.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        proc.waitUntilExit()
        return Run(status: proc.terminationStatus,
                   opened: opened.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `install` holding one file, so "which bundle is there now" is a question
    /// with an answer rather than a size.
    private func bundle(_ url: URL, saying word: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        try word.write(to: url.appendingPathComponent("Contents/word"),
                       atomically: true, encoding: .utf8)
    }

    private func word(in bundle: URL) -> String? {
        try? String(contentsOf: bundle.appendingPathComponent("Contents/word"), encoding: .utf8)
    }

    func testACopyThatSucceedsReplacesTheBundleAndTakesTheNoteWithIt() throws {
        let scratch = scratchDirectory("swap-ok")
        let install = scratch.appendingPathComponent("Applications/Helm.app")
        let work = scratch.appendingPathComponent("work")
        let new = work.appendingPathComponent("Helm.app")
        try bundle(install, saying: "old")
        try bundle(new, saying: "new")
        UpdateHandoff.note(version: "0.9.9")

        let result = try run(new: new, install: install, work: work, in: scratch)

        XCTAssertEqual(result.status, 0, "the script reported a failure it did not have")
        XCTAssertEqual(word(in: install), "new", "the update never arrived")
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.path + ".helm-old"),
                       "the copy of the old bundle was left in /Applications for ever")
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path),
                       "the unzipped payload was left behind after a swap that worked")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path),
                       "the note saying an update was in flight survived the update, so "
                       + "the next launch reports a failure that did not happen")
        XCTAssertEqual(result.opened, install.path)
    }

    func testACopyThatFailsPutsTheOldBundleBackAndKeepsTheNoteAndThePayload() throws {
        let scratch = scratchDirectory("swap-fail")
        let install = scratch.appendingPathComponent("Applications/Helm.app")
        let work = scratch.appendingPathComponent("work")
        // Nothing was ever unzipped here: `ditto` refuses, which is every reason
        // it can refuse as far as this script is concerned — it reads a status.
        let new = work.appendingPathComponent("Helm.app")
        try bundle(install, saying: "old")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        UpdateHandoff.note(version: "0.9.9")

        let result = try run(new: new, install: install, work: work, in: scratch)

        // The subject first: an absence proves nothing if the copy never failed.
        XCTAssertNotEqual(result.status, 0,
                          "the copy did not fail, so everything below is an assertion "
                          + "about a swap that simply worked")
        XCTAssertEqual(word(in: install), "old",
                       "the installed app is gone — the person pressed «Update & Relaunch» "
                       + "and has no Helm on the machine")
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.path + ".helm-old"),
                       "the old bundle was put back and its copy left beside it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: work.path),
                      "the payload was deleted on the failure path, so there is nothing "
                      + "left for a person to install by hand")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "the note the next launch reads was cleared by a swap that failed, "
                      + "so the failure is reported nowhere at all")
        XCTAssertEqual(result.opened, install.path,
                       "the script relaunched something other than the bundle it left "
                       + "in place")
    }

    /// The script names `$1 … $n` and the spawn builds the array; nothing between
    /// them is checked by a compiler, and a path that arrives one place to the
    /// left is a path this script deletes.
    func testTheScriptAndTheSpawnAgreeOnHowManyArgumentsThereAre() {
        let named = (1...9).filter { UpdateSwap.script.contains("$\($0)") }
        XCTAssertEqual(named, Array(1...named.count),
                       "the script reads \(named) — a gap means an argument nobody passes")
        XCTAssertEqual(UpdateSwap.arguments(newApp: "a", installPath: "b", pid: 1,
                                            workDir: "c", script: "d").count,
                       named.count,
                       "the spawn passes a different number of paths than the script reads")
    }

    /// The bundle cannot be moved aside at all — a `/Applications` that is not
    /// writable, which `isWritableFile` answered "yes" about a second earlier.
    /// Nothing may be copied over the installed app in that state: a `ditto`
    /// into a live bundle merges into it, which is how a half-new, half-old
    /// Helm gets made.
    func testABundleThatCannotBeMovedAsideIsNotCopiedOver() throws {
        let scratch = scratchDirectory("swap-stuck")
        let applications = scratch.appendingPathComponent("Applications")
        let install = applications.appendingPathComponent("Helm.app")
        let work = scratch.appendingPathComponent("work")
        let new = work.appendingPathComponent("Helm.app")
        try bundle(install, saying: "old")
        try bundle(new, saying: "new")
        UpdateHandoff.note(version: "0.9.9")
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: applications.path)
        // Or the scratch teardown cannot drain the directory it just locked.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: applications.path)
        }

        let result = try run(new: new, install: install, work: work, in: scratch)

        XCTAssertNotEqual(result.status, 0, "the move aside did not fail, so this test "
                          + "is about an ordinary swap")
        XCTAssertEqual(word(in: install), "old",
                       "the installed bundle was written into after it could not be "
                       + "moved out of the way")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "nothing will tell the next launch that the update never went in")
    }
}
