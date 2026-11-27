// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import HelmApp

/// The one path in Helm that can destroy Helm.
///
/// The swap script waits for Helm to quit before touching the installed bundle.
/// It attempts to remove the staged payload after a successful copy and retains
/// it on failure. If the copy fails, the script attempts relaunch only if it
/// puts the original back. If both the install path and a prior backup are
/// occupied, it leaves both alone and does not relaunch.
///
/// These tests run the swap script against scratch directories. A recorder stands
/// in for `/usr/bin/open` and captures the path and bundle contents at relaunch.
/// The restore-denial case substitutes `mv` only to refuse moving the scratch
/// backup back into place; other moves use the real `mv`.
final class AFailedCopyKeepsTheInstalledAppTests: XCTestCase {

    private struct Run {
        let status: Int32
        let errors: String
        /// What the script handed to the launcher, and what was there at that moment.
        let opened: String?
        let openedWord: String?
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

    private func run(new: URL, install: URL, work: URL, in scratch: URL,
                     denyRestore: Bool = false) throws -> Run {
        let text = UpdateSwap.script
        XCTAssertTrue(text.contains("/usr/bin/open \"$INSTALL\""),
                      "the script no longer relaunches through /usr/bin/open, so the "
                      + "substitution below is silently testing something else")
        let recorder = #"""
        record_open() {
          printf '%s\n' "$@" >> "$0.opened"
          if [ -f "$1/Contents/word" ]; then
            /bin/cat "$1/Contents/word" >> "$0.opened-word"
          fi
        }
        """#
        var harness = recorder + "\n" + text.replacingOccurrences(of: "/usr/bin/open", with: "record_open")
        if denyRestore {
            let movePort = #"""
            fixture_mv() {
              local fixture="${0%/*}/Applications/Helm.app"
              if [ "$#" -eq 2 ] && [ "$1" = "$fixture.helm-old" ] && [ "$2" = "$fixture" ]; then
                printf '%s\n' 'test: denied backup restore' >&2
                return 1
              fi
              /bin/mv "$@"
            }
            """#
            harness = movePort + "\n" + harness.replacingOccurrences(of: "/bin/mv", with: "fixture_mv")
        }
        let scriptURL = scratch.appendingPathComponent("swap.sh")
        try harness.write(to: scriptURL, atomically: true, encoding: .utf8)

        let result = try runChild("/bin/bash", [scriptURL.path]
            + UpdateSwap.arguments(newApp: new.path,
                                   installPath: install.path,
                                   pid: try deadPID(),
                                   workDir: work.path,
                                   script: scriptURL.path))
        let opened = try? String(contentsOf: scriptURL.appendingPathExtension("opened"), encoding: .utf8)
        let openedWord = try? String(contentsOf: scriptURL.appendingPathExtension("opened-word"), encoding: .utf8)
        return Run(status: result.status, errors: result.errors,
                   opened: opened?.trimmingCharacters(in: .newlines),
                   openedWord: openedWord)
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
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"),
                      "the note was never planted, so what this test reads back "
                      + "about it proves nothing")

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
        XCTAssertEqual(result.openedWord, "new", "the replaced bundle was not in place at relaunch")
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
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"),
                      "the note was never planted, so what this test reads back "
                      + "about it proves nothing")

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

    func testAnInterruptedSwapWithOnlyTheBackupRestoresAndRelaunchesTheOriginal() throws {
        let scratch = scratchDirectory("swap-interrupted")
        let install = scratch.appendingPathComponent("Applications/Helm.app")
        let aside = URL(fileURLWithPath: install.path + ".helm-old")
        let work = scratch.appendingPathComponent("work")
        let new = work.appendingPathComponent("Helm.app")
        try bundle(aside, saying: "old")
        try bundle(new, saying: "new")
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"), "the handoff note was never planted")

        let result = try run(new: new, install: install, work: work, in: scratch)

        XCTAssertNotEqual(result.status, 0, "restoring the original must not report a successful update")
        XCTAssertEqual(word(in: install), "old",
                       "the original was not restored: backup=\(word(in: aside) ?? "missing")")
        XCTAssertEqual(word(in: new), "new", "the retry did not preserve the staged payload")
        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "0.9.9",
                       "the retry did not preserve the handoff note")
        XCTAssertEqual(result.opened, install.path, "the retry must attempt one relaunch at the installed path")
        XCTAssertEqual(result.openedWord, "old", "the retry attempted a relaunch without the original in place")
    }

    func testAnInterruptedSwapWithAPartialInstallLeavesBothBundlesUntouchedWithoutRelaunch() throws {
        let scratch = scratchDirectory("swap-interrupted-partial")
        let applications = scratch.appendingPathComponent("Applications")
        let install = applications.appendingPathComponent("Helm.app")
        let aside = URL(fileURLWithPath: install.path + ".helm-old")
        let work = scratch.appendingPathComponent("work")
        // No new bundle was left at the source, so `ditto` fails if the retry reaches it.
        let new = work.appendingPathComponent("Helm.app")
        try bundle(aside, saying: "old")
        try bundle(install, saying: "partial")
        let originalTree = tree(under: applications)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"), "the handoff note was never planted")

        let result = try run(new: new, install: install, work: work, in: scratch)

        XCTAssertNotEqual(result.status, 0, "the retry reported success without a new bundle")
        XCTAssertEqual(tree(under: applications), originalTree, "the retry changed the bundle tree")
        XCTAssertEqual(word(in: install), "partial", "the retry changed the partial install")
        XCTAssertEqual(word(in: aside), "old", "the retry changed the original backup")
        XCTAssertNil(result.opened, "the retry attempted to relaunch with both paths occupied")
        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "0.9.9",
                       "the failed retry did not preserve the handoff note")
    }

    func testAFailedCopyDoesNotRelaunchWhenTheBackupCannotBeMovedBack() throws {
        let scratch = scratchDirectory("swap-restore-denied")
        let install = scratch.appendingPathComponent("Applications/Helm.app")
        let aside = URL(fileURLWithPath: install.path + ".helm-old")
        let work = scratch.appendingPathComponent("work")
        let new = work.appendingPathComponent("Helm.app") // Missing, so `ditto` fails.
        try bundle(install, saying: "old")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"), "the handoff note was never planted")

        let result = try run(new: new, install: install, work: work, in: scratch, denyRestore: true)

        XCTAssertTrue(result.errors.contains("test: denied backup restore"),
                      "the scratch backup move was never denied: \(result.errors)")
        XCTAssertNotEqual(result.status, 0, "the failed rollback reported a successful update")
        XCTAssertEqual(word(in: aside), "old", "the denied rollback lost the original bundle")
        XCTAssertFalse(FileManager.default.fileExists(atPath: install.path))
        XCTAssertNil(result.opened, "the script attempted a relaunch after the restore was denied")
        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "0.9.9",
                       "the failed rollback did not preserve the handoff note")
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
    /// Nothing may be copied over the installed app in that state, for the
    /// reason the `UpdateSwap` doc gives.
    func testABundleThatCannotBeMovedAsideIsNotCopiedOver() throws {
        let scratch = scratchDirectory("swap-stuck")
        let applications = scratch.appendingPathComponent("Applications")
        let install = applications.appendingPathComponent("Helm.app")
        let work = scratch.appendingPathComponent("work")
        let new = work.appendingPathComponent("Helm.app")
        try bundle(install, saying: "old")
        try bundle(new, saying: "new")
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"),
                      "the note was never planted, so what this test reads back "
                      + "about it proves nothing")
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
