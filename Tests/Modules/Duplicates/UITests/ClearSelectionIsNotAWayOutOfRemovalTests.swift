import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// «Clear selection» during a removal emptied the basket and the files went
/// anyway.
///
/// Measured with `trash` parked: `basket 0, busy true, parked 1` — and then
/// «Moved to the Trash — 9 GB» about the very selection the person had just
/// cleared. `emptyBasket` captures the paths at its first line, so the request
/// is already out with them in it; the button had no `.disabled` and the model
/// had no guard, so the only control on the screen that looks like a way out of
/// a destructive act was not one.
///
/// **Not academic in this module.** `DuplicatesEngine.trash` re-reads both files
/// of every pair in full before anything moves, serially, so the window between
/// the press and the reply is proportional to the volume marked: minutes on an
/// external drive.
///
/// The guard is on the model *and* the page dims the button — both, or neither is
/// reliable (ARCHITECTURE.md § One removal at a time). And it is on the press,
/// not on the reading: `LeftoversViewModel.dropHiddenSelections` records what the
/// naive version costs, where a removal holds `busy` across its own rescan.
@MainActor
final class ClearSelectionIsNotAWayOutOfRemovalTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }
    private var second: String { "\(home)/Downloads/second.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000),
                                .init(path: second, bytes: 9_000_000)])
    }

    /// A removal held open by a parked reply, which is the only way to be inside
    /// the window at all: a transport that answers on the spot is over before
    /// anything can be pressed, and a test written against one would pass with the
    /// guard deleted.
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

    func testClearingTheSelectionIsRefusedWhileTheFilesAreGoing() async {
        let (dvm, wire) = await removalInFlight()
        XCTAssertEqual(wire.parkedCount, 1, "precondition: the removal is really in flight")
        XCTAssertTrue(dvm.busy, "precondition: the model knows a removal is running")
        XCTAssertEqual(dvm.basket, [extra], "precondition: the selection is what was sent")

        dvm.clearBasket()

        XCTAssertEqual(dvm.basket, [extra], """
            the basket emptied on screen while the request was still out with those paths in it, \
            so the app reported success about a selection the person had just cleared
            """)
        wire.releaseParked()
        for _ in 0..<200 where dvm.busy { await Task.yield() }
    }

    /// And it works again the moment the removal is over, or the guard has taken
    /// the control away rather than deferred it.
    func testClearingTheSelectionWorksOnceTheRemovalIsAnswered() async {
        let (dvm, wire) = await removalInFlight()
        dvm.toggleBasket(second)
        XCTAssertEqual(dvm.basket, [extra, second], "precondition: two are marked")

        wire.releaseParked()
        for _ in 0..<200 where dvm.busy { await Task.yield() }
        XCTAssertFalse(dvm.busy, "precondition: the removal came back")

        dvm.clearBasket()

        XCTAssertTrue(dvm.basket.isEmpty, "the guard outlived the removal it was for")
    }

    /// The page's half: the button that would call it is dimmed for the same
    /// reason. A model that refuses while the control stays live is a press that
    /// looks like it worked, and a control that dims while the model accepts is
    /// one redraw from the same defect.
    func testTheClearButtonIsDimmedWhileARemovalRuns() throws {
        // `RepoSource`, not a count of `deletingLastPathComponent`s: that count is
        // a fact about where this file sits and breaks silently when it moves.
        let lines = try RepoSource.lines(of: "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let button = try XCTUnwrap(lines.firstIndex { $0.contains("DupStr.clearBasket") },
                                   "the page no longer draws that button under that name")
        let following = lines[button...].prefix(3).joined(separator: "\n")
        XCTAssertTrue(following.contains(".disabled(dvm.busy)"), """
            «Clear selection» stays live while a removal runs: \(following)
            """)
    }
}
