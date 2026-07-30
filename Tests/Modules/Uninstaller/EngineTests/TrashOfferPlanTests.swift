import XCTest
@testable import Module_Uninstaller_Engine

/// What the unprompted window may act on.
///
/// This window is different from the review screen in one way that decides all of
/// these rules: nobody asked for it. It opened because an app reached the Trash,
/// and whatever it arrives with ticked is what one press removes — so the ticks
/// have to be defensible without a person having read a single path.
final class TrashOfferPlanTests: XCTestCase {

    private func leftover(_ path: String, _ bytes: Int = 10,
                          byName: Bool = false) -> Leftover {
        Leftover(path: path, kind: .appSupport, sizeBytes: bytes, matchedByName: byName)
    }

    private func group(_ id: String, _ leftovers: [Leftover]) -> TrashedAppLeftovers {
        TrashedAppLeftovers(bundleID: id, name: "App",
                            appPath: "/Users/ann/.Trash/App.app", leftovers: leftovers)
    }

    // MARK: - What arrives ticked

    func testALeftoverFoundByBundleIDArrivesTicked() {
        let groups = [group("com.a", [leftover("/Users/ann/Library/Caches/com.a")])]
        XCTAssertEqual(TrashOfferPlan.defaultSelection(groups),
                       ["/Users/ann/Library/Caches/com.a"])
    }

    /// The same default the review screen takes, and it matters more here: there
    /// the person ticked the app themselves, here the window arrived on its own.
    /// `Application Support/Mail` is a guess about a name, and a guess arriving
    /// pre-ticked means somebody has to notice it to keep their data.
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

    /// Two apps in the Trash can name the same file — a shared group container
    /// under a suite id both of them declare. Ticked once, listed once, and the
    /// size below counted once.
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

    /// The app is already where the person put it. Helm cleans up around that
    /// decision and does not touch the bundle — not to remove it, and not to
    /// empty the Trash on somebody's behalf. Nothing in the window offers the
    /// bundle, so this is the guard for a selection that arrives holding it
    /// anyway: the ticks are a set of strings and this is the last place that
    /// can tell what they name.
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

    // MARK: - What the footer says

    func testTheSizeCountsWhatIsTicked() {
        let groups = [group("com.a", [leftover("/1", 100), leftover("/2", 20)])]
        XCTAssertEqual(TrashOfferPlan.totalBytes(groups, selected: ["/1"]), 100)
    }

    func testTheSizeCountsASharedPathOnce() {
        let shared = "/Users/ann/Library/Group Containers/group.a"
        let groups = [group("com.a", [leftover(shared, 100)]), group("com.b", [leftover(shared, 100)])]
        XCTAssertEqual(TrashOfferPlan.totalBytes(groups, selected: [shared]), 100,
                       "one folder was counted twice because two apps listed it")
    }

    func testNothingTickedIsZero() {
        let groups = [group("com.a", [leftover("/1", 100)])]
        XCTAssertEqual(TrashOfferPlan.totalBytes(groups, selected: []), 0)
    }

    // MARK: - A second app arrives while the window is open

    /// Dragging two apps to the Trash is one gesture to the person and two
    /// arrivals to the app, so the window has to take the second one. What it
    /// must not do is take it by rebuilding: a person who unticked something and
    /// then dropped another app would have their decision quietly undone.

    func testASecondAppArrivesTicked() {
        let before = [group("com.a", [leftover("/a1")])]
        let after = before + [group("com.b", [leftover("/b1")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1"], current: after),
            ["/a1", "/b1"])
    }

    /// The one that matters. Unticking is a decision, and a decision the window
    /// forgets because somebody dropped a second app is worse than no window.
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

    /// The new group's own default still applies to it — arriving late does not
    /// make a name guess any less of a guess.
    func testANewGroupsGuessArrivesUnticked() {
        let before = [group("com.a", [leftover("/a1")])]
        let after = before + [group("com.b", [leftover("/b1"), leftover("/b2", byName: true)])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1"], current: after),
            ["/a1", "/b1"])
    }

    /// An app put back before the window was answered takes its files out of the
    /// selection with it — they are not the person's to remove any more.
    func testAnAppThatLeftTheTrashLeavesTheSelection() {
        let before = [group("com.a", [leftover("/a1")]), group("com.b", [leftover("/b1")])]
        let after = [group("com.a", [leftover("/a1")])]
        XCTAssertEqual(
            TrashOfferPlan.selectionAfterRefresh(previous: before,
                                                 selected: ["/a1", "/b1"], current: after),
            ["/a1"])
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
