import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// «Found 3 groups — 21 GB could be freed» is the one clone-corrected figure on
/// the page, and it counts copies the module refuses to remove.
///
/// `wastedBytes` marks **every** extra in every group; `basketAllExtras` marks
/// only the extras `UserFileScope` allows, and reports the rest as skipped
/// (`MarkingEveryExtraReportsSkipsTests`). So the two disagree by exactly the
/// copies Helm will never touch — while `wastedBytes`' own doc comment states
/// the opposite as its reason for existing: "every extra copy in every group,
/// through the fold `basketBytes` uses, so pressing «Mark every extra copy»
/// makes the bar say what the toolbar above it already said."
///
/// The figure went to some trouble to be honest. It was a toolbar item behind a
/// measured 1040 pt threshold — "the only honest figure was drawn at no width
/// the app opens at" — and was moved under the floor note so it is drawn at
/// every width. What it is honest about is clones, and this is the other half:
/// a total is not what the disk would give back if it names space the module
/// will refuse to reclaim.
///
/// **Reachable, not exotic.** Point the search at `/`, at `/Library` or at
/// `/opt` — where a Homebrew Cellar holds real duplicates — and the walk turns
/// up copies under paths `UserFileScope.protectedPrefixes` refuses. Every one of
/// them is added to the sentence and to no basket.
@MainActor
final class TheTotalPromisesWhatHelmWillTakeTests: XCTestCase {

    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(bytes: 2_000_000, paths: paths)
    }

    /// The control, and it has to pass: with every extra inside the user's own
    /// files the two figures already agree, so a failure below is about the
    /// refused copy and not about the fold.
    func testWithNothingRefusedTheTotalIsWhatTheMarksPromise() async {
        let dvm = await searchedModel([group(["\(home)/Downloads/a1",
                                              "\(home)/Downloads/a2"])])

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.basket.count, 1, "precondition: the extra really was marked")
        XCTAssertEqual(dvm.basketBytes, dvm.wastedBytes)
        XCTAssertGreaterThan(dvm.wastedBytes, 0, "a total of zero agrees with everything")
    }

    /// And the same press over an extra the engine's own gate refuses: the bar
    /// says nothing will be freed, and the line above the list goes on promising
    /// the whole copy.
    func testACopyTheEngineWillRefuseIsNotSpaceTheTotalMayPromise() async {
        let dvm = await searchedModel([group(["\(home)/Downloads/a1",
                                              "/System/Library/CoreServices/a2"])])
        XCTAssertGreaterThan(dvm.wastedBytes, 0, "precondition: the line has something to say")

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.marksNote, DupStr.skippedNotRemovable(1),
                       "precondition: the extra really was passed over, so this is that copy")
        XCTAssertEqual(dvm.basketBytes, dvm.wastedBytes, """
            «Mark every extra copy» ticked nothing and the bar promises \(dvm.basketBytes), while \
            the total under the floor note still offers \(dvm.wastedBytes) of space Helm refuses \
            to reclaim — the one clone-corrected figure on the page, counting a copy no press on \
            it can ever remove
            """)
    }

    /// Over the whole page, the way the sentence is: one refused copy among
    /// several groups still leaves the two figures apart, so this is not a
    /// property of a page with exactly one group on it.
    func testTheGapSurvivesAPageOfGroups() async {
        let dvm = await searchedModel([
            group(["\(home)/Downloads/a1", "\(home)/Downloads/a2"]),
            group(["\(home)/Downloads/b1", "/usr/lib/b2"]),
        ])

        dvm.basketAllExtras()

        XCTAssertEqual(dvm.basket, ["\(home)/Downloads/a2"],
                       "precondition: one extra marked, one refused")
        XCTAssertEqual(dvm.basketBytes, dvm.wastedBytes,
                       "the total is a group ahead of everything the page can act on")
    }
}
