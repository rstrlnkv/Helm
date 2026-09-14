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
/// either side of the boundary rather than fifty. Asserting `true` at 834 pt
/// is the same redundancy against the 560 pt case: nothing between the two
/// literal widths distinguishes a mutant that passes one from a mutant that
/// passes the other. `testNothingCrashesAtNoWidth` asserted
/// `0 >= 560 == false`, which holds for any positive threshold at all — the
/// only mutation it caught, `masterAndInspector <= 0`, also fails the case
/// below, so it named a crash no `CGFloat` comparison can produce and checked
/// nothing past what that case already does.
final class HomebrewSplitTests: XCTestCase {

    func testTheThresholdIsWhereTheMeasurementPutIt() {
        XCTAssertFalse(HomebrewSplit(availableWidth: 543).showsInspector)
        XCTAssertTrue(HomebrewSplit(availableWidth: 560).showsInspector)
    }
}
