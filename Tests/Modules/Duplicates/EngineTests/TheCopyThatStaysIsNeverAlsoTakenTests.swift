import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The engine has the last word on deletion, and one thing it never checks is
/// that a copy another plan is keeping is not itself being taken.
///
/// **What the gates it does run cannot see.** `UserFileScope.partition` asks
/// whether a path belongs to the user; `DuplicateVerification` asks whether one
/// pair is still what the scan said it was. Both answer about a path or a pair,
/// and both say yes to each half of `[a→keep b, b→keep a]` — two pairs that are
/// each perfectly valid and together take every copy of the content. There is
/// nowhere in the reply for the outcome either: `removed` lists both, `refused`
/// is empty, and the banner reports a clean removal.
///
/// **Why an engine-side check, when the page cannot build such a plan today.**
/// `emptyBasket` pairs each marked copy with `group.copies.first` and never
/// sends the survivor, so the plan list is well formed — which is exactly the
/// argument `RemovableScope` was written to refuse: "those gates live in view
/// models, and a view model is the wrong place for the last word: the engine
/// takes a list … and trashes them, so any defect upstream that produces a bad
/// string produces a deleted folder." This module's own doc says the same in
/// its own words: the bare-paths entrance was removed because "a caller sending
/// bare paths gets nothing removed rather than something removed unchecked".
/// A plan list whose survivors are in its own removal set is the one remaining
/// shape of "removed unchecked", and it is the shape whose cost is the content
/// itself.
///
/// Nothing moves here: the engine's `trashing` port is replaced, so the
/// assertion is about what the batch **allowed**, which is the decision under
/// test and is taken before any file would move.
final class TheCopyThatStaysIsNeverAlsoTakenTests: XCTestCase {

    private var root: URL!
    private var first: String!
    private var second: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // `$TMPDIR` is on the data volume, so `UserFileScope` lets the batch
        // through and the outcome below is not some other refusal wearing this
        // one's clothes.
        root = scratchDirectory("both-copies")
        first = try write("first.bin", in: root, bytes: 2_000_000, filler: 3).path
        second = try write("second.bin", in: root, bytes: 2_000_000, filler: 3).path
    }

    /// The precondition the finding rests on: these are two separate files with
    /// the same contents, so each pair really is a valid duplicate pair and the
    /// verification has no reason of its own to refuse either.
    func testTheTwoCopiesAreARealDuplicatePair() throws {
        let attributes = FileManager.default
        let a = try XCTUnwrap(attributes.attributesOfItem(atPath: first)[.systemFileNumber]
                                as? UInt64)
        let b = try XCTUnwrap(attributes.attributesOfItem(atPath: second)[.systemFileNumber]
                                as? UInt64)
        XCTAssertNotEqual(a, b, "the fixture is one file under two names, not two copies")
        XCTAssertEqual(DuplicateVerification.verify(remove: first, keep: second), .identical)
    }

    /// A plan list that names each copy as the other's survivor takes them both,
    /// and the content stops existing anywhere.
    func testABatchThatNamesEachCopyAsTheOthersSurvivorKeepsOneOfThem() async {
        let result = await DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
            .trash([DuplicatePlan(remove: first, keep: second),
                    DuplicatePlan(remove: second, keep: first)])

        let kept = Set([first!, second!]).subtracting(result.removed)
        XCTAssertFalse(kept.isEmpty, """
            every copy of the content was allowed through: the engine verified each pair on its \
            own and nothing asked whether a path it was about to take is a path another plan in \
            the same batch is keeping. \(result.refused.count) refusals, \
            \(result.removed.count) removals
            """)
    }

    /// And the refusal is a refusal, not a silent shortening — the house rule
    /// this module answers to. Whichever copy the engine decides to keep, the
    /// plan that named it has to come back with a reason beside it.
    func testTheCopyThatIsKeptComesBackAsARefusalRatherThanBeingDropped() async {
        let result = await DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
            .trash([DuplicatePlan(remove: first, keep: second),
                    DuplicatePlan(remove: second, keep: first)])

        XCTAssertEqual(result.removed.count + result.refused.count, 2, """
            the batch answered about \(result.removed.count + result.refused.count) of its two \
            plans — a plan that is neither removed nor refused is a refusal silently discarded
            """)
        XCTAssertEqual(result.removed.count, 1,
                       "exactly one of the two copies may go, and the other is the content")
    }
}
