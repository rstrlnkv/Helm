import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// The batch read against itself: a plan may not take a copy another plan in
/// the same batch is keeping.
///
/// `TheCopyThatStaysIsNeverAlsoTakenTests` drives the whole engine over two real
/// files and asks what the batch allowed. This asks the rule itself the two
/// questions that test cannot: a plan whose own survivor is the file it removes
/// — which no pair check can catch, since `DuplicateVerification.verify` finds a
/// file identical to itself — and whether the answer is the same twice, because
/// which copy of the content survives must not be decided by the order a
/// dictionary happened to hash its keys in.
final class KeptCopiesTests: XCTestCase {

    private func plan(_ remove: String, _ keep: String) -> DuplicatePlan {
        DuplicatePlan(remove: remove, keep: keep)
    }

    /// The control, and it has to pass: an ordinary batch — every survivor
    /// outside the removal set — goes through whole. A rule that refused
    /// anything here would take the module's own screen away.
    func testAnOrdinaryBatchIsHonouredWhole() {
        let plans = [plan("/a/2", "/a/1"), plan("/a/3", "/a/1"), plan("/b/2", "/b/1")]

        let verdict = KeptCopies.partition(plans)

        XCTAssertEqual(verdict.honoured, plans)
        XCTAssertTrue(verdict.contradicted.isEmpty)
    }

    /// Each copy named as the other's survivor: one may go, and the other is the
    /// content.
    func testEachCopyNamedAsTheOthersSurvivorLeavesOneStanding() {
        let verdict = KeptCopies.partition([plan("/a/1", "/a/2"), plan("/a/2", "/a/1")])

        XCTAssertEqual(verdict.honoured, [plan("/a/1", "/a/2")])
        XCTAssertEqual(verdict.contradicted, ["/a/2"])
    }

    /// A ring of three is the same shape one turn longer, and it closes the same
    /// way: whatever else is refused, something holding the content stays.
    func testARingOfThreeStillLeavesACopyOfTheContent() {
        let verdict = KeptCopies.partition([plan("/a/1", "/a/2"),
                                            plan("/a/2", "/a/3"),
                                            plan("/a/3", "/a/1")])

        let going = Set(verdict.honoured.map(\.remove))
        XCTAssertFalse(Set(["/a/1", "/a/2", "/a/3"]).subtracting(going).isEmpty)
        XCTAssertEqual(going.count + verdict.contradicted.count, 3,
                       "a plan that is neither honoured nor refused is a refusal discarded")
    }

    /// The same promise broken from the other end: this plan's survivor is a
    /// copy an earlier plan is taking. Nothing about `/a/3` is wrong — it is the
    /// file it is measured against that will not be there.
    func testAPlanMeasuredAgainstACopyThatIsItselfGoingIsRefused() {
        let verdict = KeptCopies.partition([plan("/a/1", "/a/2"), plan("/a/3", "/a/1")])

        XCTAssertEqual(verdict.honoured, [plan("/a/1", "/a/2")])
        XCTAssertEqual(verdict.contradicted, ["/a/3"], """
            the batch kept a promise it had already broken: `/a/3` goes because `/a/1` stays, \
            and `/a/1` is in the same batch on its way to the Trash
            """)
    }

    /// The plan that keeps the very file it removes. No pair check can refuse
    /// it — `DuplicateVerification.verify(remove: p, keep: p)` reads one file
    /// twice and calls it identical, which it is — so the only place it can be
    /// stopped is here.
    func testAPlanThatKeepsTheCopyItRemovesIsRefused() {
        let verdict = KeptCopies.partition([plan("/a/1", "/a/1")])

        XCTAssertTrue(verdict.honoured.isEmpty,
                      "the batch promised to keep the file it was about to take")
        XCTAssertEqual(verdict.contradicted, ["/a/1"])
    }

    /// And which copy survives is decided by the batch's own order, not by the
    /// order a `Set` or a `Dictionary` handed the paths over in: the same
    /// contradiction must not delete `/a/1` on one run and `/a/2` on the next.
    func testTheSameBatchDecidesTheSameWayEveryTime() {
        let plans = [plan("/a/2", "/a/1"), plan("/a/1", "/a/2")]

        let answers = (0..<20).map { _ in KeptCopies.partition(plans).honoured }

        XCTAssertEqual(Set(answers.map { $0.map(\.remove) }), [["/a/2"]],
                       "the copy that goes changed between runs of the same batch")
    }
}
