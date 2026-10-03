import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The thickness-and-opacity pop-over stands under the palette at the cell that opened it, above the palette
/// when there is no room under it, and is part of the chrome: a press on it is not a press on the picture.**
///
/// Written against `EditorChrome.place(selection:in:palette:popover:anchorX:)`, whose `popover` (a size, nil
/// for none) and `anchorX` (the cell's centre, in the display's own points) default to none and 0, and
/// `EditorChrome.popover: CGRect?`. The gap is 8 pt and the room kept beside the screen's edge is the
/// palette's 16 pt. Every rect below is spelled out here, none read from the code under test, so a gap or a
/// margin that drifts fails against the numbers and not against itself.
///
/// What total failure of the subject would print: a `popover` that is always nil fails every exact rect; a
/// `covers` that ignores it fails the point on the pop-over; one that covers the gap too fails the point in
/// the gap; a pop-over that never clamps fails the edge cases; one that never goes above fails the short case.
final class ThePopoverStandsUnderItsCellTests: XCTestCase {

    private let screen = CGSize(width: 1000, height: 800)
    private let palette = CGSize(width: 578, height: 76)
    private let size = CGSize(width: 260, height: 96)
    private let gap: CGFloat = 8, keep: CGFloat = 16

    private func chrome(_ selection: CGRect, anchorX: CGFloat, size: CGSize? = nil, screen: CGSize? = nil) -> EditorChrome {
        EditorChrome.place(selection: selection, in: screen ?? self.screen, palette: palette, popover: size ?? self.size, anchorX: anchorX)
    }

    // MARK: below, centred on the cell

    func testWithRoomUnderThePaletteThePopoverIsCentredOnTheCellEightPointsUnderIt() throws {
        let c = chrome(CGRect(x: 200, y: 100, width: 400, height: 200), anchorX: 300) // palette y 314...390
        XCTAssertEqual(c.palette, CGRect(x: 111, y: 314, width: 578, height: 76))
        XCTAssertEqual(c.popover, CGRect(x: 300 - 130, y: 398, width: 260, height: 96))
    }

    func testTheSizeAndTheCellAreReadNotAssumed() throws {
        for (size, anchor) in [(CGSize(width: 260, height: 96), CGFloat(300)), (CGSize(width: 200, height: 70), 450), (CGSize(width: 320, height: 130), 520)] {
            let rect = try XCTUnwrap(chrome(CGRect(x: 200, y: 100, width: 400, height: 200), anchorX: anchor, size: size).popover)
            XCTAssertEqual(rect, CGRect(x: anchor - size.width / 2, y: 398, width: size.width, height: size.height), "\(size) at \(anchor)")
        }
    }

    func testAbsentPopoverLeavesThePaletteWhereItWasAndCoversNothingUnderIt() {
        let selection = CGRect(x: 200, y: 100, width: 400, height: 200)
        let without = EditorChrome.place(selection: selection, in: screen, palette: palette)
        XCTAssertNil(without.popover)
        XCTAssertFalse(without.covers(CGPoint(x: 300, y: 430)), "a point where the pop-over would be is the picture's when none is open")
        XCTAssertEqual(chrome(selection, anchorX: 300).palette, without.palette, "opening the pop-over moved the palette")
    }

    // MARK: the boundary: height + 8 + 16

    func testTheBoundaryIsHeightPlusEightPlusSixteenOnePointEitherSide() throws {
        // The palette's bottom is the selection's bottom + 14 + 76; the pop-over needs 8 + 96 + 16 under it.
        for (selectionBottom, below) in [(CGFloat(590), true), (591, false), (589, true)] {
            let c = chrome(CGRect(x: 200, y: 300, width: 400, height: selectionBottom - 300), anchorX: 400)
            let popover = try XCTUnwrap(c.popover)
            XCTAssertEqual(c.palette.maxY, selectionBottom + 90, "control: the palette is where the sum says")
            if below {
                XCTAssertEqual(popover.minY, c.palette.maxY + gap, "bottom \(selectionBottom): under")
                XCTAssertLessThanOrEqual(popover.maxY + keep, screen.height)
            } else {
                XCTAssertEqual(popover.maxY, c.palette.minY - gap, "bottom \(selectionBottom): one point short, above")
            }
        }
    }

    func testWithoutRoomUnderThePaletteThePopoverGoesAboveItEightPointsFromIt() throws {
        let c = chrome(CGRect(x: 100, y: 20, width: 800, height: 770), anchorX: 400) // palette inside the area, y 700...776
        XCTAssertEqual(c.palette.minY, 700)
        XCTAssertEqual(c.popover, CGRect(x: 270, y: 700 - 8 - 96, width: 260, height: 96))
    }

    // MARK: the screen's edges

    func testAtTheLeftEdgeThePopoverIsHeldSixteenPointsFromIt() throws {
        let rect = try XCTUnwrap(chrome(CGRect(x: 0, y: 100, width: 60, height: 100), anchorX: 5).popover)
        XCTAssertEqual(rect.minX, 16)
        XCTAssertEqual(rect.size, size)
    }

    func testAtTheRightEdgeThePopoverIsHeldSixteenPointsFromIt() throws {
        let rect = try XCTUnwrap(chrome(CGRect(x: 940, y: 100, width: 60, height: 100), anchorX: 995).popover)
        XCTAssertEqual(rect.maxX, 1000 - 16)
        XCTAssertEqual(rect.size, size)
    }

    func testACellThatIsNoNumberOrInfiniteLeavesThePopoverOnTheScreen() throws {
        let bounds = CGRect(origin: .zero, size: screen)
        for anchor in [CGFloat.nan, .infinity, -.infinity, 1e12, -1e12] {
            let rect = try XCTUnwrap(chrome(CGRect(x: 200, y: 100, width: 400, height: 200), anchorX: anchor).popover, "anchor \(anchor)")
            XCTAssertTrue(bounds.contains(rect), "anchor \(anchor): \(rect) is off the screen")
        }
    }

    func testWithNoRoomOnEitherSideThePopoverStaysOnTheScreen() throws {
        let short = CGSize(width: 1000, height: 200)
        let c = chrome(CGRect(x: 100, y: 20, width: 800, height: 170), anchorX: 400, screen: short)
        let popover = try XCTUnwrap(c.popover)
        XCTAssertTrue(CGRect(origin: .zero, size: short).contains(popover), "off the screen: \(popover)")
        XCTAssertEqual(popover.size, size)
    }

    // MARK: covers

    func testCoversIncludesThePopoverAndNotTheGapBetween() throws {
        let c = chrome(CGRect(x: 200, y: 100, width: 400, height: 200), anchorX: 300) // palette ...390, popover 398...494, x 170...430
        XCTAssertTrue(c.covers(CGPoint(x: 300, y: 350)), "the palette")
        XCTAssertTrue(c.covers(CGPoint(x: 300, y: 450)), "the pop-over's middle")
        XCTAssertTrue(c.covers(CGPoint(x: 171, y: 399)), "the pop-over's corner")
        XCTAssertFalse(c.covers(CGPoint(x: 300, y: 394)), "the gap between the palette and the pop-over is the picture's")
        XCTAssertFalse(c.covers(CGPoint(x: 300, y: 500)), "under the pop-over")
        XCTAssertFalse(c.covers(CGPoint(x: 160, y: 450)), "left of the pop-over, which is narrower than the palette")
        XCTAssertFalse(c.covers(CGPoint(x: 440, y: 450)), "right of the pop-over")
    }

    func testCoversIncludesAPopoverAbovePalette() throws {
        let c = chrome(CGRect(x: 100, y: 20, width: 800, height: 770), anchorX: 400) // popover 596...692
        XCTAssertTrue(c.covers(CGPoint(x: 400, y: 640)))
        XCTAssertFalse(c.covers(CGPoint(x: 400, y: 695)), "the gap above the palette")
    }
}
