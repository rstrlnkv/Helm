import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The palette stands outside the selection where there is room and inward where there is not, and is
/// never off the screen.** A pure function of the selection, the screen and the palette's size, so each edge and each
/// corner of the screen is a case; the sweep at the end asks the same of every selection on a grid, the thin and the
/// tiny ones included. Where it stands in each of the three places is `ThePaletteStandsBelowAboveOrInsideTests`'s.
final class TheEditorsBarsStayOnTheirScreenTests: XCTestCase {

    private let screen = CGSize(width: 1000, height: 800)
    private let palette = CGSize(width: 578, height: 76)
    private var visible: CGRect { CGRect(origin: .zero, size: screen) }

    private func place(_ selection: CGRect, screen: CGSize? = nil, palette: CGSize? = nil) -> EditorChrome {
        EditorChrome.place(selection: selection, in: screen ?? self.screen, palette: palette ?? self.palette)
    }

    private func assertOnScreen(_ chrome: EditorChrome, _ what: String, on size: CGSize? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let visible = size.map { CGRect(origin: .zero, size: $0) } ?? self.visible
        XCTAssertTrue(visible.contains(chrome.palette), "\(what): the palette \(chrome.palette) is off the screen", file: file, line: line)
    }

    func testWithRoomTheCentreOfThePaletteIsUnderTheSelectionByTheGap() {
        let selection = CGRect(x: 300, y: 200, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertEqual(chrome.palette.minY, selection.maxY + EditorChrome.gap, "the palette is not under the selection")
        XCTAssertEqual(chrome.palette.midX, selection.midX, accuracy: 0.001, "the palette is not centred on the selection")
        assertOnScreen(chrome, "centre")
    }

    func testAtTheBottomEdgeThePaletteFlipsAboveTheSelection() {
        let selection = CGRect(x: 200, y: 600, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertEqual(chrome.palette.maxY, selection.minY - EditorChrome.gap, "the palette did not go above")
        assertOnScreen(chrome, "bottom edge")
    }

    func testAtTheTopAndLeftEdgesNothingNeedsToFlip() {
        let selection = CGRect(x: 0, y: 0, width: 300, height: 200)
        let chrome = place(selection)
        XCTAssertEqual(chrome.palette.minY, selection.maxY + EditorChrome.gap)
        XCTAssertEqual(chrome.palette.minX, EditorChrome.margin, "the palette is not held against the left edge")
        assertOnScreen(chrome, "top-left corner")
    }

    func testAFullScreenSelectionPutsThePaletteInsideAndOnTheScreen() {
        let chrome = place(visible)
        XCTAssertTrue(visible.insetBy(dx: 1, dy: 1).contains(chrome.palette))
        XCTAssertTrue(CGRect(origin: .zero, size: screen).intersects(chrome.palette))
        XCTAssertEqual(chrome.palette.maxY, screen.height - EditorChrome.margin, "inside, the palette is held the margin from the screen's bottom edge")
        assertOnScreen(chrome, "whole screen")
    }

    func testATinySelectionAtEveryCornerAndTheCentreStillHasThePaletteOnTheScreen() {
        for (name, origin) in [("top-left", CGPoint(x: 0, y: 0)), ("top-right", CGPoint(x: 990, y: 0)),
                               ("bottom-left", CGPoint(x: 0, y: 790)), ("bottom-right", CGPoint(x: 990, y: 790)),
                               ("centre", CGPoint(x: 500, y: 400))] {
            assertOnScreen(place(CGRect(origin: origin, size: CGSize(width: 10, height: 10))), "10 pt at \(name)")
        }
    }

    func testEverySelectionOnAGridKeepsThePaletteOnTheScreen() {
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

    func testAWidePaletteAtTheCornerStillFits() {
        // A palette wider than the cells it has today (700 pt, for what later tasks add), on a screen only 1280 wide with a selection in its corner.
        let chrome = place(CGRect(x: 1100, y: 600, width: 180, height: 200), screen: CGSize(width: 1280, height: 800),
                           palette: CGSize(width: 700, height: 76))
        assertOnScreen(chrome, "wide palette", on: CGSize(width: 1280, height: 800))
    }

    func testAPaletteLargerThanTheScreenIsHeldAtItsStartNotOffItsFarSide() {
        let chrome = place(CGRect(x: 10, y: 10, width: 20, height: 20), screen: CGSize(width: 300, height: 200))
        XCTAssertEqual(chrome.palette.minX, EditorChrome.margin)
        XCTAssertGreaterThanOrEqual(chrome.palette.minY, 0)
    }

    func testANotANumberSelectionDoesNotMakeANotANumberPalette() {
        let chrome = place(CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 10, height: 10))
        XCTAssertTrue([chrome.palette.minX, chrome.palette.minY].allSatisfy(\.isFinite), "\(chrome.palette)")
    }

    func testCoversIsThePaletteAndNothingBetween() {
        let chrome = place(CGRect(x: 300, y: 200, width: 300, height: 200))
        XCTAssertTrue(chrome.covers(CGPoint(x: chrome.palette.midX, y: chrome.palette.midY)))
        XCTAssertFalse(chrome.covers(CGPoint(x: 450, y: 300)), "a point in the selection is on the palette")
        XCTAssertFalse(chrome.covers(CGPoint(x: chrome.palette.midX, y: 400 + EditorChrome.gap / 2)), "a point in the gap is on the palette")
    }
}
