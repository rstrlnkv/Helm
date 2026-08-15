import XCTest
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What the Advice row offers as its reason.
///
/// The row asks somebody to move a gigabyte-plus file to the Trash and gave a
/// category word as its whole justification — and the word was "Untouched for
/// months", a claim about *use*. The only date behind it is `ATTR_CMN_MODTIME`
/// (`DiskScanner.readDirectory`), which is when the file was last written. A
/// 12 GB Parallels image opened every morning is written to by nobody, and a
/// film watched monthly is written to by nobody: both were listed as untouched.
///
/// Nothing a bulk directory read returns reports use, so the row says what the
/// attribute says, and says when.
final class AdviceReasonTests: XCTestCase {

    private let modified = Date(timeIntervalSince1970: 1_710_000_000)

    private func advice(_ kind: DiskAdvice.Kind, modified: Date?) -> DiskAdvice {
        DiskAdvice(name: "raw-footage.mov", path: "/Users/test/Movies/raw-footage.mov",
                   bytes: 5_000_000_000, kind: kind,
                   modified: modified?.timeIntervalSince1970)
    }

    func testTheReasonForALargeOldFileIsTheDateItWasLastWritten() {
        let line = DkStr.adviceReason(advice(.largeOld, modified: modified))
        XCTAssertTrue(line.contains(HelmDates.day(modified)),
                      "the row's reason does not carry the date it was judged by: \(line)")
    }

    /// The day, and not the minute.
    ///
    /// This advice is measured in months, so "19:00" is precision the judgement
    /// does not have and the reader has no use for — and `dayAndMinute`, which
    /// this used at first, is the format built for a report of today's activity.
    func testTheDateIsWrittenAsADayWithoutATime() {
        let line = DkStr.adviceReason(advice(.largeOld, modified: modified))
        XCTAssertFalse(line.contains(HelmDates.dayAndMinute(modified)),
                       "the reason carries a clock time: \(line)")
    }

    /// Two files judged the same way do not get the same sentence — which is
    /// the whole difference between a reason and a category word.
    func testTwoFilesOfDifferentAgesReadDifferently() {
        let older = advice(.largeOld, modified: Date(timeIntervalSince1970: 1_500_000_000))
        XCTAssertNotEqual(DkStr.adviceReason(advice(.largeOld, modified: modified)),
                          DkStr.adviceReason(older))
    }

    /// Advice restored from a scan an earlier build cached carries the verdict
    /// and no date. It still must not claim more than it knows.
    func testWithNoDateItFallsBackToTheClaimTheDataSupports() {
        XCTAssertEqual(DkStr.adviceReason(advice(.largeOld, modified: nil)),
                       DkStr.notModifiedInMonths)
    }

    /// A cache is a folder, and a folder's own mtime says when something was
    /// last added to it and nothing about what is inside — so this row has no
    /// date to offer and says what it is instead.
    func testACacheKeepsItsOwnReason() {
        XCTAssertEqual(DkStr.adviceReason(advice(.cache, modified: nil)),
                       DkStr.adviceKindCache)
    }

    /// **And an old download carries a date it was not showing.**
    ///
    /// `DiskAdvisor` builds this advice with `modified:` — the threshold *is* a
    /// date, thirty days — and the row answered «Old download», a category word,
    /// over a request to bin an 8 GB installer. The evidence was already in the
    /// payload and the sentence for it already in the table.
    func testAnOldDownloadOffersTheDateItWasJudgedBy() {
        let line = DkStr.adviceReason(advice(.oldDownload, modified: modified))
        XCTAssertTrue(line.contains(HelmDates.day(modified)),
                      "the row's whole evidence is a category word: \(line)")
    }

    /// Advice cached by a build that did not carry the date falls back to the
    /// category word rather than claiming a day it does not know.
    func testAnOldDownloadWithNoDateFallsBackToItsCategory() {
        XCTAssertEqual(DkStr.adviceReason(advice(.oldDownload, modified: nil)),
                       DkStr.adviceKindOldDownload)
    }
}
