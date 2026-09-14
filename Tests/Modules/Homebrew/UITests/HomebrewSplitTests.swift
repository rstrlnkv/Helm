import XCTest
@testable import Module_Homebrew_UI

/// The literal boundary, pinned as a number — `TheSplitThresholdFitsThePageItGatesTests`
/// is what pins it as a *claim about the layout*, asking `HomebrewSplit` itself
/// rather than a literal width and checking the real page still fits at
/// whatever it answers; nothing here should duplicate that.
///
/// This file used to carry four cases. Three went: asserting `false` at 490 pt
/// cannot fail apart from asserting `false` at 543 pt below — `showsInspector`
/// is one `>=` against one constant, so any mutation that flips one flips the
/// other, and the 543/560 pair below is the tighter of the two, one point
/// either side of the boundary rather than fifty. `testNothingCrashesAtNoWidth`
/// asserted `0 >= 560 == false`, which holds for any positive threshold at
/// all — the only mutation it caught, `masterAndInspector <= 0`, also fails
/// the case below, so it named a crash no `CGFloat` comparison can produce and
/// checked nothing past what that case already does.
///
/// **Asserting `true` at 834 pt is not the same redundancy, and does not read
/// as one.** `>= 560 && < 800` passes the 560 pt case here and fails at 834 —
/// measured 2026-09-14 by substituting exactly that expression into
/// `HomebrewSplit.showsInspector` — so the pair on its own did distinguish
/// that mutant from a correct threshold. What actually made the 834 pt case
/// safe to delete is a check this file does not name:
/// `TheSplitThresholdFitsThePageItGatesTests.threshold` sweeps 200…1200 pt and
/// asserts monotonicity — once `showsInspector` turns true it must stay true —
/// so the same `< 800` mutant is caught there, before either of that file's
/// two tests can even run, without this file's help.
final class HomebrewSplitTests: XCTestCase {

    func testTheThresholdIsWhereTheMeasurementPutIt() {
        XCTAssertFalse(HomebrewSplit(availableWidth: 543).showsInspector)
        XCTAssertTrue(HomebrewSplit(availableWidth: 560).showsInspector)
    }
}
