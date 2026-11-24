import XCTest
@testable import Module_Uninstaller_Engine

private func leftover(_ path: String, _ bytes: Int = 10,
                      byName: Bool = false) -> Leftover {
    Leftover(path: path, kind: .appSupport, sizeBytes: bytes, matchedByName: byName)
}

private func group(_ id: String, _ leftovers: [Leftover]) -> TrashedAppLeftovers {
    TrashedAppLeftovers(bundleID: id, name: "App",
                        appPath: "/Users/ann/.Trash/App.app", leftovers: leftovers)
}

/// What the unprompted window may act on.
///
/// Nobody asked for this window, and what it arrives with ticked is what one
/// press removes, so the ticks have to be defensible unread.
final class TrashOfferPlanTests: XCTestCase {
    // MARK: - What arrives ticked

    func testALeftoverFoundByBundleIDArrivesTicked() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a")])]
        XCTAssertEqual(TrashOfferPlan.defaultSelection(groups),
                       ["/Users/ann/Library/Caches/com.a"])
    }

    /// The review screen's default, and it matters more here, where the window
    /// arrived on its own: `Application Support/Mail` is a guess about a name.
    func testALeftoverFoundByNameArrivesUnticked() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Logs/Mail", byName: true)])]
        XCTAssertTrue(TrashOfferPlan.defaultSelection(groups).isEmpty,
                      "a name guess arrived ticked next to a button that removes it")
    }

    func testTheGuessIsLeftOutAndTheRestIsKept() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a"),
                                      leftover("/Users/ann/Library/Logs/App", byName: true)])]
        XCTAssertEqual(TrashOfferPlan.defaultSelection(groups),
                       ["/Users/ann/Library/Caches/com.a"])
    }

    /// Two apps in the Trash can name the same file (a shared group container):
    /// ticked, listed and counted once.
    func testAPathTwoAppsShareIsTickedOnce() {
        let shared = "/Users/ann/Library/Group Containers/group.a"
        let groups = [group("com.a", [leftover(shared)]), group("com.b", [leftover(shared)])]
        XCTAssertEqual(TrashOfferPlan.defaultSelection(groups), [shared])
    }

    // MARK: - What one press sends

    func testOnlyTickedPathsAreSent() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a"),
                                      leftover("/Users/ann/Library/Logs/App")])]
        XCTAssertEqual(TrashOfferPlan.paths(groups, selected: ["/Users/ann/Library/Logs/App"]),
                       ["/Users/ann/Library/Logs/App"])
    }

    /// The app is already where the person put it, and Helm does not touch it.
    /// Nothing offers the bundle, so this guards a selection that holds it
    /// anyway: the ticks are strings, and this is the last place that can tell.
    func testTheAppInTheTrashIsNeverSent() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a")])]
        let paths = TrashOfferPlan.paths(groups, selected: ["/Users/ann/Library/Caches/com.a",
                                                            "/Users/ann/.Trash/App.app"])
        XCTAssertEqual(paths, ["/Users/ann/Library/Caches/com.a"],
                       "the window sent the app bundle sitting in the Trash")
    }

    /// A tick for something the window never listed is not a licence to remove
    /// it — the paths that go out are the ones the person was shown.
    func testAPathThatWasNeverListedIsNotSent() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a")])]
        XCTAssertTrue(TrashOfferPlan.paths(groups, selected: ["/Users/ann/Documents/thesis"]).isEmpty)
    }

    func testASharedPathIsSentOnce() {
        let shared = "/Users/ann/Library/Group Containers/group.a"
        let groups = [group("com.a", [leftover(shared)]), group("com.b", [leftover(shared)])]
        XCTAssertEqual(TrashOfferPlan.paths(groups, selected: [shared]), [shared])
    }

    func testGroupOrderIsKept() {
        let groups = [group("com.a", [leftover("/1")]), group("com.b", [leftover("/2")])]
        XCTAssertEqual(TrashOfferPlan.paths(groups, selected: ["/1", "/2"]), ["/1", "/2"])
    }

    // MARK: - A second app arrives while the window is open

    // The window takes a second app in without rebuilding, which would undo
    // what the person unticked.

    func testASecondAppArrivesTicked() {
        let before = [group("com.a", [leftover("/a1")])]
        let after = before + [group("com.b", [leftover("/b1")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1"], current: after),
            ["/a1", "/b1"])
    }

    /// Unticking is a decision, and a second app arriving does not undo it.
    func testWhatWasUntickedStaysUnticked() {
        let before = [group("com.a", [leftover("/a1"), leftover("/a2")])]
        let after = before + [group("com.b", [leftover("/b1")])]
        let selection = TrashOfferPlan.selectionAfterRefresh(
            previous: before, selected: ["/a1"], current: after)
        XCTAssertFalse(selection.contains("/a2"), "a path the person unticked came back ticked")
        XCTAssertEqual(selection, ["/a1", "/b1"])
    }

    /// And the other direction: something ticked by hand stays ticked, even
    /// though the default would have left it alone.
    func testAGuessTickedByHandStaysTicked() {
        let before = [group("com.a", [leftover("/a1", byName: true)])]
        let after = before + [group("com.b", [leftover("/b1")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1"], current: after),
            ["/a1", "/b1"])
    }

    /// The new group's own default applies: a late name guess is still a guess.
    func testANewGroupsGuessArrivesUnticked() {
        let before = [group("com.a", [leftover("/a1")])]
        let after = before + [group("com.b", [leftover("/b1"), leftover("/b2", byName: true)])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1"], current: after),
            ["/a1", "/b1"])
    }

    /// An app put back before the window was answered takes its files out of the
    /// selection.
    func testAnAppThatLeftTheTrashLeavesTheSelection() {
        let before = [group("com.a", [leftover("/a1")]), group("com.b", [leftover("/b1")])]
        let after = [group("com.a", [leftover("/a1")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1", "/b1"], current: after),
            ["/a1"])
    }

    // MARK: - Which apps a removal has actually answered for

    // A "no" is remembered while the app sits in the Trash, and some of these
    // files are offered nowhere else, so a refusal recorded as an answer takes
    // them off every screen.

    func testAppsWhosePathsAllMovedAreAnswered() {
        let groups = [group("com.a", [leftover("/a1")]), group("com.b", [leftover("/b1")])]
        let result = UninstallResult(trashed: ["/a1", "/b1"], freedBytes: 20)
        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID),
                       ["com.a", "com.b"])
    }

    /// A refusal from macOS is not a decision: the person may fix the cause, and
    /// the offer has to be able to come back.
    func testAnAppWhosePathWasRefusedIsNotAnswered() {
        let groups = [group("com.a", [leftover("/a1")]), group("com.b", [leftover("/b1")])]
        let result = UninstallResult(
            trashed: ["/b1"], freedBytes: 10,
            failures: [TrashFailureInfo(path: "/a1", reason: .noPermission)])
        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID),
                       ["com.b"], "an app macOS refused was filed as the person's no")
    }

    /// One refusal in a group is enough: the app still has something of its on
    /// disk, and that is the state the offer exists for.
    func testOneRefusalInAGroupHoldsTheWholeGroupOpen() {
        let groups = [group("com.a", [leftover("/a1"), leftover("/a2")])]
        let result = UninstallResult(
            trashed: ["/a1"], freedBytes: 10,
            failures: [TrashFailureInfo(path: "/a2", reason: .noPermission)])
        XCTAssertTrue(TrashOfferPlan.answered(groups, to: result).isEmpty)
    }

    /// A path the person left unticked is not a refusal — they saw it and said
    /// no to that one. The app has been answered.
    func testAnUntickedPathDoesNotHoldTheGroupOpen() {
        let groups = [group("com.a", [leftover("/a1"), leftover("/a2", byName: true)])]
        let result = UninstallResult(trashed: ["/a1"], freedBytes: 10)
        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID), ["com.a"])
    }

    /// A refresh that changes nothing must change nothing.
    func testTheSameGroupsKeepTheSameSelection() {
        let groups = [group("com.a", [leftover("/a1"), leftover("/a2")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: groups,
                                                 selected: ["/a2"], current: groups),
            ["/a2"])
    }
}
