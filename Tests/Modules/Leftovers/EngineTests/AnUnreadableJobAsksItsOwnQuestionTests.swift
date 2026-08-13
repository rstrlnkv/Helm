import Foundation
import XCTest
@testable import Module_Leftovers_Engine

/// A row Helm could not read is still a row somebody may delete on purpose — and
/// the question asked first has to be about what is true of it.
///
/// `APlistNobodyCouldReadTests` is the finding: an unreadable launchd job was
/// swept up by «Select all». Keeping it out of the batch leaves the row's own
/// menu, which asks before deleting anything that is not a leftover — and the one
/// question this module had says «It is loaded now, and the app that installed it
/// may put it back», which is a claim about a file whose contents Helm never got
/// to see. So «why we are asking» is a value the strings switch over, the shape
/// `NoDelete` already uses for «why there is no delete button».
final class AnUnreadableJobAsksItsOwnQuestionTests: XCTestCase {

    private func item(_ status: ItemStatus) -> StaleItem {
        StaleItem(path: "/Users/x/Library/LaunchAgents/com.vendor.updater.plist",
                  identifier: "com.vendor.updater", kind: .launchAgent, sizeBytes: 100,
                  status: status)
    }

    /// Clearing a leftover is tidying: no dialog, and the row says «Move to
    /// Trash» rather than promising a step that never comes.
    func testALeftoverIsNotAskedAbout() {
        XCTAssertNil(LeftoverActions.askBeforeDeleting(item(.orphaned)))
        XCTAssertFalse(LeftoverActions.needsConfirmation(item(.orphaned)),
                       "the two answers are one answer, or they will part")
    }

    /// Something the Mac is loading now: the question this module already had.
    func testSomethingInUseIsAskedAboutBeingLoaded() {
        XCTAssertEqual(LeftoverActions.askBeforeDeleting(item(.inUse)), .loadedNow)
        XCTAssertTrue(LeftoverActions.needsConfirmation(item(.inUse)))
    }

    /// And a job whose definition could not be read is asked about *that*, not
    /// about being loaded — the fact Helm has is that it could not read the file.
    func testAnUnreadableJobIsAskedAboutBeingUnreadable() {
        XCTAssertEqual(LeftoverActions.askBeforeDeleting(item(.unreadable)), .cannotBeRead)
        XCTAssertTrue(LeftoverActions.needsConfirmation(item(.unreadable)),
                      "deleting a file nobody could read is a decision, not tidying")
    }

    /// The bulk tick is the offer being withheld, and the row's own delete is not
    /// — a row nobody can read is worth showing, and worth being able to clear
    /// deliberately.
    func testTheRowKeepsItsOwnDeleteWhileTheBatchDoesNot() {
        XCTAssertFalse(item(.unreadable).removable,
                       "«Select all» ticks a job whose plist could not be read")
        XCTAssertTrue(LeftoverActions.available(for: item(.unreadable)).contains(.delete),
                      "and the row's own menu lost the way to clear it")
    }

    /// **And it does not offer the switch, because the label is a guess.**
    /// `LaunchAgentReader` falls back to the file name when `Label` cannot be
    /// read, which is right for a job that *omits* the key — launchd does the same
    /// — and is an invention for a file whose contents never came. Sending that
    /// guess to `launchctl disable` writes an entry under a name that may be no
    /// job at all, and the row then reads it back and wears «Disabled»: the badge
    /// this module offers as reassurance that a login item will not run, over a
    /// job nobody switched off. The same implication `ASwitchTheSystemWillRefuse`
    /// asserts about a label launchd would refuse, for a label Helm made up.
    func testAnUnreadableJobIsNotOfferedTheSwitchEither() {
        XCTAssertFalse(item(.unreadable).canToggle)
        XCTAssertTrue(item(.inUse).canToggle,
                      "precondition: an agent Helm did read still offers it")
    }
}
