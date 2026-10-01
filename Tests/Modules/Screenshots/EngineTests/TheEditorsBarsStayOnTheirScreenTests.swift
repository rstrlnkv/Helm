import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The two bars stand outside the selection where there is room and inward where there
/// is not, and are never off the screen or on each other.** A pure function of three
/// sizes, so each edge and each corner of the screen is a case; the sweep at the end asks
/// the same of every selection on a grid, the thin and the tiny ones included.
final class TheEditorsBarsStayOnTheirScreenTests: XCTestCase {

    private let screen = CGSize(width: 1000, height: 800)
    private let tools = CGSize(width: 68, height: 330)
    private let actions = CGSize(width: 220, height: 40)
    private var visible: CGRect { CGRect(origin: .zero, size: screen) }

    private func place(_ selection: CGRect, screen: CGSize? = nil, tools: CGSize? = nil, actions: CGSize? = nil) -> EditorChrome {
        EditorChrome.place(selection: selection, in: screen ?? self.screen, tools: tools ?? self.tools,
                           actions: actions ?? self.actions)
    }

    private func assertOnScreen(_ chrome: EditorChrome, _ what: String, on size: CGSize? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let visible = size.map { CGRect(origin: .zero, size: $0) } ?? self.visible
        for (name, bar) in [("tools", chrome.tools), ("actions", chrome.actions)] {
            XCTAssertTrue(visible.contains(bar), "\(what): the \(name) bar \(bar) is off the screen", file: file, line: line)
        }
        XCTAssertFalse(chrome.tools.intersects(chrome.actions), "\(what): the bars lie on each other: \(chrome)", file: file, line: line)
    }

    func testASmallScreenATallToolBarAndABottomLeftSelectionKeepTheBarsApart() {
        let small = CGSize(width: 300, height: 200)
        let tall = CGSize(width: 68, height: 150)
        for selection in [CGRect(x: 0, y: 150, width: 40, height: 50), CGRect(x: 10, y: 120, width: 120, height: 70),
                          CGRect(x: 0, y: 190, width: 5, height: 10)] {
            let chrome = place(selection, screen: small, tools: tall, actions: CGSize(width: 260, height: 30))
            XCTAssertFalse(chrome.tools.intersects(chrome.actions), "\(selection): the bars lie on each other: \(chrome)")
            XCTAssertTrue(CGRect(origin: .zero, size: small).contains(chrome.actions), "\(selection): the row left the screen: \(chrome)")
        }
    }

    func testWithRoomTheToolsAreRightOfTheSelectionAndTheRowIsBelowIt() {
        let selection = CGRect(x: 300, y: 200, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertEqual(chrome.tools.minX, selection.maxX + EditorChrome.gap, "the tool bar is not to the right of the selection")
        XCTAssertEqual(chrome.tools.minY, selection.minY, "the tool bar does not start at the selection's top")
        XCTAssertEqual(chrome.actions.minY, selection.maxY + EditorChrome.gap, "the row is not under the selection")
        XCTAssertEqual(chrome.actions.maxX, selection.maxX, "the row is not flush with the selection's right edge")
        assertOnScreen(chrome, "centre")
    }

    func testAtTheRightEdgeTheToolsFlipInwardAndTheRowStaysBelow() {
        let selection = CGRect(x: 600, y: 200, width: 400, height: 200)
        let chrome = place(selection)
        XCTAssertLessThanOrEqual(chrome.tools.maxX, selection.maxX - EditorChrome.gap + 0.001, "the tool bar did not come inside")
        XCTAssertGreaterThanOrEqual(chrome.tools.minX, selection.minX, "the tool bar left the selection altogether")
        XCTAssertEqual(chrome.actions.minY, selection.maxY + EditorChrome.gap)
        assertOnScreen(chrome, "right edge")
    }

    func testAtTheBottomEdgeTheRowFlipsInward() {
        let selection = CGRect(x: 200, y: 400, width: 300, height: 400)
        let chrome = place(selection)
        XCTAssertLessThanOrEqual(chrome.actions.maxY, selection.maxY - EditorChrome.gap + 0.001, "the row did not come inside")
        XCTAssertEqual(chrome.tools.minX, selection.maxX + EditorChrome.gap)
        assertOnScreen(chrome, "bottom edge")
    }

    func testAtTheTopAndLeftEdgesNothingNeedsToFlip() {
        let selection = CGRect(x: 0, y: 0, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertEqual(chrome.tools.minX, selection.maxX + EditorChrome.gap)
        XCTAssertEqual(chrome.actions.minY, selection.maxY + EditorChrome.gap)
        assertOnScreen(chrome, "top-left corner")
    }

    func testAFullScreenSelectionPutsBothBarsInsideAndApart() {
        let chrome = place(visible)
        XCTAssertTrue(visible.insetBy(dx: 1, dy: 1).contains(chrome.tools))
        XCTAssertTrue(visible.insetBy(dx: 1, dy: 1).contains(chrome.actions))
        assertOnScreen(chrome, "whole screen")
    }

    func testTheBottomRightCornerMovesTheRowLeftOfTheToolBarRatherThanOverIt() {
        let selection = CGRect(x: 700, y: 600, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertLessThanOrEqual(chrome.actions.maxX, chrome.tools.minX, "the row is under the tool bar's column, not beside it: \(chrome)")
        assertOnScreen(chrome, "bottom-right corner")
    }

    func testATinySelectionAtEveryCornerAndTheCentreStillHasBothBarsOnTheScreen() {
        for (name, origin) in [("top-left", CGPoint(x: 0, y: 0)), ("top-right", CGPoint(x: 990, y: 0)),
                               ("bottom-left", CGPoint(x: 0, y: 790)), ("bottom-right", CGPoint(x: 990, y: 790)),
                               ("centre", CGPoint(x: 500, y: 400))] {
            assertOnScreen(place(CGRect(origin: origin, size: CGSize(width: 10, height: 10))), "10 pt at \(name)")
        }
    }

    func testEverySelectionOnAGridKeepsBothBarsOnTheScreenAndApart() {
        let edges: [CGFloat] = [0, 1, 60, 300, 640, 930, 999, 1000]
        let tops: [CGFloat] = [0, 1, 40, 390, 700, 770, 799, 800]
        var cases = 0
        for x0 in edges { for x1 in edges where x1 > x0 + 0.5 {
            for y0 in tops { for y1 in tops where y1 > y0 + 0.5 {
                cases += 1
                assertOnScreen(place(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)), "selection \(x0),\(y0)-\(x1),\(y1)")
            } }
        } }
        XCTAssertGreaterThan(cases, 500, "the sweep did not run: \(cases) cases")
    }

    func testAWideRowAtTheCornerStillFitsWhenTheToolBarIsBeside() {
        // The widest a language can make the row, on a screen only 1280 wide with a selection in its corner.
        let chrome = place(CGRect(x: 1100, y: 600, width: 180, height: 200), screen: CGSize(width: 1280, height: 800),
                           actions: CGSize(width: 380, height: 40))
        assertOnScreen(chrome, "wide row", on: CGSize(width: 1280, height: 800))
    }

    func testBarsLargerThanTheScreenAreHeldAtItsStartNotOffItsFarSide() {
        let chrome = place(CGRect(x: 10, y: 10, width: 20, height: 20), screen: CGSize(width: 300, height: 200))
        XCTAssertEqual(chrome.tools.minY, EditorChrome.margin)
        XCTAssertGreaterThanOrEqual(chrome.tools.minX, 0)
        XCTAssertGreaterThanOrEqual(chrome.actions.minX, 0)
    }

    func testANotANumberSelectionDoesNotMakeANotANumberBar() {
        let chrome = place(CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 10, height: 10))
        for bar in [chrome.tools, chrome.actions] {
            XCTAssertTrue([bar.minX, bar.minY].allSatisfy(\.isFinite), "\(bar)")
        }
    }

    func testCoversIsTheBarsAndNothingBetween() {
        let chrome = place(CGRect(x: 300, y: 200, width: 300, height: 200))
        XCTAssertTrue(chrome.covers(CGPoint(x: chrome.tools.midX, y: chrome.tools.midY)))
        XCTAssertTrue(chrome.covers(CGPoint(x: chrome.actions.midX, y: chrome.actions.midY)))
        XCTAssertFalse(chrome.covers(CGPoint(x: 450, y: 300)), "a point in the selection is on a bar")
    }
}
