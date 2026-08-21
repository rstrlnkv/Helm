import XCTest
@testable import Module_Autopilot_Engine

/// The one thing this app does unattended that it cannot take back.
///
/// Autopilot trashes files on an hourly sweep, and the entire account of it was
/// a line in a log file — while the banner port was spent on the two modules
/// that touch no files at all. This is the rule that decides which pass is worth
/// a banner, and every silence below is the reason it is not one a person turns
/// off after a day.
final class AnHourlySweepThatTrashedSomethingSaysSoTests: XCTestCase {

    private func record(_ kind: ActionRecord.Kind) -> ActionRecord {
        ActionRecord(at: Date(), rule: "a rule", file: "a.pdf", kind: kind,
                     detail: "", path: "/Users/tester/Downloads/a.pdf", destination: "")
    }

    // MARK: - What stays silent

    /// **A move it can undo and has recorded in History is not news.** That is
    /// the whole of what the sentinel does on an ordinary day, and a banner for
    /// it makes an hourly sweep an hourly banner — which is a channel nobody
    /// keeps switched on long enough to be told the one thing that matters.
    func testAPassThatOnlyTidiedIsSilent() {
        let tidy = [record(.moved), record(.renamed), record(.tagged)]
        XCTAssertNil(SweepNews.worthTelling(tidy))
    }

    /// The ordinary hour: nothing matched, nothing happened.
    func testAPassThatDidNothingIsSilent() {
        XCTAssertNil(SweepNews.worthTelling([]))
    }

    // MARK: - What speaks

    /// The Trash is the one act with nowhere to put the file back from by
    /// itself, and the reason this channel exists.
    func testAPassThatTrashedSomethingSpeaks() {
        let told = SweepNews.worthTelling([record(.moved), record(.trashed)])
        XCTAssertEqual(told?.trashed, 1)
        XCTAssertEqual(told?.refused, 0)
        XCTAssertEqual(told?.failed, 0)
    }

    /// A refusal is the gate holding, and the person is owed it: a rule they
    /// wrote is not running and every screen looks well.
    func testAPassThatRefusedSpeaks() {
        let told = SweepNews.worthTelling([record(.refused)])
        XCTAssertEqual(told?.refused, 1)
        XCTAssertEqual(told?.trashed, 0)
    }

    /// And a failure is the filesystem saying no, which is not the same fact
    /// and is not one to fold into the other.
    func testAPassThatFailedSpeaks() {
        let told = SweepNews.worthTelling([record(.failed)])
        XCTAssertEqual(told?.failed, 1)
        XCTAssertEqual(told?.refused, 0)
    }

    /// The counts are the pass's own, over every kind at once — one banner for
    /// the pass, never one per file.
    func testTheCountsAreThePassesOwn() {
        let mixed = [record(.trashed), record(.trashed), record(.moved),
                     record(.refused), record(.failed), record(.failed), record(.failed)]
        let told = SweepNews.worthTelling(mixed)
        XCTAssertEqual(told?.trashed, 2)
        XCTAssertEqual(told?.refused, 1)
        XCTAssertEqual(told?.failed, 3)
    }

    /// The tally is answered for every pass, whether or not it is worth saying:
    /// it is what the two legs of the engine add together, and a rule that
    /// returned nothing for a quiet folder could not be summed.
    func testAQuietPassStillTalliesToNothing() {
        let quiet = SweepNews.tally(of: [record(.moved)])
        XCTAssertEqual(quiet, SweepNews.Tally(trashed: 0, refused: 0, failed: 0))
        XCTAssertFalse(quiet.isSomething)
    }

    /// Two folders swept in one pass are one banner, so the tallies add.
    func testTalliesFromTwoFoldersAddIntoOne() {
        let first = SweepNews.tally(of: [record(.trashed), record(.refused)])
        let second = SweepNews.tally(of: [record(.trashed), record(.failed)])
        XCTAssertEqual(first + second, SweepNews.Tally(trashed: 2, refused: 1, failed: 1))
    }
}
