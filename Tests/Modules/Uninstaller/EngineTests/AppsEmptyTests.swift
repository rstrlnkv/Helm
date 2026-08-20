import XCTest
@testable import Module_Uninstaller_Engine

/// Why the Apps tab's list is empty — the module's rule, not the page's guess.
///
/// The page used to branch on `loading` alone: a search that matched nothing, a
/// Mac whose list really is empty and a list the engine never answered all drew
/// the same empty inset `List` under a footer that still counted apps. Three
/// facts, one picture. `DuplicatesEmpty` and `HistoryEmpty` are the same repair
/// one and two modules over.
final class AppsEmptyTests: XCTestCase {

    func testAListWithRowsHasNoReason() {
        XCTAssertNil(AppsEmpty.reason(answered: true, apps: 3, shown: 3))
        XCTAssertNil(AppsEmpty.reason(answered: true, apps: 3, shown: 1),
                     "a filtered list that still shows rows is a list, not a statement")
    }

    /// A request that went out and came back with nothing is not a Mac with no
    /// applications on it — the footer already refuses that fold
    /// (`UninstallerViewModel.appCount`), and the body must not undo it.
    func testAnUnansweredListIsNotAMacWithNoApps() {
        XCTAssertEqual(AppsEmpty.reason(answered: false, apps: 0, shown: 0),
                       .neverAnswered)
    }

    func testAnAnsweredEmptyListIsAMacWithNoApps() {
        XCTAssertEqual(AppsEmpty.reason(answered: true, apps: 0, shown: 0),
                       .noApps)
    }

    /// The search owns the emptiness whenever there is a list behind it: rows
    /// exist, the filter hid every one, and «no applications» would be a claim
    /// about the Mac where the truth is a claim about the search field.
    func testASearchThatHidesEveryRowIsTheSearchsOwnSentence() {
        XCTAssertEqual(AppsEmpty.reason(answered: true, apps: 3, shown: 0),
                       .searchHidesAll)
    }

    /// One of the three is an invitation and two are statements, the split
    /// `HelmEmptyState` draws along and `LeftoversEmpty.invites` already answers
    /// one module over. A verb on the answered-and-empty screen offers to repeat
    /// a question just answered, and on the filtered one it offers to reload the
    /// Mac when what the person wants is the search field directly above.
    func testOnlyTheListNobodyAnsweredIsWorthAskingAgainFor() {
        XCTAssertTrue(AppsEmpty.invites(.neverAnswered),
                      "a list whose reply never came is a dead end without a way to ask again")
        XCTAssertFalse(AppsEmpty.invites(.noApps))
        XCTAssertFalse(AppsEmpty.invites(.searchHidesAll))
    }

    // MARK: - What the footer says beside all that

    /// **The page said two contradictory things at once.** The centre read
    /// «Helm could not read the list of applications» with a *Reload list*
    /// button while the footer 600 pt below read «Counting apps…» — one state,
    /// a failure and a claim of progress together. `UnStr.appsCount` takes an
    /// optional and folds two different unknowns into it: a count still on its
    /// way, and a count that will never come. The comment over `emptyMessage`
    /// said «the footer beside it already refuses that fold», and it did not.
    ///
    /// So the footer reads the body's own value. It cannot disagree with a
    /// screen it is derived from.
    func testTheFooterSaysNothingAboutAListNobodyAnswered() {
        XCTAssertEqual(AppsEmpty.status(.neverAnswered, loading: false, apps: 0), .silent)
    }

    /// A query still out is «Counting apps…» whatever the reason would be, and
    /// it is asked first: the body draws a spinner while `loading` holds, so
    /// there is no empty screen for the footer to contradict yet.
    func testAQueryStillOutIsCounting() {
        XCTAssertEqual(AppsEmpty.status(nil, loading: true, apps: 0), .counting)
        XCTAssertEqual(AppsEmpty.status(.neverAnswered, loading: true, apps: 0), .counting)
    }

    /// An answer of «none» is an answer, and it reads as a count of zero — the
    /// distinction `UninstallerViewModel.appCount` was already making and this
    /// keeps.
    func testAnAnswerIsACount() {
        XCTAssertEqual(AppsEmpty.status(.noApps, loading: false, apps: 0), .counted(0))
        XCTAssertEqual(AppsEmpty.status(.searchHidesAll, loading: false, apps: 7), .counted(7))
        XCTAssertEqual(AppsEmpty.status(nil, loading: false, apps: 7), .counted(7))
    }

    /// The whole point, stated over every reason rather than over the one that
    /// was wrong: no screen may show a refusal in the centre and a claim of
    /// progress underneath it.
    func testNoScreenClaimsProgressWhileItsBodyReportsARefusal() {
        for reason: AppsEmpty.Reason in [.neverAnswered, .noApps, .searchHidesAll] {
            let status = AppsEmpty.status(reason, loading: false, apps: 0)
            XCTAssertNotEqual(status, .counting, """
                the body says «\(reason)» and the footer beside it is still counting
                """)
        }
    }
}
