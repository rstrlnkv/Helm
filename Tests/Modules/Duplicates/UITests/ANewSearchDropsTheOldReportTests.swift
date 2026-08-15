import HelmRuntime
import Module_Duplicates_Engine
import XCTest
@testable import Module_Duplicates_UI

/// A removal's report belongs to the press that made it, not to the next
/// search's results.
///
/// `search()` cleared `replyLost` and `marksNote` and left `banner`, `failures`
/// and `removedCount` standing — so a refusal from the last removal sat under a
/// different folder's list, saying «could not be moved» about a file the new
/// search never returned. The five fields are one report and go together.
@MainActor
final class ANewSearchDropsTheOldReportTests: XCTestCase {

    /// A removal that both moved something and refused something, so every
    /// field of the report is non-empty before the search that must clear it —
    /// an assertion about an absence passes when the subject never happened.
    private func reportedModel() async -> DuplicatesViewModel {
        let keep = "\(home)/Downloads/keep.bin"
        let gone = "\(home)/Downloads/gone.bin"
        let refused = "\(home)/Downloads/refused.bin"
        let wire = DuplicatesWire(
            groups: [DuplicateGroup(bytes: 1_000_000, paths: [keep, gone, refused])],
            removal: DuplicateRemoval(
                removed: [gone],
                refused: [HelmTrash.Refusal(path: refused, reason: .changedSinceScan)],
                freedBytes: 1_000_000))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(gone)
        dvm.toggleBasket(refused)
        await dvm.emptyBasket()
        return dvm
    }

    func testANewSearchDropsTheLastRemovalsReport() async {
        let dvm = await reportedModel()
        XCTAssertNotNil(dvm.banner, "the removal never reported — this test is about nothing")
        XCTAssertEqual(dvm.failures.map(\.path), ["\(home)/Downloads/refused.bin"])
        XCTAssertEqual(dvm.removedCount, 1)

        dvm.search()

        XCTAssertNil(dvm.banner, "the old removal's banner hangs under the new search")
        XCTAssertTrue(dvm.failures.isEmpty,
                      "a refusal from the last removal is drawn under the next search's results")
        XCTAssertEqual(dvm.removedCount, 0)
    }
}
