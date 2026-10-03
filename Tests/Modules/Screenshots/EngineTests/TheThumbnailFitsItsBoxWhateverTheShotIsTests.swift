import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The after-shot picture's size is one pure function of the shot's pixels, and it fits its box whatever the shot
/// is.** `ShotThumbnail.fitted` reduces to `maxWidth` by `maxHeight` with the proportions kept, never enlarges, and
/// answers a size that is not a number, has no area, or is endless with a finite, positive one: the view, the panel
/// and the drag's frame all take this answer, and a NaN or zero in it would be a zero-sized window or a frame the
/// layout cannot place.
///
/// Total failure of the subject prints: a picture that overflows its box, a small shot blown up, a squashed
/// aspect, or a non-finite size handed to a window.
final class TheThumbnailFitsItsBoxWhateverTheShotIsTests: XCTestCase {

    private let box = CGSize(width: ShotThumbnail.maxWidth, height: ShotThumbnail.maxHeight)

    private func fitted(_ width: CGFloat, _ height: CGFloat) -> CGSize {
        ShotThumbnail.fitted(pixels: CGSize(width: width, height: height))
    }

    /// The box and the edge this file's numbers are written against: a changed constant fails here in its own words.
    func testTheBoxIsTheMockupsAndTheCopyIsBiggerThanTheBox() {
        XCTAssertEqual(box, CGSize(width: 200, height: 126))
        XCTAssertEqual(ShotThumbnail.longestEdge, 520)
        XCTAssertGreaterThan(ShotThumbnail.longestEdge, ShotThumbnail.maxWidth, "the copy the window holds is smaller than what it draws")
    }

    func testALandscapeShotIsHeldByTheWidth() {
        // 1600 × 900: the width asks for 1/8, the height for 0.14: the width is the tighter.
        let size = fitted(1600, 900)
        XCTAssertEqual(size.width, 200, accuracy: 1e-9)
        XCTAssertEqual(size.height, 112.5, accuracy: 1e-9)
    }

    func testAPortraitShotIsHeldByTheHeight() {
        let size = fitted(900, 1600)
        XCTAssertEqual(size.height, 126, accuracy: 1e-9)
        XCTAssertEqual(size.width, 126 * 900 / 1600, accuracy: 1e-9)
    }

    /// A strip: 100 times wider than tall is 200 wide and two high; a column the other way round.
    func testAStripAndAColumnKeepTheirProportion() {
        let strip = fitted(10_000, 100)
        XCTAssertEqual(strip.width, 200, accuracy: 1e-9)
        XCTAssertEqual(strip.height, 2, accuracy: 1e-9)
        let column = fitted(100, 10_000)
        XCTAssertEqual(column.height, 126, accuracy: 1e-9)
        XCTAssertEqual(column.width, 1.26, accuracy: 1e-9)
    }

    /// Below the box the shot stands as it is: a thumbnail is never enlarged.
    func testATinyShotIsNotEnlarged() {
        XCTAssertEqual(fitted(40, 30), CGSize(width: 40, height: 30))
        XCTAssertEqual(fitted(1, 1), CGSize(width: 1, height: 1))
        XCTAssertEqual(fitted(199, 125), CGSize(width: 199, height: 125))
        XCTAssertEqual(fitted(200, 50), CGSize(width: 200, height: 50))
    }

    /// Exactly the box is the box; one pixel over in either direction is reduced, and by the tighter side.
    func testTheBoxItselfIsUntouchedAndOnePixelOverIsReduced() {
        XCTAssertEqual(fitted(200, 126), box)
        let wider = fitted(201, 126)
        XCTAssertLessThan(wider.width, 200.0 + 1e-9)
        XCTAssertLessThan(wider.width, 201)
        XCTAssertEqual(wider.width / wider.height, 201.0 / 126.0, accuracy: 1e-9)
        let taller = fitted(200, 127)
        XCTAssertLessThan(taller.height, 127)
        XCTAssertLessThanOrEqual(taller.height, 126 + 1e-9)
        XCTAssertEqual(taller.width / taller.height, 200.0 / 127.0, accuracy: 1e-9)
    }

    /// The structure, over a grid of shapes and sizes: it fits, never grows, and keeps its aspect (a scale applied
    /// to both sides), and the box is touched on at least one side when anything was reduced.
    func testEveryShotFitsNeverGrowsAndKeepsItsAspect() {
        let sides: [CGFloat] = [1, 2, 3, 30, 125, 126, 127, 199, 200, 201, 520, 1000, 1440, 2560, 5120, 16_000]
        var asked = 0
        for width in sides {
            for height in sides {
                let size = fitted(width, height)
                let context = "\(width)×\(height) -> \(size)"
                XCTAssertLessThanOrEqual(size.width, ShotThumbnail.maxWidth + 1e-9, context)
                XCTAssertLessThanOrEqual(size.height, ShotThumbnail.maxHeight + 1e-9, context)
                XCTAssertLessThanOrEqual(size.width, width + 1e-9, "enlarged: \(context)")
                XCTAssertLessThanOrEqual(size.height, height + 1e-9, "enlarged: \(context)")
                XCTAssertGreaterThan(size.width, 0, context)
                XCTAssertGreaterThan(size.height, 0, context)
                XCTAssertEqual(size.width / size.height, width / height, accuracy: 1e-9 * max(1, width / height), "aspect: \(context)")
                if size.width < width - 1e-9 {
                    let touches = abs(size.width - ShotThumbnail.maxWidth) < 1e-9 || abs(size.height - ShotThumbnail.maxHeight) < 1e-9
                    XCTAssertTrue(touches, "reduced but touches neither side of the box: \(context)")
                }
                asked += 1
            }
        }
        XCTAssertEqual(asked, sides.count * sides.count)
    }

    /// No area: one point on that side, and the other side is read as it is (and then reduced by the box).
    func testZeroAndNegativeAreOnePointOnThatSide() {
        XCTAssertEqual(fitted(0, 0), CGSize(width: 1, height: 1))
        XCTAssertEqual(fitted(-5, -5), CGSize(width: 1, height: 1))
        XCTAssertEqual(fitted(0, 100), CGSize(width: 1, height: 100))
        XCTAssertEqual(fitted(100, 0), CGSize(width: 100, height: 1))
        XCTAssertEqual(fitted(-1, 50), CGSize(width: 1, height: 50))
        let tall = fitted(0, 1000)
        XCTAssertEqual(tall.height, 126, accuracy: 1e-9, "a side of no width is not a reason to leave the box")
        XCTAssertGreaterThan(tall.width, 0)
        XCTAssertEqual(fitted(-.infinity, -.infinity), CGSize(width: 1, height: 1))
    }

    func testNotANumberIsOnePointOnThatSide() {
        XCTAssertEqual(fitted(.nan, .nan), CGSize(width: 1, height: 1))
        XCTAssertEqual(fitted(.nan, 100), CGSize(width: 1, height: 100))
        XCTAssertEqual(fitted(100, .nan), CGSize(width: 100, height: 1))
        let size = fitted(.nan, 5000)
        XCTAssertTrue(size.width.isFinite && size.height.isFinite)
        XCTAssertLessThanOrEqual(size.height, 126 + 1e-9)
    }

    /// An endless side is bounded, never zero times infinity: the answer is finite, in the box, and endless on both
    /// sides is the box's own aspect.
    func testInfinityIsBoundedAndTheAnswerStaysInTheBox() {
        for (width, height) in [(CGFloat.infinity, 100), (100, .infinity), (.infinity, .infinity), (.infinity, 1), (1, .infinity),
                                (.greatestFiniteMagnitude, .greatestFiniteMagnitude)] as [(CGFloat, CGFloat)] {
            let size = fitted(width, height)
            let context = "\(width)×\(height) -> \(size)"
            XCTAssertTrue(size.width.isFinite && size.height.isFinite, context)
            XCTAssertGreaterThan(size.width, 0, context)
            XCTAssertGreaterThan(size.height, 0, context)
            XCTAssertLessThanOrEqual(size.width, 200 + 1e-9, context)
            XCTAssertLessThanOrEqual(size.height, 126 + 1e-9, context)
        }
        XCTAssertEqual(fitted(.infinity, .infinity).width, 126, accuracy: 1e-9, "a square of endless sides is the box's tighter side")
        XCTAssertEqual(fitted(.infinity, .infinity).height, 126, accuracy: 1e-9)
    }
}
