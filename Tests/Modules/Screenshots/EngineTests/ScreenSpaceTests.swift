import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// AppKit's origin is the lower-left of the primary display and CG's is its
/// upper-left. They differ by a flip of y, and a display above or left of the
/// primary is where an unflipped crop becomes a picture of a different part of
/// the desk.
final class ScreenSpaceTests: XCTestCase {

    /// The primary is 1920×1080; a second display sits left of it and one row up,
    /// so its CG frame has negative x **and** negative y.
    private let primaryHeight: CGFloat = 1080
    private let aboveLeftCG = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

    func testADisplayAboveThePrimaryIsAboveInAppKitToo() {
        let appKit = ScreenSpace.appKitRect(fromCG: aboveLeftCG, primaryHeight: primaryHeight)
        XCTAssertEqual(appKit, CGRect(x: -1920, y: 1080, width: 1920, height: 1080),
                       "the display above the primary was not placed above it: the y flip is missing")
    }

    func testTheFlipIsItsOwnInverse() {
        let rect = CGRect(x: 40, y: 70, width: 300, height: 200)
        let round = ScreenSpace.cgRect(fromAppKit: ScreenSpace.appKitRect(fromCG: rect, primaryHeight: primaryHeight),
                                       primaryHeight: primaryHeight)
        XCTAssertEqual(round, rect)
    }

    func testThePointerOnTheUpperDisplayHasANegativeCGY() {
        // AppKit: 200 points into the display that is above the primary.
        let appKitPoint = CGPoint(x: -1000, y: 1080 + 1080 - 200)
        let cg = ScreenSpace.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        XCTAssertEqual(cg, CGPoint(x: -1000, y: -880))
        XCTAssertTrue(aboveLeftCG.contains(cg), "the pointer is not inside the display it is on")
    }

    func testAWindowOnTheUpperDisplayIsLocalToItAndCutFromTheRightPlace() {
        let window = CGRect(x: -1900, y: -1000, width: 400, height: 300)
        let local = ScreenSpace.local(window, in: aboveLeftCG)
        XCTAssertEqual(local, CGRect(x: 20, y: 80, width: 400, height: 300))
        XCTAssertEqual(ScreenSpace.global(local, in: aboveLeftCG), window)
    }

    func testPixelsAreRoundedOutwardAndClampedIntoTheImage() {
        let pixels = ScreenSpace.pixels(ofLocal: CGRect(x: 10.3, y: 10.6, width: 50.3, height: 30.1),
                                        scale: 2, imageWidth: 200, imageHeight: 100)
        // Every edge lands between two pixels: 20.6 and 121.2 across, 21.2 and 81.4 down.
        XCTAssertEqual(pixels, CGRect(x: 20, y: 21, width: 102, height: 61))
        let edge = ScreenSpace.pixels(ofLocal: CGRect(x: 90, y: 40, width: 50, height: 50),
                                      scale: 2, imageWidth: 200, imageHeight: 100)
        XCTAssertEqual(edge, CGRect(x: 180, y: 80, width: 20, height: 20), "the crop ran past the last pixel")
    }

    func testASelectionWhollyOutsideOrNotANumberIsNothing() {
        XCTAssertNil(ScreenSpace.pixels(ofLocal: CGRect(x: 500, y: 500, width: 10, height: 10), scale: 2, imageWidth: 200, imageHeight: 100))
        XCTAssertNil(ScreenSpace.pixels(ofLocal: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), scale: 2, imageWidth: 200, imageHeight: 100))
        XCTAssertNil(ScreenSpace.pixels(ofLocal: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 0, imageWidth: 200, imageHeight: 100))
    }

    /// The whole chain on a real image: a crop at the bottom-right corner of a
    /// picture that is red on the left and blue on the right comes out blue.
    func testACropTakesTheRightPixels() {
        let image = makeSplitImage(width: 200, height: 100)
        let pixels = ScreenSpace.pixels(ofLocal: CGRect(x: 60, y: 10, width: 30, height: 20), scale: 2,
                                        imageWidth: image.width, imageHeight: image.height)!
        let cut = image.cropping(to: pixels)!
        XCTAssertGreaterThan(firstPixel(cut).2, 200, "not the blue half")
        XCTAssertLessThan(firstPixel(cut).0, 40, "the red half leaked in")
    }
}
