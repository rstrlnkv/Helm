import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The bar under the list, the confirmation that quotes it, and the toolbar's
/// total are one promise about free space, and a clone gives none of it back.
///
/// `DuplicateGroup.wasted` has been clone-aware since the copies started
/// carrying their family; `basketBytes` summed `Copy.bytes` and never looked at
/// `cloneFamily` at all, so one screen said 300 MB in the toolbar and 321 MB in
/// the bar about the same two files — and the confirmation dialog and the banner
/// both inherited the larger, wrong one.
///
/// The fixtures below give a clone its **whole** allocated size, which is what
/// APFS reports for one: the older fixtures in this target plant `bytes: 0` for
/// a clone, a state no volume can produce, and no arithmetic that folds a family
/// can be seen through it.
@MainActor
final class TheBasketPromisesWhatTheDiskGivesTests: XCTestCase {

    private var original: String { "\(home)/Downloads/orig.bin" }
    private var clone: String { "\(home)/Downloads/clone.bin" }
    private var copy: String { "\(home)/Downloads/copy.bin" }

    /// One group: a survivor, a clone of it, and a real copy — all three
    /// reporting 20 MB, because that is what the filesystem reports for all
    /// three.
    private func model() async -> DuplicatesViewModel {
        await searchedModel([DuplicateGroup(copies: [
            .init(path: original, bytes: 20_971_520, cloneFamily: 77),
            .init(path: clone, bytes: 20_971_520, cloneFamily: 77),
            .init(path: copy, bytes: 20_971_520, cloneFamily: 99),
        ])])
    }

    /// Marking the clone of a copy that stays promises nothing, because nothing
    /// is what the disk gives back.
    func testACloneOfTheCopyThatStaysPromisesNothing() async {
        let dvm = await model()
        XCTAssertEqual(dvm.groups.count, 1, "the fixture never reached the view model")

        dvm.toggleBasket(clone)

        XCTAssertEqual(dvm.basket, [clone], "precondition: the clone really is marked")
        XCTAssertEqual(dvm.basketBytes, 0,
                       "the bar promised the clone's blocks, which the survivor keeps")
    }

    /// And marking both extras promises the real copy alone — the figure the
    /// group's own `wasted` has been answering all along.
    func testMarkingEveryExtraPromisesExactlyWhatTheGroupCallsWasted() async {
        let dvm = await model()

        dvm.basketAllExtras()

        XCTAssertEqual(Set(dvm.basket), [clone, copy], "precondition: both extras are marked")
        XCTAssertEqual(dvm.basketBytes, 20_971_520)
        XCTAssertEqual(dvm.basketBytes, dvm.wastedBytes,
                       "the bar and the toolbar disagree about one press on one screen")
    }

    /// A copy that shares its blocks with nothing is still its own size: the
    /// fold must not swallow the ordinary case.
    func testARealCopyIsStillCountedInFull() async {
        let dvm = await model()

        dvm.toggleBasket(copy)

        XCTAssertEqual(dvm.basketBytes, 20_971_520)
    }

    /// **What stays is every copy that is not ticked, not merely the survivor.**
    /// The rule's doc says so and nothing held it to it: an extra the person left
    /// unticked holds its family's blocks exactly as the survivor does, so its
    /// twin going frees nothing — and reading only the survivor's family, which
    /// is the shape that looks right, promises the whole file.
    func testAnUntickedExtraKeepsItsFamilysBlocksJustAsTheSurvivorWould() async {
        let ticked = "\(home)/Downloads/ticked.bin"
        let left = "\(home)/Downloads/left-alone.bin"
        let dvm = await searchedModel([DuplicateGroup(copies: [
            .init(path: original, bytes: 20_971_520, cloneFamily: 1),
            .init(path: ticked, bytes: 20_971_520, cloneFamily: 7),
            .init(path: left, bytes: 20_971_520, cloneFamily: 7),
        ])])

        dvm.toggleBasket(ticked)

        XCTAssertEqual(dvm.basket, [ticked], "precondition: only one of the pair is marked")
        XCTAssertEqual(dvm.basketBytes, 0,
                       "the copy left on screen goes on holding those blocks")
    }

    /// **One family across two groups is one lot of blocks.** The rule's own doc
    /// says it folds over every group at once and not group by group; nothing
    /// held it to that, and summing each group's `wasted` — which is what the
    /// toolbar did — charges such a family twice.
    ///
    /// A clone written to after it was made is the state: its content diverges,
    /// so the two land in different groups, and its blocks are still shared with
    /// what it was cloned from until the last member of the family goes.
    func testAFamilyThatSpansTwoGroupsIsCountedOnceAcrossThePress() async {
        let firstExtra = "\(home)/Downloads/one-extra.bin"
        let secondExtra = "\(home)/Downloads/two-extra.bin"
        let dvm = await searchedModel([
            DuplicateGroup(copies: [.init(path: "\(home)/Downloads/one.bin", bytes: 8_000_000),
                                    .init(path: firstExtra, bytes: 8_000_000, cloneFamily: 42)]),
            DuplicateGroup(copies: [.init(path: "\(home)/Downloads/two.bin", bytes: 8_000_000),
                                    .init(path: secondExtra, bytes: 8_000_000, cloneFamily: 42)]),
        ])
        XCTAssertEqual(dvm.groups.count, 2, "precondition: two groups reached the view model")

        dvm.basketAllExtras()

        XCTAssertEqual(Set(dvm.basket), [firstExtra, secondExtra],
                       "precondition: one extra from each group is marked")
        XCTAssertEqual(dvm.basketBytes, 8_000_000,
                       "the family's blocks were promised once per group that holds a member")
        XCTAssertEqual(dvm.wastedBytes, dvm.basketBytes,
                       "the toolbar and the bar disagree about the same two files")
        XCTAssertEqual(dvm.groups.reduce(0) { $0 + $1.wasted }, 16_000_000,
                       "precondition: group by group really is the other answer, or this "
                       + "fixture cannot tell the two arithmetics apart")
    }

    /// Two clones of one family, both marked, with the survivor outside the
    /// basket: still nothing. Counting the family once would answer 20 MB, which
    /// is the other half of the same lie.
    func testTwoClonesOfOneFamilyPromiseNothingWhileTheirSurvivorStays() async {
        let second = "\(home)/Downloads/clone-2.bin"
        let dvm = await searchedModel([DuplicateGroup(copies: [
            .init(path: original, bytes: 20_971_520, cloneFamily: 77),
            .init(path: clone, bytes: 20_971_520, cloneFamily: 77),
            .init(path: second, bytes: 20_971_520, cloneFamily: 77),
        ])])

        dvm.basketAllExtras()

        XCTAssertEqual(Set(dvm.basket), [clone, second], "precondition: both extras are marked")
        XCTAssertEqual(dvm.basketBytes, 0)
    }
}
