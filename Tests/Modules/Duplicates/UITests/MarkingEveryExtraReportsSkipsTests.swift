import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// «Mark every extra copy» passes over what the engine would refuse, and used to
/// do it in silence.
///
/// The button's whole point is that one press stands for a page of decisions, so
/// the count under it is what the person acts on: pressing it on twenty groups
/// and getting eighteen ticks is a difference nobody can see, and the two copies
/// it stepped over are the ones they would most want to know about — a duplicate
/// sitting somewhere Helm may not touch stays there for ever, unmentioned.
@MainActor
final class MarkingEveryExtraReportsSkipsTests: XCTestCase {

    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(bytes: 2_000_000, paths: paths)
    }

    private func searched(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
        let dvm = await searchedModel(groups)
        return dvm
    }

    /// The system path is an extra copy the engine's scope gate refuses, which is
    /// the same rule `UserFileScope` applies here — so the button leaves it and
    /// says how many it left.
    func testWhatCannotBeRemovedIsCounted() async {
        let dvm = await searched([group(["\(home)/Downloads/a1",
                                         "/System/Library/CoreServices/a2"])])

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.basket, [], "the fixture's extra was marked after all")
        XCTAssertEqual(dvm.marksNote, DupStr.skippedNotRemovable(1))
    }

    /// Over the whole page, not per group: one press, one report.
    func testTheCountIsOfCopiesAcrossEveryGroup() async {
        let dvm = await searched([
            group(["\(home)/Downloads/a1", "/System/Library/CoreServices/a2"]),
            group(["\(home)/Downloads/b1", "/usr/lib/b2"]),
        ])

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.marksNote, DupStr.skippedNotRemovable(2))
    }

    func testAPressThatSkippedNothingSaysNothing() async {
        let dvm = await searched([group(["\(home)/Downloads/a1", "\(home)/Downloads/a2"])])

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.basket, ["\(home)/Downloads/a2"],
                       "nothing was marked, so the silence below is about the wrong thing")
        XCTAssertNil(dvm.marksNote)
    }

    /// The per-group button skips in the same silence and gets the same line —
    /// it is the same rule applied to one section.
    func testTheGroupButtonReportsToo() async {
        let dvm = await searched([group(["\(home)/Downloads/a1",
                                         "/System/Library/CoreServices/a2"])])

        dvm.basketExtras(of: dvm.groups[0])

        XCTAssertEqual(dvm.marksNote, DupStr.skippedNotRemovable(1))
    }

    /// A copy already ticked is not a copy that was skipped. The button is
    /// pressed twice on the same page more often than not.
    func testMarkingTwiceDoesNotReportTheMarksItAlreadyMade() async {
        let dvm = await searched([group(["\(home)/Downloads/a1", "\(home)/Downloads/a2"])])
        dvm.basketAllExtras()

        dvm.basketAllExtras()

        XCTAssertNil(dvm.marksNote)
    }
}
