import HelmTestSupport
import HelmUI
import XCTest

/// **The panel's grid marks an edge only where widgets really continue past it.**
///
/// A widget cut by the scroll view's clip read as a short widget, and the tab
/// strip, the grid and the footer as one flat sheet. `PanelScrollEdges` is the
/// whole decision; each case below is one of the ways it can be wrong — a mark
/// on a grid that fits (a fade eating the first widget's top for nothing), no
/// mark on a grid that does not, or the two edges swapped.
final class APanelListSaysWhereItContinuesTests: XCTestCase {

    /// A 600 pt grid in a 400 pt scroll view with no insets: 200 pt of travel.
    private func edges(at offset: CGFloat, content: CGFloat = 600,
                       insetTop: CGFloat = 0, insetBottom: CGFloat = 0) -> PanelScrollEdges {
        PanelScrollEdges(offset: offset, insetTop: insetTop, insetBottom: insetBottom,
                         contentHeight: content, viewport: 400)
    }

    func testAGridThatFitsMarksNeitherEdge() {
        XCTAssertEqual(edges(at: 0, content: 300), .none,
                       "a grid shorter than its scroll view was marked as continuing")
        XCTAssertEqual(edges(at: 0, content: 400), .none,
                       "a grid exactly the scroll view's height was marked as continuing")
    }

    func testAtTheTopOnlyTheBottomContinues() {
        XCTAssertEqual(edges(at: 0), PanelScrollEdges(above: false, below: true))
    }

    func testMidwayBothContinue() {
        XCTAssertEqual(edges(at: 100), PanelScrollEdges(above: true, below: true))
    }

    func testAtTheBottomOnlyTheTopContinues() {
        XCTAssertEqual(edges(at: 200), PanelScrollEdges(above: true, below: false))
    }

    /// At rest a top inset puts the offset at minus the inset, and rounding
    /// puts a few hundredths on either end; neither is content past an edge.
    func testInsetsAndRoundingAtRestAreNotContent() {
        XCTAssertEqual(edges(at: -8, insetTop: 8).above, false)
        XCTAssertEqual(edges(at: 0.3).above, false)
        XCTAssertEqual(edges(at: 208, insetBottom: 8).below, false)
        XCTAssertEqual(edges(at: 199.7).below, false)
    }

    /// The panel's grid is the scroll view that wears it — a helper nobody
    /// applies is a check on a type, not on the panel.
    func testThePanelsGridWearsIt() throws {
        let code = SwiftSource.code(try RepoSource.text(of: "Sources/HelmApp/HelmPanel.swift"))
        let scroll = try XCTUnwrap(code.range(of: "ScrollView {"), "the panel has no scroll view")
        let footer = try XCTUnwrap(code.range(of: "PanelEditBar", range: scroll.upperBound..<code.endIndex),
                                   "the panel's footer block is not after its scroll view")
        XCTAssertTrue(code[scroll.lowerBound..<footer.lowerBound].contains(".helmPanelScrollEdges()"),
                      "the panel's grid scroll view does not mark the edges it clips")
    }
}
