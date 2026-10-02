import CoreGraphics
import HelmContract
import XCTest
@testable import Module_Screenshots_Engine

/// **Where a pin opens, how far it scales, how opaque it gets, and where it goes when its display leaves.**
/// Pure arithmetic over AppKit-global points (origin at the lower-left of the primary display).
///
/// Total failure of the subject prints a frame that is not the selection's: a pin a pixel off, a
/// pixel-sized pin 2x too large on a Retina display, a pin hung on the wrong side of the flip when
/// the display sits above or left of the primary, a pin that jumps away from under the pointer when
/// scaled, a window that traps on a display smaller than its own floor, or a pin stranded off every screen.
///
/// The plan's spelling is assumed; `PinGeometry.minimumSide` and `PinGeometry.minimumOpacity` are the
/// two floors the plan calls "N pt" and "floor", named here so a test can read them.
final class ThePinGeometryHoldsAtItsEdgesTests: XCTestCase {

    private let accuracy: CGFloat = 0.001

    private func assertEqual(_ a: CGRect, _ b: CGRect, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: Opening

    /// A 2x display above-left of the primary (CG origin negative on both axes), a selection that
    /// lands between pixels. The expected frame is worked by hand: pixels (20,21,102,61) are points
    /// (10,10.5,51,30.5) from the display's top-left; the display's AppKit frame is y 1080...2160, so
    /// the pin's lower edge is 2160 - 10.5 - 30.5 = 2119.
    func testAPinOpensOnTheSelectionsPixelsOnADisplayWithANegativeOrigin() {
        let frame = PinGeometry.opening(local: CGRect(x: 10.3, y: 10.6, width: 50.3, height: 30.1), scale: 2,
                                        imageWidth: 3840, imageHeight: 2160,
                                        display: CGRect(x: -1920, y: -1080, width: 1920, height: 1080),
                                        primaryHeight: 1080)
        assertEqual(frame, CGRect(x: -1910, y: 2119, width: 51, height: 30.5),
                    "the pin is not where the selection's pixels were, or is a pixel count and not points")
    }

    /// The control on the primary at 1x: size is the selection's own, and the flip uses the primary's height.
    func testAPinOnThePrimaryAtOneXIsTheSelectionFlipped() {
        let frame = PinGeometry.opening(local: CGRect(x: 100, y: 100, width: 400, height: 300), scale: 1,
                                        imageWidth: 1920, imageHeight: 1080,
                                        display: CGRect(x: 0, y: 0, width: 1920, height: 1080), primaryHeight: 1080)
        assertEqual(frame, CGRect(x: 100, y: 680, width: 400, height: 300))
    }

    // MARK: Scale

    private let display = CGRect(x: 0, y: 0, width: 4000, height: 3000)
    private let start = CGRect(x: 1000, y: 1000, width: 400, height: 200)
    private let native = CGSize(width: 400, height: 200)
    private let about = CGPoint(x: 1100, y: 1050)

    private func fractions(_ rect: CGRect, of point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    private func assertAnchored(_ result: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let before = fractions(start, of: about), after = fractions(result, of: about)
        XCTAssertEqual(after.x, before.x, accuracy: 0.001, "the point under the pointer moved horizontally", file: file, line: line)
        XCTAssertEqual(after.y, before.y, accuracy: 0.001, "the point under the pointer moved vertically", file: file, line: line)
        XCTAssertEqual(result.width / result.height, start.width / start.height, accuracy: 0.001, "proportions changed", file: file, line: line)
    }

    /// Positive delta enlarges, negative shrinks (assumed direction), the pointer's point stays put.
    func testScalingKeepsThePointUnderThePointerFixed() throws {
        for precise in [true, false] {
            let up = try XCTUnwrap(PinGeometry.scaled(frame: start, native: native, delta: 3, precise: precise, about: about, display: display))
            XCTAssertGreaterThan(up.width, start.width, "a positive delta did not enlarge (precise \(precise))")
            assertAnchored(up)
            let down = try XCTUnwrap(PinGeometry.scaled(frame: start, native: native, delta: -3, precise: precise, about: about, display: display))
            XCTAssertLessThan(down.width, start.width, "a negative delta did not shrink (precise \(precise))")
            assertAnchored(down)
        }
    }

    /// A bound reached still keeps the point under the pointer: the factor is clamped, not the origin.
    func testTheLowerBoundHoldsAndKeepsTheAnchor() throws {
        XCTAssertTrue((8...64).contains(PinGeometry.minimumSide), "the floor is not a plausible point count")
        let floor = try XCTUnwrap(PinGeometry.scaled(frame: start, native: native, delta: -1_000_000, precise: true, about: about, display: display))
        XCTAssertEqual(min(floor.width, floor.height), PinGeometry.minimumSide, accuracy: 0.01, "the short side did not stop at the floor")
        assertAnchored(floor)
    }

    /// A selection smaller than the floor can never be made bigger than 1:1 by shrinking: its floor is itself.
    func testATinySelectionsFloorIsItsOwnSize() throws {
        let tiny = CGRect(x: 500, y: 500, width: 10, height: 6)
        let result = try XCTUnwrap(PinGeometry.scaled(frame: tiny, native: tiny.size, delta: -1_000_000, precise: true,
                                                      about: CGPoint(x: 505, y: 503), display: display))
        XCTAssertGreaterThanOrEqual(min(result.width, result.height), 6 - 0.001, "a tiny pin shrank below its own size")
        XCTAssertLessThanOrEqual(min(result.width, result.height), 6 + 0.001, "a tiny pin was floored above its own size")
    }

    func testTheUpperBoundFitsTheDisplayAndKeepsTheAnchor() throws {
        let ceiling = try XCTUnwrap(PinGeometry.scaled(frame: start, native: native, delta: 1_000_000, precise: true, about: about, display: display))
        XCTAssertLessThanOrEqual(ceiling.width, display.width + 0.001, "the pin outgrew the display's width")
        XCTAssertLessThanOrEqual(ceiling.height, display.height + 0.001, "the pin outgrew the display's height")
        // It reached a limit, and the limit is the display's: one side fills it.
        XCTAssertTrue(abs(ceiling.width - display.width) < 0.01 || abs(ceiling.height - display.height) < 0.01,
                      "the pin stopped short of the display: \(ceiling)")
        assertAnchored(ceiling)
    }

    /// A display smaller than the floor: the bounds are inverted, and a clamp over them traps.
    /// The ceiling is raised to the floor first, so this answers with a finite frame and does not crash.
    func testInvertedBoundsDoNotTrap() throws {
        let tinyDisplay = CGRect(x: 0, y: 0, width: 5, height: 4)
        for delta in [CGFloat(-1_000_000), 0, 1_000_000] {
            if let result = PinGeometry.scaled(frame: start, native: native, delta: delta, precise: true, about: about, display: tinyDisplay) {
                XCTAssertTrue(result.width.isFinite && result.height.isFinite && result.minX.isFinite && result.minY.isFinite, "\(result)")
                XCTAssertGreaterThan(result.width, 0)
            }
        }
    }

    /// Not a number or infinite: no change at all. nil is the answer, and the caller keeps the frame it had.
    func testANonFiniteDeltaChangesNothing() {
        for delta in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertNil(PinGeometry.scaled(frame: start, native: native, delta: delta, precise: false, about: about, display: display),
                         "delta \(delta) produced a frame")
        }
        // A pointer that is not a point cannot move the pin either: nil or the frame itself.
        let result = PinGeometry.scaled(frame: start, native: native, delta: 1, precise: false,
                                        about: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), display: display)
        XCTAssertTrue(result == nil || result == start, "a non-finite anchor moved the pin: \(String(describing: result))")
    }

    // MARK: Opacity

    func testOpacityClampsToTheFloorAndOne() throws {
        XCTAssertTrue((0.05...0.5).contains(PinGeometry.minimumOpacity), "the floor is not a plausible opacity")
        XCTAssertEqual(try XCTUnwrap(PinGeometry.opacity(0.8, delta: -1_000_000, precise: true)), PinGeometry.minimumOpacity, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(PinGeometry.opacity(0.8, delta: 1_000_000, precise: true)), 1, accuracy: 0.0001)
        let up = try XCTUnwrap(PinGeometry.opacity(0.5, delta: 1, precise: false))
        XCTAssertGreaterThan(up, 0.5, "a positive delta did not raise the opacity")
        XCTAssertLessThanOrEqual(up, 1)
        let down = try XCTUnwrap(PinGeometry.opacity(0.5, delta: -1, precise: false))
        XCTAssertLessThan(down, 0.5)
        XCTAssertGreaterThanOrEqual(down, PinGeometry.minimumOpacity)
    }

    func testANonFiniteDeltaLeavesTheOpacityAlone() {
        for delta in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertNil(PinGeometry.opacity(0.5, delta: delta, precise: false), "delta \(delta) produced an opacity")
        }
    }

    // MARK: Rehoming

    private let a = (id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    private let b = (id: DisplayID(2), frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))

    func testAPinWhollyOnOneScreenStaysWhereItIs() {
        let pin = CGRect(x: 1200, y: 100, width: 300, height: 200)
        assertEqual(PinGeometry.rehome(frame: pin, native: pin.size, screens: [a, b]), pin)
    }

    /// 100 points on A and 300 on B: it goes whole to B, its size untouched because it fits.
    func testAPinAcrossTwoScreensGoesToTheOneHoldingMostOfIt() {
        let pin = CGRect(x: 900, y: 100, width: 400, height: 200)
        let home = PinGeometry.rehome(frame: pin, native: pin.size, screens: [a, b])
        XCTAssertTrue(b.frame.contains(home), "\(home) is not wholly on the screen holding most of it")
        XCTAssertEqual(home.width, 400, accuracy: accuracy)
        XCTAssertEqual(home.height, 200, accuracy: accuracy)
    }

    /// Larger than any screen: shrunk keeping proportions and pushed inside.
    func testAPinTooBigForItsScreenShrinksKeepingItsProportions() {
        let pin = CGRect(x: -100, y: 0, width: 2000, height: 1000)
        let home = PinGeometry.rehome(frame: pin, native: pin.size, screens: [a, b])
        XCTAssertTrue(a.frame.contains(home), "\(home) is not on A, which held the larger part")
        XCTAssertEqual(home.width / home.height, 2, accuracy: 0.001, "proportions changed")
    }

    /// Entirely off every screen: the first screen of the list — the list's own order, not the nearest.
    func testAPinOnNoScreenGoesToTheFirstOne() {
        let pin = CGRect(x: 50_000, y: 50_000, width: 200, height: 100)
        let home = PinGeometry.rehome(frame: pin, native: pin.size, screens: [b, a])
        XCTAssertTrue(b.frame.contains(home), "\(home) is not on the first screen of the list")
        assertEqual(CGRect(origin: .zero, size: home.size), CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    /// No screens at all (every display gone for a moment): no trap, and nothing made up.
    func testNoScreensLeavesThePinAlone() {
        let pin = CGRect(x: 10, y: 10, width: 200, height: 100)
        assertEqual(PinGeometry.rehome(frame: pin, native: pin.size, screens: []), pin)
    }

    func testThereAreAtMostEightPins() {
        XCTAssertEqual(PinGeometry.limit, 8)
    }
}
