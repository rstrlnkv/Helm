// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// **The reset's own line survives the relaunch.**
///
/// Past defect: the reset trashes the log folder, the latch of the one-time
/// pre-redaction purge goes with it, and the next launch purged the fresh log
/// holding the reset's `removed N, refused M`. `ResetPlan.relatchTheLogPurge`
/// writes the latch again; the order is guarded in `AResetAsksBeforeItDeletesTests`.
final class AResetKeepsItsOwnRecordTests: XCTestCase {

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    private func logText() -> String {
        (try? String(contentsOf: HelmLog.fileURL, encoding: .utf8)) ?? ""
    }

    func testALineWrittenAfterTheFolderWasTrashedSurvivesTheNextStart() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: HelmLog.directory)   // the reset's trash: folder and latch
        HelmLog.shared.setEnabled(true)
        let marker = "reset kept \(UUID().uuidString)"
        HelmLog.shared.info("reset", marker)
        HelmLog.shared.rewritePurgeLatch()
        _ = HelmLog.shared.recentEntries()   // drains the queue
        XCTAssertTrue(logText().contains(marker), "nothing was written, so nothing below is a test")

        HelmLog.shared.start(version: "0.0.0", override: true)
        _ = HelmLog.shared.recentEntries()

        XCTAssertTrue(logText().contains(marker),
                      "the next launch purged the log holding the reset's own record")
    }

    /// An empty latch an older build left still stops the purge.
    func testAnEmptyLatchFromAnOlderBuildStillStopsThePurge() throws {
        let fm = FileManager.default
        XCTAssertTrue(PrivateFile.directory(at: HelmLog.directory))
        fm.createFile(atPath: HelmLog.resetMarkerURL.path, contents: Data())
        let marker = "older latch \(UUID().uuidString)"
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.info("app", marker)
        _ = HelmLog.shared.recentEntries()
        XCTAssertTrue(logText().contains(marker))

        HelmLog.shared.start(version: "0.0.0", override: true)
        _ = HelmLog.shared.recentEntries()

        XCTAssertTrue(logText().contains(marker))
        XCTAssertEqual(try Data(contentsOf: HelmLog.resetMarkerURL), Data())
    }

    /// The purge itself leaves the latch, empty, and a later start keeps new lines.
    func testThePurgeWritesTheLatchAndTheNextStartKeepsANewLine() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: HelmLog.directory)
        XCTAssertTrue(PrivateFile.directory(at: HelmLog.directory))
        let old = "before redact \(UUID().uuidString)"
        try Data((old + "\n").utf8).write(to: HelmLog.fileURL)

        HelmLog.shared.start(version: "0.0.0", override: true)
        _ = HelmLog.shared.recentEntries()

        XCTAssertFalse(logText().contains(old), "the old log was not purged")
        XCTAssertTrue(fm.fileExists(atPath: HelmLog.resetMarkerURL.path), "the purge left no latch")
        XCTAssertEqual(try Data(contentsOf: HelmLog.resetMarkerURL), Data())

        HelmLog.shared.setEnabled(true)
        let fresh = "after purge \(UUID().uuidString)"
        HelmLog.shared.info("app", fresh)
        _ = HelmLog.shared.recentEntries()
        HelmLog.shared.start(version: "0.0.0", override: true)
        _ = HelmLog.shared.recentEntries()
        XCTAssertTrue(logText().contains(fresh))
    }
}
