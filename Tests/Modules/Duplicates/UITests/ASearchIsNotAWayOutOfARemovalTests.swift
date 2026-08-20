import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// «Search again» during a removal is the second way out of a destructive act,
/// and it was never gated.
///
/// `ClearSelectionIsNotAWayOutOfRemovalTests` records the first one: the basket
/// emptied on screen while the request was already out with those paths in it,
/// so «Moved to the Trash — 9 GB» arrived about a selection the person had just
/// cleared. `clearBasket` grew a `guard !busy` and the page dims the button.
///
/// `search()` does the same three things and has neither. Its first four lines
/// are `phase = .searching`, `groups = []`, `basket = []`, `clearRemovalReport()`
/// — and nothing in it asks whether a removal is in flight. The toolbar's Search
/// button is drawn for `phase != .searching`, which during a removal is `.result`,
/// so it is live and undimmed for the whole window; and in this module that
/// window is minutes, because `DuplicatesEngine.trash` re-reads both files of
/// every pair in full before anything moves.
///
/// Two things go with the basket. The count and the marks, which is the same
/// harm the clear button had. And **the way out**: the page draws its busy row —
/// the removal's tick and the Stop button — inside `basketBar`, which is drawn
/// only for a non-empty basket, a report or a marks note. `search()` takes all
/// three away in one press, so a removal a person has started goes on running
/// with no control anywhere on screen that reaches it.
///
/// Parked, never answered on the spot: a removal that returns before the press
/// under test is a window nothing can be inside, and every assertion here would
/// hold with the gate deleted.
@MainActor
final class ASearchIsNotAWayOutOfARemovalTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }
    private var second: String { "\(home)/Downloads/second.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000),
                                .init(path: second, bytes: 9_000_000)])
    }

    /// A page whose removal is out on the wire and cannot come back until this
    /// test lets it.
    private func removalInFlight() async -> (DuplicatesViewModel, DuplicatesWire) {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where wire.parkedCount < 1 { await Task.yield() }
        return (dvm, wire)
    }

    /// The window closed, so the suite does not carry a parked task out of the
    /// test that made it.
    private func finish(_ dvm: DuplicatesViewModel, _ wire: DuplicatesWire) async {
        wire.answers(.reply)
        wire.releaseParked()
        for _ in 0..<1000 where dvm.busy { await Task.yield() }
    }

    /// The same claim `clearBasket` makes, in the control beside it: the request
    /// is out with those paths in it, so nothing on screen may say they are no
    /// longer marked.
    func testSearchingWhileTheFilesAreGoingKeepsTheSelectionTheRequestIsOutWith() async {
        let (dvm, wire) = await removalInFlight()
        XCTAssertEqual(wire.parkedCount, 1, "precondition: the removal is really in flight")
        XCTAssertTrue(dvm.busy, "precondition: the model knows a removal is running")
        XCTAssertEqual(dvm.basket, [extra], "precondition: the selection is what was sent")

        dvm.search()

        XCTAssertEqual(dvm.basket, [extra], """
            «Search again» emptied the basket while the removal was still out with those paths \
            in it — the same press `clearBasket` grew a `guard !busy` for, in the control next \
            to it
            """)
        await finish(dvm, wire)
    }

    /// `DuplicatesSettingsPage`'s own condition for drawing `basketBar` — the
    /// one place on the page that reads `dvm.busy`, and therefore the only place
    /// the removal's tick and its Stop button can appear.
    ///
    /// Mirrored rather than rendered, and spelled from the same three published
    /// values the page reads, so a page that starts drawing the bar on something
    /// else makes this read wrong at a glance instead of passing quietly.
    private func pageDrawsTheBasketBar(_ dvm: DuplicatesViewModel) -> Bool {
        let hasReport = dvm.replyLost || dvm.removalStopped
            || dvm.banner != nil || !dvm.failures.isEmpty
        return !dvm.basket.isEmpty || hasReport || dvm.marksNote != nil
    }

    /// And the removal is still running, so this is not «the search cancelled
    /// it»: it is the screen forgetting a destructive act that is still under
    /// way, and taking the only way out of it with the basket.
    func testTheRemovalInFlightStillHasSomewhereToDrawItsStop() async {
        let (dvm, wire) = await removalInFlight()
        XCTAssertTrue(pageDrawsTheBasketBar(dvm), "precondition: the bar is up before the press")

        dvm.search()

        XCTAssertTrue(dvm.busy, "precondition: pressing Search did not end the removal")
        XCTAssertEqual(wire.parkedCount, 1, "precondition: the removal request is still parked")
        XCTAssertTrue(pageDrawsTheBasketBar(dvm), """
            the basket, the report and the marks note all went down in one press, and the page \
            draws the removal's tick and its Stop button inside the bar those three bring up — \
            so a removal the person started has no control anywhere on screen that reaches it
            """)
        await settle()
        XCTAssertTrue(dvm.busy, "precondition: still running once the search has answered")
        XCTAssertTrue(pageDrawsTheBasketBar(dvm),
                      "and the search answering does not bring the Stop control back either")
        await finish(dvm, wire)
    }

    /// The page's half of the gate, the way `testTheClearButtonIsDimmedWhileARemovalRuns`
    /// holds the other one: a model that refuses while the control stays live is
    /// a press that looks like it worked (ARCHITECTURE.md § One removal at a time).
    func testTheSearchControlIsDimmedWhileARemovalRuns() throws {
        let lines = try RepoSource
            .lines(of: "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let search = try XCTUnwrap(lines.firstIndex { $0.contains("dvm.search()") },
                                   "the toolbar no longer calls the search from this page")
        let around = lines[max(0, search - 4)...].prefix(8).joined(separator: "\n")
        XCTAssertTrue(around.contains("dvm.busy"), """
            «Search again» stays live and undimmed for the whole of a removal, and pressing it \
            clears the basket the request is out with:
            \(around)
            """)
    }
}
