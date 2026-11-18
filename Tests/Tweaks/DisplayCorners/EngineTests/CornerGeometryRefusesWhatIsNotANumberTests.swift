import CoreGraphics
import XCTest
@testable import Tweak_DisplayCorners_Engine

/// **A value that came from a file, a display driver or the system is not always a number.**
///
/// Each test feeds `Logic` code NaN, infinity or a value out of range. Nothing may trap; where a test
/// asserts the answer, it is a finite value, nil (no correction) or no mask, and the motion clock's masks
/// stay unrounded until the settle wait has passed.
final class CornerGeometryRefusesWhatIsNotANumberTests: XCTestCase {
    private let awkward: [CGFloat] = [.nan, .infinity, -.infinity, 0, -1, 1e300, .leastNonzeroMagnitude]

    private func display(scale: CGFloat = 2, ppp: CGFloat = 2, frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982),
                         fps: Int = 120) -> DisplayDescriptor {
        DisplayDescriptor(id: 1, frame: frame, quartzBounds: frame, backingScale: scale, pixelsPerPoint: ppp,
                          isBuiltIn: true, isMirrored: false, maxFPS: fps)
    }

    func testNoRadiusScaleOrFrameTrapsTheLayout() {
        let settings = CornerSettings(builtIn: true, external: true, radiusPixels: 28)
        for value in awkward {
            for specs in [
                LayoutDecision.decide(displays: [display(ppp: value)], settings: settings, calibration: nil),
                LayoutDecision.decide(displays: [display(scale: value)], settings: settings, calibration: nil),
                LayoutDecision.decide(displays: [display(frame: CGRect(x: value, y: value, width: value, height: value))],
                                      settings: settings, calibration: nil),
            ] {
                for spec in specs {
                    XCTAssertTrue(spec.radius.isFinite && spec.radius > 0, "\(value): radius \(spec.radius)")
                    XCTAssertTrue(spec.frame.width.isFinite && spec.frame.width > 0 && spec.frame.origin.x.isFinite,
                                  "\(value): frame \(spec.frame)")
                    XCTAssertTrue(spec.backingScale.isFinite && spec.backingScale > 0)
                }
            }
            XCTAssertEqual(CornerFrames.size(radius: value) == 0 || CornerFrames.size(radius: value) <= CornerFrames.largestSize,
                           true, "size for \(value)")
        }
        let radii: [Double] = [.nan, .infinity, -.infinity, 0, -5, 1e300]
        for radius in radii {
            let specs = LayoutDecision.decide(displays: [display()],
                                              settings: CornerSettings(builtIn: true, external: true, radiusPixels: radius),
                                              calibration: nil)
            for spec in specs { XCTAssertTrue(spec.radius.isFinite && spec.frame.width <= CornerFrames.largestSize) }
        }
    }

    /// A clock sample that is not a finite number, after a finite one, is not rounded and leaves no trace:
    /// the next at-rest sample waits out `settle` from the last finite motion instead of rounding at once.
    func testAClockThatIsNotFiniteDoesNotShortenTheSettleWait() {
        for bad in [-TimeInterval.infinity, .infinity, .nan] {
            var motion = DisplayMotion()
            XCTAssertEqual(motion.update(atRest: false, now: 10), false, "\(bad): motion at 10")
            XCTAssertEqual(motion.update(atRest: true, now: bad), nil, "\(bad): stays unrounded")
            XCTAssertNil(motion.update(atRest: true, now: 10.01), "\(bad): 0.01 s after the motion must not round")
            XCTAssertFalse(motion.rounded, "\(bad)")
            XCTAssertEqual(motion.update(atRest: true, now: 10.06), true, "\(bad): 0.06 s after the motion rounds")
        }
    }

    func testAHugeRadiusMakesABoundedWindow() {
        let specs = LayoutDecision.decide(displays: [display(ppp: 1e-9)],
                                          settings: CornerSettings(builtIn: true, external: false, radiusPixels: 128),
                                          calibration: nil)
        XCTAssertFalse(specs.isEmpty)
        for spec in specs { XCTAssertLessThanOrEqual(spec.frame.width, CornerFrames.largestSize) }
    }

    func testAModeWithZeroPixelsFallsBackToTheBackingScale() {
        let modes = [DisplayModeInfo(pixelWidth: 0, pixelHeight: 0, isNative: true),
                     DisplayModeInfo(pixelWidth: 3024, pixelHeight: 0, isNative: true)]
        XCTAssertEqual(PixelsPerPoint.resolve(modes: modes, pointSize: CGSize(width: 1512, height: 982), backing: 2), 2)
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 982), CGSize(width: CGFloat.infinity, height: CGFloat.infinity)] {
            XCTAssertEqual(PixelsPerPoint.resolve(modes: modes, pointSize: size, backing: 2), 2)
        }
        XCTAssertEqual(PixelsPerPoint.resolve(modes: [], pointSize: CGSize(width: 10, height: 10), backing: .nan), 1)
    }

    func testTheCorrectionRefusesWhatIsNotANumber() {
        let geometry = CornerGeometry(size: 28, radius: 14, corner: .bottomLeft, constrainsCursor: true)
        let rested = MaskPresentation(scale: 1, opacity: 1, ready: true)
        for value in [CGFloat.nan, .infinity] {
            XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: value, y: 1), remainder: .zero,
                                                  geometry: geometry, presentation: rested))
            XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: CGPoint(x: value, y: 0),
                                                  geometry: geometry, presentation: rested))
            XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: geometry,
                                                  presentation: MaskPresentation(scale: value, opacity: 1, ready: true)))
        }
        let broken = CornerGeometry(size: .nan, radius: .nan, corner: .topRight, constrainsCursor: true)
        _ = CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: broken, presentation: rested)
    }

    func testTheRadiusBoundsHoldForWhatIsNotANumber() {
        for stored in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(RadiusMath.pixels(stored: stored, scale: 2), 28)
            XCTAssertEqual(RadiusMath.stepped(stored, direction: 1, scale: 2), 28)
        }
        XCTAssertEqual(RadiusMath.pixels(stored: 1e9, scale: 2), 128)
        XCTAssertEqual(RadiusMath.pixels(stored: -3, scale: 2), 0.5)
        XCTAssertEqual(RadiusMath.defaultPixels(scale: .nan), 14)
        XCTAssertEqual(RadiusMath.preset(points: 32, scale: .infinity), 14)
        XCTAssertEqual(RadiusMath.points(pixels: 28, pixelsPerPoint: .nan), 0)
        XCTAssertEqual(RadiusScale.reference(builtInNow: .nan, remembered: 0, main: .infinity), 1)
    }

    func testTheCalibrationClampHolds() {
        let colour = CalibrationColour(clamping: 1.4, -0.2, 0.5)
        XCTAssertEqual([colour.red, colour.green, colour.blue], [1, 0, 0.5])
        let broken = CalibrationColour(clamping: .nan, .infinity, 0.25)
        XCTAssertEqual([broken.red, broken.green, broken.blue], [1, 0.32, 0.25],
                       "a channel that is not a number takes the default's; the others keep theirs")
    }
}
