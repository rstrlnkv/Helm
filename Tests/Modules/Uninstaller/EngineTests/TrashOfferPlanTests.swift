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
}
