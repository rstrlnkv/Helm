import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A box Vision gives lands on the pixels of the frame the text is on**, and the box that hides it is wider
/// than the text and made of whole mosaic blocks.
///
/// The area read is 400 × 200 pixels at (100, 50) of a 2× display. Vision's rectangle is a fraction of what it
/// was given, its origin at the **lower** left; the layers are in the display's points, the origin at the top
/// left. Every number below is worked out by hand in the comment beside it.
final class TheRecognizedBoxesLandOnTheFramesPixelsTests: XCTestCase {

    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 100, y: 50, width: 400, height: 200), scale: 2)

    /// x 0.25 → 100 px across the read; top = 1 − (0.5 + 0.1) = 0.4 → 80 px down; 200 × 20 px. In the frame: add
    /// (100, 50) → (200, 130). In points: (100, 65, 100, 10).
    func testTheTextsOwnBoxIsTheFramesPixelsInPoints() throws {
        let ink = try XCTUnwrap(RecognizedBoxes.ink(of: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1), in: source))
        XCTAssertEqual(ink, CGRect(x: 100, y: 65, width: 100, height: 10))
    }

    /// The origin turns over: a box at the bottom of what was read is at the bottom of the area on the display.
    /// y 0 → 1 − 0.1 = 0.9 → 180 px down, in the frame 230 → 115 points.
    func testTheLowerLeftOriginIsTurnedOver() throws {
        let low = try XCTUnwrap(RecognizedBoxes.ink(of: CGRect(x: 0, y: 0, width: 0.5, height: 0.1), in: source))
        let high = try XCTUnwrap(RecognizedBoxes.ink(of: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.1), in: source))
        XCTAssertEqual(low.minY, 115)
        XCTAssertEqual(high.minY, 25, "the top of what was read is the top of the area: 50 px in the frame, 25 points")
        XCTAssertGreaterThan(low.minY, high.minY)
    }

    /// The text is 10 points high, so the step is the first (a block of 10 points is 20 px at 2×). Padding is
    /// half a height across (10 px) and a quarter up and down (5 px): (190, 125)–(410, 155) in the frame. Out to
    /// the 20 px grid: left 180, top 120, right 420, bottom 160 → in points (90, 60, 120, 20).
    func testTheBoxThatHidesIsPaddedAndRoundedOutToTheMosaicGrid() throws {
        let placed = try XCTUnwrap(RecognizedBoxes.place(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1), in: source))
        XCTAssertEqual(placed.step, .thin)
        XCTAssertEqual(placed.rect, CGRect(x: 90, y: 60, width: 120, height: 20))
    }

    /// Whatever the text and wherever it is: the box holds the whole text, grows it on every side the area allows,
    /// and its edges are on the grid of the step it was given or on the area's own edge. A partial block at an
    /// edge of the box would cut a glyph.
    func testEveryBoxHoldsItsTextAndStandsOnTheGrid() throws {
        var checked = 0
        for width in [0.05, 0.2, 0.6] {
            for height in [0.04, 0.09, 0.2] {
                for x in [0.0, 0.13, 0.4] {
                    for y in [0.0, 0.31, 0.77] {
                        let box = CGRect(x: x, y: y, width: width, height: height)
                        guard let ink = RecognizedBoxes.ink(of: box, in: source),
                              let placed = RecognizedBoxes.place(box, in: source) else { continue }
                        checked += 1
                        XCTAssertTrue(placed.rect.contains(ink), "\(box): \(placed.rect) does not hold \(ink)")
                        let side = CGFloat(Pixelate.block(points: placed.step.points(for: .blur), scale: 2))
                        let pixels = CGRect(x: placed.rect.minX * 2, y: placed.rect.minY * 2,
                                            width: placed.rect.width * 2, height: placed.rect.height * 2)
                        for (edge, limit) in [(pixels.minX, source.pixels.minX), (pixels.maxX, source.pixels.maxX),
                                              (pixels.minY, source.pixels.minY), (pixels.maxY, source.pixels.maxY)] {
                            let onGrid = edge.truncatingRemainder(dividingBy: side) == 0
                            XCTAssertTrue(onGrid || edge == limit, "\(box): an edge at \(edge) is on neither the \(side) px grid nor the area's")
                        }
                        XCTAssertTrue(source.pixels.contains(pixels), "\(box) leaves the area: \(pixels)")
                        if ink.minX * 2 - 1 > source.pixels.minX + side && ink.maxX * 2 + 1 < source.pixels.maxX - side {
                            XCTAssertGreaterThan(placed.rect.width, ink.width, "\(box): the box is as wide as the text and shows its length")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 40, "the walk found almost nothing to check, so a pass means little")
    }

    /// A box wholly beyond the read picture, an empty one and one that is not a number are no box.
    func testWhatIsNotOnTheReadPictureIsNoBox() {
        let rects = [CGRect(x: 1.2, y: 0.2, width: 0.1, height: 0.1), CGRect(x: 0.2, y: 0.2, width: 0, height: 0.1),
                     CGRect(x: CGFloat.nan, y: 0.2, width: 0.1, height: 0.1), CGRect(x: 0.2, y: 0.2, width: CGFloat.infinity, height: 0.1),
                     CGRect(x: -0.5, y: 0.2, width: 0.4, height: 0.1)]
        for rect in rects {
            XCTAssertNil(RecognizedBoxes.ink(of: rect, in: source), "\(rect)")
            XCTAssertNil(RecognizedBoxes.place(rect, in: source), "\(rect)")
        }
        let none = RecognizedBoxes.Source(pixels: .zero, scale: 2)
        let notAScale = RecognizedBoxes.Source(pixels: source.pixels, scale: .nan)
        XCTAssertNil(RecognizedBoxes.place(CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2), in: none))
        XCTAssertNil(RecognizedBoxes.place(CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2), in: notAScale))
    }

    /// A text that starts before the picture is kept to the part that is on it, and a box at the edge of the area
    /// is kept to the area: the file is cut there.
    func testABoxAtTheEdgeIsKeptToTheArea() throws {
        let edge = CGRect(x: -0.05, y: 0.45, width: 0.2, height: 0.1)
        let ink = try XCTUnwrap(RecognizedBoxes.ink(of: edge, in: source))
        XCTAssertEqual(ink.minX, 50, "the area's left edge, 100 px in the frame")
        let placed = try XCTUnwrap(RecognizedBoxes.place(edge, in: source))
        XCTAssertEqual(placed.rect.minX, 50)
    }

    /// The step an automatic blur takes comes from the height of the text, not from the one the editor remembers:
    /// the smallest of 10, 16 and 24 points that is at least as high as the text, the thickest when none is.
    func testTheStepIsTheSmallestBlockAsHighAsTheText() {
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 5), .thin)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 10), .thin, "a block of exactly the height is enough")
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 10.5), .medium)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 13), .medium, "13 point digits under a 10 point block can be read back")
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 16), .medium)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 17), .thick)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 24), .thick)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: 60), .thick, "no block is high enough: the thickest")
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: .nan), .thick)
        XCTAssertEqual(RecognizedBoxes.step(forTextHeight: .infinity), .thick)
    }

    /// The step reaches the box: a taller text gets a coarser grid, and the box is on that grid.
    func testATallerTextGetsACoarserBlockAndABoxOnIt() throws {
        // 24 px of text at 2× is 12 points: medium (16 points = 32 px).
        let tall = CGRect(x: 0.3, y: 0.4, width: 0.3, height: 0.12)
        let placed = try XCTUnwrap(RecognizedBoxes.place(tall, in: source))
        XCTAssertEqual(placed.step, .medium)
        XCTAssertEqual((placed.rect.minX * 2).truncatingRemainder(dividingBy: 32), 0)
        XCTAssertEqual((placed.rect.maxY * 2).truncatingRemainder(dividingBy: 32), 0)
    }
}
