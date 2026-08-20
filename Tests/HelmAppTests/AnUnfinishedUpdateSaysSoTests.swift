// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// **The report belongs to whichever Helm launches next.**
///
/// An update that goes wrong goes wrong after `NSApp.terminate`: there is no
/// screen, no view model and no log — the process that owns all three is what
/// the swap script waits for before it starts. So the note is written *before*
/// the handover, by the app, and the script's only duty is to take it away when
/// the copy landed. The failure is then reported by an act nobody had to
/// remember to perform, which is also why it covers the cases a status file
/// written afterwards would miss: a script that was killed, a machine that lost
/// power, a swap that never started at all.
final class AnUnfinishedUpdateSaysSoTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UpdateHandoff.clear()
    }

    /// The log is off in a test process; these two are about what it says, so
    /// they turn it on and put it back.
    private func listeningLog() -> HelmLog {
        let log = HelmLog.shared
        log.setEnabled(true)
        addTeardownBlock { log.setEnabled(false); log.clearTail() }
        log.clearTail()
        return log
    }

    override func tearDown() {
        UpdateHandoff.clear()
        super.tearDown()
    }

    func testTheNoteOutlivesTheProcessThatWroteIt() {
        UpdateHandoff.note(version: "0.9.9")
        XCTAssertEqual(UpdateHandoff.take(), "0.9.9",
                       "the note an update was in flight did not survive being written")
    }

    /// Read once. A note left in place would tell every launch from now on about
    /// one update that failed a month ago.
    func testTakingItTakesItAway() {
        UpdateHandoff.note(version: "0.9.9")
        XCTAssertNotNil(UpdateHandoff.take(), "precondition: there was a note to take")
        XCTAssertNil(UpdateHandoff.take(),
                     "the note survives being read, so every launch from now on reports "
                     + "the same failure")
    }

    func testAnOrdinaryLaunchHasNothingToReport() {
        XCTAssertNil(UpdateHandoff.take())
    }

    /// The whole finding, end to end: what the swap script leaves behind is what
    /// the next launch says out loud.
    func testTheLaunchAfterAFailedSwapPutsItInTheLog() {
        let log = listeningLog()
        UpdateHandoff.note(version: "0.9.9")

        UpdateHandoff.reportAtLaunch()

        let said = log.recentEntries().map(\.message).joined(separator: "\n")
        XCTAssertTrue(said.contains("0.9.9"),
                      "an update that never went in is reported nowhere — the person "
                      + "pressed «Update & Relaunch», got the version they already had "
                      + "back, and there is nothing to triage: \(said)")
        XCTAssertNil(UpdateHandoff.take(), "the report left the note behind")
    }

    /// **Read off the source, and the reason is worth stating.** Driving this
    /// means `Installer.installZip`, which ends in `NSApp.terminate` and hands a
    /// detached script the path of the bundle the suite is running out of. The
    /// script itself is driven for real next door
    /// (`AFailedCopyKeepsTheInstalledAppTests`); this pins the half
    /// that decides what the script is given and when.
    func testTheAppWritesTheNoteBeforeItHandsOver() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/Installer.swift")
        XCTAssertGreaterThan(source.count, 2000, "the installer was not read at all")

        let note = try XCTUnwrap(source.range(of: "UpdateHandoff.note("),
                                 "the installer hands the swap over without leaving a note, "
                                 + "so a swap that fails is reported nowhere: the app that "
                                 + "owns the log is dead before the script starts")
        // The hand-over, by the name of the door it goes through. It was
        // `proc.run()` until 2026-08-20, when the launch moved onto
        // `HelmProcess.start` — the one that answers instead of raising, since
        // an `NSTask` that raises aborts the app, and here it would abort it
        // while it is replacing itself. Any source scan anchors on a spelling;
        // what this one can do is say which spelling, so the next rename is an
        // edit here rather than a puzzle.
        let spawn = try XCTUnwrap(source.range(of: "HelmProcess.start(proc"),
                                  "the installer no longer hands the swap over through "
                                  + "`HelmProcess.start`, so this scan cannot see where the "
                                  + "hand-over is — find the launch and name it here")
        XCTAssertLessThan(note.lowerBound, spawn.lowerBound,
                          "the note is written after the handover, so a swap that beats "
                          + "this process to it clears a note that is not there yet")

        XCTAssertTrue(source.contains("UpdateSwap.script"),
                      "the installer carries a swap script of its own again — one that "
                      + "no test drives and that nothing keeps in step with the arguments")
        XCTAssertTrue(source.contains("UpdateSwap.arguments("),
                      "the spawn assembles its own argument array, which is the order "
                      + "spelled twice with nothing between the halves")
    }

    /// And the launch after a swap that worked says nothing, or the line means
    /// nothing.
    func testASwapThatWorkedIsNotReportedAsAFailure() {
        let log = listeningLog()
        // The subject has to be able to happen: the same call, with a note,
        // writes a line — otherwise "nothing was said" is an absence of
        // everything.
        UpdateHandoff.note(version: "0.9.9")
        log.clearTail()
        UpdateHandoff.reportAtLaunch()
        XCTAssertFalse(log.recentEntries().isEmpty,
                       "precondition: reporting an unfinished update writes nothing at "
                       + "all, so the absence below proves nothing")

        log.clearTail()
        UpdateHandoff.reportAtLaunch()
        XCTAssertTrue(log.recentEntries().isEmpty,
                      "an update that installed cleanly is reported as a failure")
    }
}
