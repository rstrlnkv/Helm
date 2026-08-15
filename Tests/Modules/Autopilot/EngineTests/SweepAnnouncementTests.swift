import XCTest
@testable import Module_Autopilot_Engine

/// One condition decides which sweep speaks, held in one place so the two
/// triggers cannot drift: the hourly sentinel stays silent over a folder where
/// nothing happened — 24 lines a day about nothing drown the trail — and a
/// person's Run now is always answered, because a button that leaves no line
/// cannot be told apart from a button that did not run.
final class SweepAnnouncementTests: XCTestCase {

    private func report(acted: Int = 0, refused: Int = 0, failed: Int = 0,
                        examined: Int = 0) -> SweepReport {
        SweepReport(folderID: "f", examined: examined,
                    acted: acted, refused: refused, failed: failed)
    }

    // MARK: - Run now: a command is always answered

    func testAManualRunOverANolentFolderStillSpeaks() throws {
        let line = try XCTUnwrap(SweepAnnouncement.line(for: report(), manual: true),
                                 "the person pressed a button and the log says nothing, so "
                                 + "«went clean» and «never ran» are the same silence")
        XCTAssertTrue(line.contains("swept 0"), "the line does not carry the counts: \(line)")
    }

    /// The trigger is in the sentence: an hourly line and a pressed one land in
    /// the same log, and a person triaging it is owed which was which.
    func testAManualLineNamesItsTrigger() throws {
        let line = try XCTUnwrap(SweepAnnouncement.line(for: report(acted: 2, examined: 5),
                                                        manual: true))
        XCTAssertTrue(line.contains("run now"), "nothing says a person asked for this: \(line)")
    }

    // MARK: - The hourly sentinel: conditional, as it always was

    func testAnHourlySweepThatDidNothingSaysNothing() {
        XCTAssertNil(SweepAnnouncement.line(for: report(examined: 12), manual: false),
                     "the sentinel now writes a line per idle hour, which is the noise "
                     + "the condition existed to keep out")
    }

    func testAnHourlySweepThatActedKeepsItsLine() throws {
        let line = try XCTUnwrap(SweepAnnouncement.line(for: report(acted: 3, refused: 1,
                                                                    failed: 1, examined: 7),
                                                        manual: false))
        // The exact wording the log has always carried, so nothing greps differently.
        XCTAssertEqual(line, "swept 7, acted 3, refused 1, failed 1")
    }

    /// A refusal or a failure is work worth a line even when nothing moved —
    /// the condition is over all three counts, not over `acted` alone.
    func testARefusalAloneIsWorthAnHourlyLine() {
        XCTAssertNotNil(SweepAnnouncement.line(for: report(refused: 1, examined: 3),
                                               manual: false))
        XCTAssertNotNil(SweepAnnouncement.line(for: report(failed: 1, examined: 3),
                                               manual: false))
    }
}
