import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The palette is one capsule: below the area, above it when below is short, inside it when
/// neither side has room, and always on the display being edited.** A pure function of the
/// selection, the screen and the palette's *measured* size, so every placement, every screen edge and
/// the boundary between "below" and "above" is a case that can be asked.
///
/// What total failure of the subject would print: an API that returns `.zero` is caught by every exact
/// rect here (none of them is `.zero`); a `place` that ignores the size is caught by
/// `testTheSizeIsReadNotAssumed` (three sizes, three answers) and by the boundary, which moves with the
/// height; a `place` that never clamps is caught by the edge cases; a `covers` that still looks at an old
/// frame is caught by the points inside and just outside the palette.
final class ThePaletteStandsBelowAboveOrInsideTests: XCTestCase {

    private let screen = CGSize(width: 1000, height: 800)
    private let palette = CGSize(width: 578, height: 76)
    private var visible: CGRect { CGRect(origin: .zero, size: screen) }
    /// The palette's distance from the area, and the room kept free under it.
    private let gap: CGFloat = 14, keep: CGFloat = 16

    private func place(_ selection: CGRect, screen: CGSize? = nil, palette: CGSize? = nil) -> CGRect {
        EditorChrome.place(selection: selection, in: screen ?? self.screen, palette: palette ?? self.palette).palette
    }

    // MARK: the three placements

    func testWithRoomBelowThePaletteIsCentredOnTheAreaFourteenPointsUnderIt() {
        let selection = CGRect(x: 200, y: 100, width: 400, height: 200)
        XCTAssertEqual(place(selection), CGRect(x: 400 - 289, y: 314, width: 578, height: 76))
    }

    func testWithoutRoomBelowThePaletteGoesAboveFourteenPointsFromTheFrame() {
        let selection = CGRect(x: 200, y: 400, width: 400, height: 350) // 50 pt left below the area
        XCTAssertEqual(place(selection), CGRect(x: 111, y: 400 - 14 - 76, width: 578, height: 76))
    }

    func testWithoutRoomOnEitherSideThePaletteIsInsideFourteenPointsFromTheAreasBottomEdge() {
        let selection = CGRect(x: 100, y: 20, width: 800, height: 770) // 10 below, 20 above
        XCTAssertEqual(place(selection), CGRect(x: 211, y: 790 - 14 - 76, width: 578, height: 76))
    }

    func testTheSizeIsReadNotAssumed() {
        let selection = CGRect(x: 300, y: 100, width: 400, height: 200)
        for size in [CGSize(width: 578, height: 76), CGSize(width: 300, height: 120), CGSize(width: 90, height: 40)] {
            XCTAssertEqual(place(selection, palette: size),
                           CGRect(x: 500 - size.width / 2, y: 314, width: size.width, height: size.height), "\(size)")
        }
    }

    // MARK: the boundary: height + 14 + 16

    func testTheBoundaryIsHeightPlusFourteenPlusSixteenOnePointEitherSide() {
        for height in [CGFloat(76), 120] {
            let size = CGSize(width: 578, height: height)
            let room = height + gap + keep
            // Exactly `room` left below: still below. One point less: above. One point more: below.
            let fits = CGRect(x: 200, y: 300, width: 400, height: screen.height - room - 300)
            XCTAssertEqual(screen.height - fits.maxY, room)
            XCTAssertEqual(place(fits, palette: size).minY, fits.maxY + gap, "h=\(height): at the boundary the palette is below")
            let short = CGRect(x: 200, y: 300, width: 400, height: fits.height + 1)
            XCTAssertEqual(place(short, palette: size).minY, short.minY - gap - height, "h=\(height): one point short it is above")
            let roomier = CGRect(x: 200, y: 300, width: 400, height: fits.height - 1)
            XCTAssertEqual(place(roomier, palette: size).minY, roomier.maxY + gap, "h=\(height): one point to spare it is below")
        }
    }

    // MARK: the four screen edges

    func testAtTheLeftEdgeThePaletteIsHeldOnTheScreen() {
        let rect = place(CGRect(x: 0, y: 100, width: 60, height: 100))
        XCTAssertEqual(rect.size, palette)
        XCTAssertEqual(rect.minY, 214)
        XCTAssertTrue((0...16).contains(rect.minX), "off the left edge or not held against it: \(rect)")
    }

    func testAtTheRightEdgeThePaletteIsHeldOnTheScreen() {
        let rect = place(CGRect(x: 940, y: 100, width: 60, height: 100))
        XCTAssertEqual(rect.size, palette)
        XCTAssertEqual(rect.minY, 214)
        XCTAssertTrue((screen.width - palette.width - 16...screen.width - palette.width).contains(rect.minX),
                      "off the right edge or not held against it: \(rect)")
    }

    func testAtTheBottomEdgeAnAreaThatRunsPastItPutsThePaletteInsideAndOnTheScreen() {
        let rect = place(CGRect(x: 100, y: -100, width: 800, height: 1000)) // maxY 900 on an 800 screen
        XCTAssertEqual(rect.size, palette)
        XCTAssertLessThanOrEqual(rect.maxY, screen.height)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertGreaterThan(rect.maxY, screen.height - 40, "held on the bottom edge, not floating up")
    }

    func testAtTheTopEdgeAnAreaThatRunsPastItPutsThePaletteInsideAndOnTheScreen() {
        let small = CGSize(width: 1000, height: 100)
        let rect = place(CGRect(x: 100, y: -200, width: 800, height: 250), screen: small) // maxY 50, minY off the top
        XCTAssertEqual(rect.size, palette)
        XCTAssertGreaterThanOrEqual(rect.minY, 0, "off the top edge: \(rect)")
        XCTAssertTrue(CGRect(origin: .zero, size: small).contains(rect), "\(rect)")
    }

    func testAnAreaAtTheBottomAndInTheCornerGoesAboveAndStaysOnTheScreen() {
        let rect = place(CGRect(x: 960, y: 700, width: 40, height: 100)) // flush to the bottom-right corner
        XCTAssertEqual(rect.minY, 700 - 14 - 76)
        XCTAssertTrue(visible.contains(rect), "\(rect)")
    }

    func testAScreenNarrowerThanThePaletteHoldsItsStartAndNeverMovesBeforeZero() {
        let rect = place(CGRect(x: 10, y: 10, width: 100, height: 100), screen: CGSize(width: 300, height: 800))
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertEqual(rect.size, palette)
    }

    // MARK: the edited display

    func testASelectionOnASecondDisplayStaysOnThePaletteOfThatDisplay() {
        // Points of a display to the right of the main one (past this screen's width) and of one to the left (negative).
        for selection in [CGRect(x: 1400, y: 100, width: 300, height: 200), CGRect(x: -800, y: 100, width: 300, height: 200),
                          CGRect(x: 100, y: 1200, width: 300, height: 200), CGRect(x: 100, y: -900, width: 300, height: 200)] {
            let rect = place(selection)
            XCTAssertEqual(rect.size, palette, "\(selection)")
            XCTAssertTrue(visible.contains(rect), "\(selection): the palette left the edited display: \(rect)")
        }
    }

    func testTheSecondDisplaySelectionInsideItsOwnBoundsIsPlacedByTheSameRule() {
        let wide = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(place(CGRect(x: 800, y: 100, width: 400, height: 200), screen: wide),
                       CGRect(x: 1000 - 289, y: 314, width: 578, height: 76))
    }

    // MARK: not a number, infinity

    func testANonFinitePaletteSizeNeverLeavesANonFiniteOriginOffTheScreen() {
        let selection = CGRect(x: 200, y: 100, width: 400, height: 200)
        let sizes = [CGSize(width: CGFloat.nan, height: 76), CGSize(width: 578, height: CGFloat.nan), CGSize(width: CGFloat.nan, height: CGFloat.nan),
                     CGSize(width: CGFloat.infinity, height: 76), CGSize(width: 578, height: CGFloat.infinity),
                     CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity)]
        for size in sizes {
            let rect = place(selection, palette: size)
            XCTAssertTrue(rect.origin.x.isFinite && rect.origin.y.isFinite, "\(size): the origin is \(rect.origin)")
            XCTAssertTrue(visible.contains(rect.origin), "\(size): the origin \(rect.origin) is off the screen")
        }
    }

    func testANonFiniteSelectionOrScreenNeverLeavesANonFiniteRect() {
        let selections = [CGRect(x: CGFloat.nan, y: 100, width: 400, height: 200), CGRect(x: 200, y: CGFloat.nan, width: 400, height: 200),
                          CGRect(x: 200, y: 100, width: CGFloat.nan, height: 200), CGRect(x: 200, y: 100, width: 400, height: CGFloat.nan),
                          CGRect(x: CGFloat.infinity, y: 100, width: 400, height: 200), CGRect(x: 200, y: -CGFloat.infinity, width: 400, height: 200)]
        for selection in selections {
            let rect = place(selection)
            XCTAssertEqual(rect.size, palette, "\(selection)")
            XCTAssertTrue(visible.contains(rect), "\(selection): \(rect)")
        }
        let rect = place(CGRect(x: 200, y: 100, width: 400, height: 200), screen: CGSize(width: CGFloat.nan, height: CGFloat.nan))
        XCTAssertTrue(rect.origin.x.isFinite && rect.origin.y.isFinite, "a NaN screen gave \(rect)")
    }

    // MARK: covers

    func testCoversIsThePaletteFrameAndNothingElse() {
        let selection = CGRect(x: 200, y: 100, width: 400, height: 200)
        let chrome = EditorChrome.place(selection: selection, in: screen, palette: palette)
        let p = chrome.palette
        XCTAssertEqual(p, CGRect(x: 111, y: 314, width: 578, height: 76))
        XCTAssertTrue(chrome.covers(CGPoint(x: p.midX, y: p.midY)))
        XCTAssertTrue(chrome.covers(p.origin), "the top-left corner is on the palette")
        XCTAssertFalse(chrome.covers(CGPoint(x: p.maxX, y: p.midY)), "the far edge is outside, as CGRect says")
        XCTAssertFalse(chrome.covers(CGPoint(x: p.minX - 1, y: p.midY)))
        XCTAssertFalse(chrome.covers(CGPoint(x: p.midX, y: p.minY - 1)), "the gap between the area and the palette is not the palette")
        XCTAssertFalse(chrome.covers(CGPoint(x: p.midX, y: p.maxY + 1)))
        XCTAssertFalse(chrome.covers(CGPoint(x: selection.midX, y: selection.midY)), "the area itself is not the palette")
        XCTAssertFalse(chrome.covers(CGPoint(x: CGFloat.nan, y: CGFloat.nan)))
    }
}
