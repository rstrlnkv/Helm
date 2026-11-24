// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// **The report belongs to whichever Helm launches next.**
///
/// An update that goes wrong goes wrong after `NSApp.terminate`, with no
/// screen, no view model and no log. So the app writes the note *before* the
/// handover, and the script's only duty is to take it away when the copy
/// landed. The failure is then reported by an act nobody has to remember,
/// which also covers what a status file written afterwards would miss: a
/// script that was killed, a machine that lost power, a swap never started.
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
        _ = UpdateHandoff.note(version: "0.9.9")
        XCTAssertEqual(UpdateHandoff.take(), "0.9.9",
                       "the note an update was in flight did not survive being written")
    }

    /// Read once. A note left in place would tell every later launch about one
    /// update that failed a month ago.
    func testTakingItTakesItAway() {
        _ = UpdateHandoff.note(version: "0.9.9")
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
        _ = UpdateHandoff.note(version: "0.9.9")

        UpdateHandoff.reportAtLaunch()

        let said = log.recentEntries().map(\.message).joined(separator: "\n")
        XCTAssertTrue(said.contains("0.9.9"),
                      "an update that never went in is reported nowhere — the person "
                      + "pressed «Update & Relaunch», got the version they already had "
                      + "back, and there is nothing to triage: \(said)")
        XCTAssertNil(UpdateHandoff.take(), "the report left the note behind")
    }

    /// And the launch after a swap that worked says nothing, or the line means
    /// nothing.
    func testASwapThatWorkedIsNotReportedAsAFailure() {
        let log = listeningLog()
        // The subject has to be able to happen: the same call, with a note,
        // writes a line — otherwise "nothing was said" is an absence of
        // everything.
        _ = UpdateHandoff.note(version: "0.9.9")
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

    /// The sentence on the updates card does not depend on the log. A
    /// Beta build ships with logging off, so a report that travels only through
    /// `HelmLog` reaches nobody there.
    func testTheFailureIsPublishedWithLoggingOff() throws {
        let log = HelmLog.shared
        log.setEnabled(false)
        // A note in today's format: the bare version, as `note(version:)` writes it.
        XCTAssertTrue(UpdateHandoff.note(version: "0.9.9"), "precondition: the note was written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: UpdateHandoff.file.path),
                      "precondition: the note is on disk")

        let published = UpdateHandoff.reportAtLaunch()

        XCTAssertEqual(published, "0.9.9",
                       "with logging off the failed update is said nowhere: the person "
                       + "pressed «Update & Relaunch» and the card is silent about it")
    }

    func testTheCardSaysItWhenNothingNewerHasBeenSaid() {
        func drawn(note: UpdateService.Note?, unfinished: Bool) -> UpdateCard {
            UpdateCard.drawn(installState: .idle, checking: false, hasRelease: false,
                             hasAhead: false, note: note, hasUnfinishedUpdate: unfinished)
        }
        XCTAssertEqual(drawn(note: nil, unfinished: true), .unfinishedUpdate)
        XCTAssertEqual(drawn(note: nil, unfinished: false), .lastChecked)
        XCTAssertEqual(drawn(note: .upToDate, unfinished: true), .upToDate,
                       "a check that just answered is newer than the failure")
    }
}
