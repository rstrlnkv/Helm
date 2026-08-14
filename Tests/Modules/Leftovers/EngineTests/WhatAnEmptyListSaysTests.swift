import XCTest
import Module_Leftovers_Engine

/// **A scan that found things and no leftovers has something to say.**
///
/// The page branched its empty state on «the scan found nothing» while the list
/// was built from what the filters leave — and those are different questions on
/// almost every Mac, because `LeftoversScanner.preferences` returns every plist in
/// `~/Library/Preferences` and nearly all of them are `.inUse`. So the ordinary
/// first scan drew «Found: 542 items», the sentence about nothing being ticked,
/// and 515 pt of nothing under it.
///
/// Three answers rather than two, because «nothing is left over» and «everything
/// found is hidden by the filter you set» are different facts and only one of them
/// is news the person can act on — the filter menu is on screen above it.
final class WhatAnEmptyListSaysTests: XCTestCase {

    func testBeforeTheFirstScanThePageInvites() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: false, visible: 0, hiddenByKind: 0, unchecked: 0),
                       .notScanned)
    }

    /// And it goes on inviting even if a previous session's counts are lying
    /// around: nothing has been asked of the machine yet.
    func testAnUnscannedPageInvitesWhateverTheCountsSay() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: false, visible: 4, hiddenByKind: 2, unchecked: 0),
                       .notScanned)
    }

    func testARowToDrawIsNotAnEmptyList() {
        XCTAssertNil(LeftoversEmpty.reason(scanned: true, visible: 3, hiddenByKind: 9, unchecked: 0))
    }

    func testAScanWithNothingLeftOverSaysSo() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: true, visible: 0, hiddenByKind: 0, unchecked: 0),
                       .nothingFound)
    }

    /// The distinction the page could not make: rows exist, the kind filter is
    /// hiding all of them, and «No leftovers found» would be a claim about the
    /// Mac where the truth is a claim about a menu.
    func testRowsHiddenByTheFilterSayThatInstead() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: true, visible: 0, hiddenByKind: 7, unchecked: 0),
                       .hiddenByFilter)
    }
}
