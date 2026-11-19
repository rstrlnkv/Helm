import CoreGraphics
import XCTest
@testable import Tweak_DisplayCorners_Engine

/// The pure parts of Display Corners: path, boundary, correction, motion rule, layout decision, radius.
final class CornerLogicTests: XCTestCase {
    private func display(_ id: UInt32, _ frame: CGRect, builtIn: Bool = true, mirrored: Bool = false,
                         ppp: CGFloat = 2, fps: Int = 120) -> DisplayDescriptor {
        DisplayDescriptor(id: id, frame: frame, quartzBounds: CGRect(x: frame.minX, y: 0, width: frame.width, height: frame.height),
                          backingScale: 2, pixelsPerPoint: ppp, isBuiltIn: builtIn, isMirrored: mirrored, maxFPS: fps)
    }
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let on = CornerSettings(builtIn: true, external: true, radiusPixels: 28)

    func testThePathCutsTheCornerAndKeepsTheRest() {
        for corner in CornerPosition.allCases {
            let path = CornerPath.visible(size: 28, radius: 14, corner: corner)
            let nearCorner = CGPoint(x: corner.isRight ? 27.5 : 0.5, y: corner.isTop ? 27.5 : 0.5)
            let farFromCorner = CGPoint(x: corner.isRight ? 0.5 : 27.5, y: corner.isTop ? 0.5 : 27.5)
            XCTAssertFalse(path.contains(nearCorner), "\(corner)")
            XCTAssertTrue(path.contains(farFromCorner), "\(corner)")
        }
        XCTAssertTrue(CornerPath.visible(size: 28, radius: 0, corner: .bottomLeft).contains(CGPoint(x: 0.1, y: 0.1)),
                      "no radius is no rounding")
    }

    func testTheBoundaryIsOnTheCurve() {
        let path = CornerPath.visible(size: 28, radius: 14, corner: .bottomLeft)
        let closest = CursorBoundary(path).closestPoint(to: CGPoint(x: 0, y: 0))
        XCTAssertFalse(path.contains(CGPoint(x: 0, y: 0)))
        XCTAssertLessThan(hypot(closest.x - 3, closest.y - 3), 4, "the diagonal point of a radius 14 curve is near 4,4")
    }

    func testTheFramesFlipAndKeepNegativeOrigins() {
        XCTAssertEqual(CornerFrames.size(radius: 13.2), 27)
        let display = CGRect(x: -1512, y: 100, width: 1512, height: 982)
        let window = CornerFrames.windowFrame(display: display, size: 28, corner: .bottomRight)
        XCTAssertEqual(window, CGRect(x: -28, y: 100, width: 28, height: 28))
        let quartz = CornerFrames.restingQuartzFrame(window: window, display: display,
                                                     quartzBounds: CGRect(x: -1512, y: -200, width: 1512, height: 982))
        XCTAssertEqual(quartz, CGRect(x: -28, y: -200 + 982 - 28, width: 28, height: 28))
    }

    func testThePointerInTheCornerIsPutOnTheCurve() throws {
        let geometry = CornerGeometry(size: 28, radius: 14, corner: .bottomLeft, constrainsCursor: true)
        let rested = MaskPresentation(scale: 1, opacity: 1, ready: true)
        let hit = try XCTUnwrap(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero,
                                                         geometry: geometry, presentation: rested))
        XCTAssertTrue(geometry.visible.contains(hit.position))
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 20, y: 20), remainder: .zero, geometry: geometry,
                                              presentation: rested), "on the visible part there is nothing to correct")
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: geometry,
                                              presentation: MaskPresentation(scale: 1, opacity: 1, ready: false)))
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: geometry,
                                              presentation: MaskPresentation(scale: 0, opacity: 1, ready: true)))
        let calibration = CornerGeometry(size: 28, radius: 14, corner: .bottomLeft, constrainsCursor: false)
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: calibration,
                                              presentation: rested))
        XCTAssertTrue(CursorContact(window: 1, position: CGPoint(x: 5, y: 5), remainder: .zero).isNear(CGPoint(x: 7, y: 3)))
        XCTAssertFalse(CursorContact(window: 1, position: CGPoint(x: 5, y: 5), remainder: .zero).isNear(CGPoint(x: 7.1, y: 5)))
    }

    func testTheMotionRuleSettlesAfterFiftyMilliseconds() {
        var motion = DisplayMotion()
        XCTAssertNil(motion.update(atRest: true, now: 100), "starts rounded")
        XCTAssertEqual(motion.update(atRest: false, now: 100), false)
        XCTAssertNil(motion.update(atRest: true, now: 100.04))
        XCTAssertEqual(motion.update(atRest: true, now: 100.06), true)
        XCTAssertEqual(SamplingRate.next(unsettled: false, maxFPS: 120), 20, "finding 4: slow at rest")
        XCTAssertEqual(SamplingRate.next(unsettled: true, maxFPS: 120), 120)
        XCTAssertEqual(SamplingRate.next(unsettled: true, maxFPS: 30), 60)
        XCTAssertEqual(SamplingRate.next(unsettled: true, maxFPS: 500), 120)
    }

    func testBuiltInGetsTheBottomExternalAllFourAndMirroredNone() {
        let external = display(2, CGRect(x: 1512, y: 0, width: 1920, height: 1080), builtIn: false)
        let mirrored = display(3, CGRect(x: 0, y: 2000, width: 800, height: 600), builtIn: false, mirrored: true)
        let specs = LayoutDecision.decide(displays: [display(1, screen), external, mirrored], settings: on, calibration: nil)
        XCTAssertEqual(specs.filter { $0.key.display == 1 }.map(\.key.corner), [.bottomLeft, .bottomRight])
        XCTAssertEqual(specs.filter { $0.key.display == 2 }.count, 4)
        XCTAssertTrue(specs.filter { $0.key.display == 3 }.isEmpty)
        let off = LayoutDecision.decide(displays: [display(1, screen), external],
                                        settings: CornerSettings(builtIn: false, external: false, radiusPixels: 28), calibration: nil)
        XCTAssertTrue(off.isEmpty)
    }

    func testCalibrationAddsColouredTopMasksOnTheBuiltInOnly() {
        let external = display(2, CGRect(x: 5000, y: 0, width: 1920, height: 1080), builtIn: false)
        let specs = LayoutDecision.decide(displays: [display(1, screen), external], settings: on, calibration: .default)
        let top = specs.filter { $0.key.display == 1 && $0.topLevel }
        XCTAssertEqual(top.count, 2)
        XCTAssertTrue(top.allSatisfy { $0.colour == .rgb(.default) && !$0.constrainsCursor })
        XCTAssertTrue(specs.filter { $0.key.display == 2 }.allSatisfy { $0.colour == .black })
        let only = LayoutDecision.decide(displays: [display(1, screen)],
                                         settings: CornerSettings(builtIn: false, external: false, radiusPixels: 28),
                                         calibration: .default)
        XCTAssertEqual(only.map(\.key.corner), [.topLeft, .topRight], "calibration alone draws no bottom masks")
    }

    func testASharedCornerIsDrawnButDoesNotHoldThePointer() {
        let left = display(1, CGRect(x: 0, y: 0, width: 1000, height: 800), builtIn: false)
        let right = display(2, CGRect(x: 1000, y: 0, width: 1000, height: 800), builtIn: false)
        let specs = LayoutDecision.decide(displays: [left, right], settings: on, calibration: nil)
        func spec(_ id: UInt32, _ corner: CornerPosition) -> MaskSpec { specs.first { $0.key == MaskKey(display: id, corner: corner) }! }
        XCTAssertFalse(spec(1, .bottomRight).constrainsCursor)
        XCTAssertFalse(spec(2, .topLeft).constrainsCursor)
        XCTAssertTrue(spec(1, .bottomLeft).constrainsCursor)
        XCTAssertTrue(spec(2, .bottomRight).constrainsCursor)
        XCTAssertEqual(specs.count, 8, "still drawn")
    }

    /// A neighbour on any side frees the corners that face it; one that meets a corner only at its point
    /// shares no span the pointer could cross, so it frees nothing.
    func testANeighbourOnEachOfTheFourSidesFreesTheCornersFacingIt() {
        let centre = CGRect(x: 0, y: 0, width: 1000, height: 800)
        func freed(_ neighbour: CGRect) -> Set<CornerPosition> {
            let specs = LayoutDecision.decide(displays: [display(1, centre, builtIn: false),
                                                         display(2, neighbour, builtIn: false)],
                                              settings: on, calibration: nil)
            return Set(specs.filter { $0.key.display == 1 && !$0.constrainsCursor }.map(\.key.corner))
        }
        XCTAssertEqual(freed(CGRect(x: 1000, y: 0, width: 1000, height: 800)), [.bottomRight, .topRight], "right")
        XCTAssertEqual(freed(CGRect(x: -1000, y: 0, width: 1000, height: 800)), [.bottomLeft, .topLeft], "left")
        XCTAssertEqual(freed(CGRect(x: 0, y: 800, width: 1000, height: 800)), [.topLeft, .topRight], "above")
        XCTAssertEqual(freed(CGRect(x: 0, y: -800, width: 1000, height: 800)), [.bottomLeft, .bottomRight], "below")
        XCTAssertEqual(freed(CGRect(x: 500, y: 800, width: 1000, height: 800)), [.topRight], "above, shifted right")
        XCTAssertEqual(freed(CGRect(x: 1000, y: 800, width: 1000, height: 800)), [], "diagonal: a point is no span")
        XCTAssertEqual(freed(CGRect(x: -1000, y: -800, width: 1000, height: 800)), [], "diagonal below left")
    }

    func testAMirroredDisplayIsStillANeighbourAndGetsNoMask() {
        let extended = display(1, CGRect(x: 0, y: 0, width: 1000, height: 800), builtIn: false)
        let mirrored = display(2, CGRect(x: 1000, y: 0, width: 1000, height: 800), builtIn: false, mirrored: true)
        let specs = LayoutDecision.decide(displays: [extended, mirrored], settings: on, calibration: nil)
        XCTAssertEqual(Set(specs.map(\.key.display)), [1])
        XCTAssertFalse(specs.first { $0.key == MaskKey(display: 1, corner: .bottomRight) }!.constrainsCursor)
        XCTAssertFalse(specs.first { $0.key == MaskKey(display: 1, corner: .topRight) }!.constrainsCursor)
        XCTAssertTrue(specs.first { $0.key == MaskKey(display: 1, corner: .bottomLeft) }!.constrainsCursor)
    }

    func testTheRadiusNeverExceedsWhatItsWindowHolds() {
        let specs = LayoutDecision.decide(displays: [display(1, screen, ppp: 0.01)], settings: on, calibration: nil)
        XCTAssertFalse(specs.isEmpty)
        for spec in specs {
            XCTAssertEqual(spec.frame.width, CornerFrames.largestSize)
            XCTAssertLessThanOrEqual(spec.radius * 2, spec.frame.width, "radius \(spec.radius)")
        }
    }

    func testADisplayIdListedTwiceCountsOnce() {
        let first = display(1, screen)
        let again = display(1, CGRect(x: 5000, y: 0, width: 800, height: 600))
        let specs = LayoutDecision.decide(displays: [first, again], settings: on, calibration: nil)
        XCTAssertEqual(specs.map(\.key), [MaskKey(display: 1, corner: .bottomLeft), MaskKey(display: 1, corner: .bottomRight)])
        XCTAssertEqual(specs.first?.frame.minX, 0, "the first wins")
    }

    func testTheMotionRuleSurvivesAClockThatGoesBackOrIsNotANumber() {
        var back = DisplayMotion()
        XCTAssertEqual(back.update(atRest: false, now: 1000), false)
        XCTAssertNil(back.update(atRest: true, now: 10), "a clock gone back is motion")
        XCTAssertEqual(back.update(atRest: true, now: 10.06), true, "and settles from there")
        var nan = DisplayMotion()
        XCTAssertEqual(nan.update(atRest: false, now: .nan), false, "a non-number is motion")
        XCTAssertFalse(nan.rounded)
        XCTAssertNil(nan.update(atRest: true, now: .infinity))
        XCTAssertNil(nan.update(atRest: false, now: 5))
        XCTAssertEqual(nan.update(atRest: true, now: 5.06), true)
    }

    /// A clock that is not a number is never stored: the next finite sample at rest has no motion to wait
    /// out, it does not wait on a NaN for ever.
    func testANonNumberClockLeavesNoTraceInTheLastMotion() {
        var motion = DisplayMotion()
        XCTAssertEqual(motion.update(atRest: false, now: .nan), false, "a non-number is motion")
        XCTAssertEqual(motion.rounded, false)
        XCTAssertEqual(motion.update(atRest: true, now: 7), true, "a finite rest sample after a NaN settles")
    }

    func testTheLidClosedScaleIsTheRememberedOne() {
        XCTAssertEqual(RadiusScale.reference(builtInNow: 2, remembered: 3, main: 1), 2)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: 2, main: 1), 2)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: nil, main: 1.5), 1.5)
    }

    func testAStepIsAChangedSpecNotARebuild() {
        let one = LayoutDecision.decide(displays: [display(1, screen)], settings: on, calibration: nil)
        let stepped = RadiusMath.stepped(28, direction: 1, scale: 2)
        XCTAssertEqual(stepped, 28.5)
        let two = LayoutDecision.decide(displays: [display(1, screen)],
                                        settings: CornerSettings(builtIn: true, external: true, radiusPixels: stepped), calibration: nil)
        let diff = MaskDiff.between(one, two)
        XCTAssertTrue(diff.added.isEmpty && diff.removed.isEmpty)
        XCTAssertEqual(diff.changed.map(\.key), one.map(\.key))
        XCTAssertTrue(MaskDiff.between(one, one).isEmpty)
        let gone = MaskDiff.between(one, [])
        XCTAssertEqual(gone.removed, one.map(\.key))
        XCTAssertEqual(MaskDiff.between([], one).added, one)
        XCTAssertEqual(RadiusMath.stepped(0.5, direction: -1, scale: 2), 0.5)
        XCTAssertEqual(RadiusMath.stepped(128, direction: 1, scale: 2), 128)
    }

    func testPixelsPerPointTakesTheLargestNativeModeOfTheSameShape() {
        let modes = [DisplayModeInfo(pixelWidth: 3024, pixelHeight: 1964, isNative: true),
                     DisplayModeInfo(pixelWidth: 2056, pixelHeight: 1329, isNative: true),
                     DisplayModeInfo(pixelWidth: 5120, pixelHeight: 2880, isNative: true),
                     DisplayModeInfo(pixelWidth: 4000, pixelHeight: 1964, isNative: false)]
        XCTAssertEqual(PixelsPerPoint.resolve(modes: modes, pointSize: CGSize(width: 1512, height: 982), backing: 2), 2)
    }

    func testTheDefaultKeepsMeaningFourteenPointsWhenTheScaleIsNoScale() {
        XCTAssertEqual(RadiusMath.defaultPixels(scale: .nan), 14)
        XCTAssertEqual(RadiusMath.defaultPixels(scale: -2), 14)
        XCTAssertEqual(RadiusMath.defaultPixels(scale: 0), 14)
        XCTAssertEqual(RadiusMath.defaultPixels(scale: 1e308), 128)
    }

    func testRadiusPresetsAreBuiltInPointsAtTheReferenceScale() {
        XCTAssertEqual(RadiusMath.preset(points: 14, scale: 2), 28)
        XCTAssertEqual(RadiusMath.defaultPixels(scale: 2), 28)
        XCTAssertEqual(RadiusMath.points(pixels: 28, pixelsPerPoint: 2), 14)
    }

    /// Points of SwiftUI's `RoundedRectangle(cornerRadius: 100, style: .continuous)` edge: the path of
    /// `RoundedRectangle(cornerRadius:style: .continuous).path(in:)`, flattened to 0.0005 pt, read by a
    /// script outside the repo. At x (points from the display's side edge) the curve is at y. An engine
    /// cannot import SwiftUI, so the numbers are pinned here.
    private static let swiftUIContinuousCorner: [(x: CGFloat, y: CGFloat)] = [
        (10, 56.956584), (25, 33.581301), (50, 13.468558), (75, 4.327439), (100, 0.962562), (125, 0.099304),
    ]

    func testThePathIsSwiftUIsContinuousCornerWithinAHundredthOfAPoint() {
        let r: CGFloat = 100
        let size = r * 2
        for corner in CornerPosition.allCases {
            let path = CornerPath.visible(size: size, radius: r, corner: corner)
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: corner.isRight ? size - x : x, y: corner.isTop ? size - y : y)
            }
            func inward(_ y: CGFloat, _ by: CGFloat) -> CGFloat { y + by }
            for (x, y) in Self.swiftUIContinuousCorner {
                XCTAssertTrue(path.contains(at(x, inward(y, 0.01))), "\(corner) x=\(x): just inside the curve is visible")
                XCTAssertFalse(path.contains(at(x, inward(y, -0.01))), "\(corner) x=\(x): just outside the curve is cut")
            }
        }
    }

    func testDisplaysAtNegativeOriginsKeepTheirOwnCorners() {
        let left = display(1, CGRect(x: -2000, y: -800, width: 1000, height: 800), builtIn: false)
        let right = display(2, CGRect(x: -1000, y: -800, width: 1000, height: 800), builtIn: false)
        let specs = LayoutDecision.decide(displays: [left, right], settings: on, calibration: nil)
        func spec(_ id: UInt32, _ corner: CornerPosition) -> MaskSpec { specs.first { $0.key == MaskKey(display: id, corner: corner) }! }
        XCTAssertEqual(spec(1, .bottomLeft).frame, CGRect(x: -2000, y: -800, width: 28, height: 28))
        XCTAssertEqual(spec(2, .topRight).frame, CGRect(x: -28, y: -28, width: 28, height: 28))
        XCTAssertFalse(spec(1, .topRight).constrainsCursor)
        XCTAssertFalse(spec(2, .bottomLeft).constrainsCursor)
        XCTAssertTrue(spec(1, .topLeft).constrainsCursor)
        XCTAssertTrue(spec(2, .bottomRight).constrainsCursor)
    }

    func testThreeDisplaysInAnLShareOnlyTheCornersTheyShare() {
        let a = display(1, CGRect(x: 0, y: 0, width: 1000, height: 800), builtIn: false)
        let b = display(2, CGRect(x: 1000, y: 0, width: 1000, height: 800), builtIn: false)
        let c = display(3, CGRect(x: 0, y: 800, width: 1000, height: 800), builtIn: false)
        let specs = LayoutDecision.decide(displays: [a, b, c], settings: on, calibration: nil)
        let freed = Set(specs.filter { !$0.constrainsCursor }.map(\.key))
        XCTAssertEqual(freed, [MaskKey(display: 1, corner: .bottomRight), MaskKey(display: 1, corner: .topRight),
                               MaskKey(display: 1, corner: .topLeft),
                               MaskKey(display: 2, corner: .bottomLeft), MaskKey(display: 2, corner: .topLeft),
                               MaskKey(display: 3, corner: .bottomLeft), MaskKey(display: 3, corner: .bottomRight)])
        XCTAssertEqual(specs.count, 12)
    }

    func testANeighbourTouchesTheCornerOnlyOverTheSquaresSpan() {
        func freed(neighbourY: CGFloat, neighbourX: CGFloat = 1000) -> Bool {
            let left = display(1, CGRect(x: 0, y: 0, width: 1000, height: 800), builtIn: false)
            let right = display(2, CGRect(x: neighbourX, y: neighbourY, width: 1000, height: 800), builtIn: false)
            let specs = LayoutDecision.decide(displays: [left, right], settings: on, calibration: nil)
            return !specs.first { $0.key == MaskKey(display: 1, corner: .bottomRight) }!.constrainsCursor
        }
        XCTAssertTrue(freed(neighbourY: 0))
        XCTAssertTrue(freed(neighbourY: 27.5), "half a point of the 28 pt square is shared")
        XCTAssertFalse(freed(neighbourY: 28), "the neighbour starts where the square ends: no shared span")
        XCTAssertTrue(freed(neighbourY: -799.5), "it ends half a point into the square")
        XCTAssertFalse(freed(neighbourY: -800), "it ends where the square starts")
        XCTAssertFalse(freed(neighbourY: 400), "beside the display but away from the corner")
        XCTAssertTrue(freed(neighbourY: 0, neighbourX: 999), "overlapping frames still touch")
        XCTAssertFalse(freed(neighbourY: 0, neighbourX: 1002), "a gap is no neighbour")
    }

    func testAMirrorSetOfTwoAndOneExtendedDrawOnlyTheExtended() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let specs = LayoutDecision.decide(displays: [display(1, frame, mirrored: true), display(2, frame, mirrored: true),
                                                     display(3, CGRect(x: 1000, y: 0, width: 1000, height: 800), builtIn: false)],
                                          settings: on, calibration: .default)
        XCTAssertEqual(Set(specs.map(\.key.display)), [3])
        XCTAssertEqual(specs.count, 4)
        XCTAssertTrue(specs.allSatisfy { $0.colour == .black }, "calibration is the built-in's alone, and it is mirrored away")
    }

    func testTheBuiltInAbsentLeavesTheExternalsAtTheirOwnScale() {
        let external = display(2, CGRect(x: 0, y: 0, width: 1920, height: 1080), builtIn: false, ppp: 1)
        let remembered = RadiusScale.reference(builtInNow: nil, remembered: 2, main: 1)
        let forgotten = RadiusScale.reference(builtInNow: nil, remembered: nil, main: nil)
        XCTAssertEqual(RadiusMath.preset(points: 14, scale: remembered), 28)
        XCTAssertEqual(RadiusMath.preset(points: 14, scale: forgotten), 14)
        for pixels in [RadiusMath.preset(points: 14, scale: remembered), RadiusMath.preset(points: 14, scale: forgotten)] {
            let specs = LayoutDecision.decide(displays: [external],
                                              settings: CornerSettings(builtIn: true, external: true, radiusPixels: pixels), calibration: nil)
            XCTAssertEqual(specs.count, 4)
            XCTAssertTrue(specs.allSatisfy { $0.radius == CGFloat(pixels) }, "1 pixel per point: the radius in points is the pixels")
        }
    }

    func testAScaleThatIsNoScaleIsNeverTheRememberedOne() {
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: .nan, main: 1.5), 1.5)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: 0, main: 1.5), 1.5)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: -2, main: 1.5), 1.5)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: .infinity, main: 1.5), 1.5)
        XCTAssertEqual(RadiusScale.reference(builtInNow: 0, remembered: 2, main: 1.5), 2)
        XCTAssertEqual(RadiusScale.reference(builtInNow: -1, remembered: nil, main: 1.5), 1.5)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: nil, main: .nan), 1)
        XCTAssertEqual(RadiusScale.reference(builtInNow: nil, remembered: nil, main: nil), 1)
    }

    func testTheRadiusBoundsAndAStepPastEach() {
        XCTAssertEqual([0.25, 0.4, 0.5, 0.75, 127.5, 128, 128.5, 1000].map { RadiusMath.pixels(stored: $0, scale: 2) },
                       [0.5, 0.5, 0.5, 0.75, 127.5, 128, 128, 128])
        XCTAssertEqual(RadiusMath.stepped(0.5, direction: -1, scale: 2), 0.5)
        XCTAssertEqual(RadiusMath.stepped(0.5, direction: 1, scale: 2), 1)
        XCTAssertEqual(RadiusMath.stepped(128, direction: 1, scale: 2), 128)
        XCTAssertEqual(RadiusMath.stepped(128, direction: -1, scale: 2), 127.5)
        XCTAssertEqual(RadiusMath.stepped(127.75, direction: 1, scale: 2), 128, "off the grid and past the top")
        XCTAssertEqual(RadiusMath.stepped(10.3, direction: 0, scale: 2), 10.5, "no direction still lands on the half-pixel grid")
        XCTAssertEqual(RadiusMath.stepped(10, direction: 7, scale: 2), 10.5, "a step is one step whatever the sign's size")
        XCTAssertEqual(RadiusMath.stepped(10, direction: -7, scale: 2), 9.5)
        XCTAssertEqual(RadiusMath.points(pixels: 0.5, pixelsPerPoint: 2), 0.25)
        XCTAssertEqual(RadiusMath.points(pixels: 128, pixelsPerPoint: 1), 128)
        XCTAssertEqual(RadiusMath.points(pixels: 1000, pixelsPerPoint: 1), 128, "past the top the stored value is clamped")
    }

    func testPresetsAtOtherScalesStayInsideTheBounds() {
        XCTAssertEqual(RadiusMath.presetPoints.map { RadiusMath.preset(points: Double($0), scale: 1) }, [8, 10, 12, 14, 16, 18, 20, 24, 28, 32])
        XCTAssertEqual(RadiusMath.presetPoints.map { RadiusMath.preset(points: Double($0), scale: 5) },
                       [40, 50, 60, 70, 80, 90, 100, 120, 128, 128])
        XCTAssertEqual(RadiusMath.preset(points: 8, scale: 0.0001), 0.5)
        XCTAssertEqual(RadiusMath.preset(points: 8, scale: 0), 0.5)
    }

    func testThePointerOnTheEdgesOfTheMaskIsOnlyCorrectedInsideTheDisplay() throws {
        let rested = MaskPresentation(scale: 1, opacity: 1, ready: true)
        let bottomLeft = CornerGeometry(size: 28, radius: 14, corner: .bottomLeft, constrainsCursor: true)
        func correct(_ geometry: CornerGeometry, _ x: CGFloat, _ y: CGFloat, _ presentation: MaskPresentation? = nil) -> CursorCorrection.Result? {
            CursorCorrection.correct(local: CGPoint(x: x, y: y), remainder: .zero, geometry: geometry, presentation: presentation ?? rested)
        }
        XCTAssertNil(correct(bottomLeft, -1, 5), "one pixel left of the display")
        XCTAssertNil(correct(bottomLeft, 5, -1), "one pixel below it")
        XCTAssertNil(correct(bottomLeft, 1, 0), "the bottom edge is outside (Quartz: bottom-exclusive)")
        XCTAssertNotNil(correct(bottomLeft, 0, 1), "the left edge is inside")
        XCTAssertNotNil(correct(bottomLeft, 1, 0.0001))
        let onTheCurve = try XCTUnwrap(CursorBoundary(bottomLeft.visible).closestPoint(to: CGPoint(x: 0, y: 0)) as CGPoint?)
        XCTAssertNil(correct(bottomLeft, onTheCurve.x + 0.01, onTheCurve.y + 0.01), "just on the visible side: nothing to do")
        if let result = correct(bottomLeft, onTheCurve.x - 0.01, onTheCurve.y - 0.01) {
            XCTAssertTrue(bottomLeft.visible.contains(result.position))
        }
        let topRight = CornerGeometry(size: 28, radius: 14, corner: .topRight, constrainsCursor: true)
        XCTAssertNotNil(correct(topRight, 27, 28), "the top edge is inside (top-inclusive)")
        XCTAssertNil(correct(topRight, 27, 28.5), "one pixel above the display")
        XCTAssertNil(correct(topRight, 28, 27), "the right edge is outside")
        XCTAssertNil(correct(topRight, 28.5, 27), "one pixel right of the display")
        let hit = try XCTUnwrap(correct(topRight, 27, 27))
        XCTAssertTrue(topRight.visible.contains(hit.position))
        XCTAssertLessThan(hit.position.x, 28)
        XCTAssertLessThanOrEqual(hit.position.y, 28)
    }

    func testTheCorrectionAtTheSmallestScalesAnswersNilAndNeverTraps() {
        let geometry = CornerGeometry(size: 28, radius: 14, corner: .bottomLeft, constrainsCursor: true)
        for scale in [0, 0.001, 0.0011, 1e-300, -1] as [CGFloat] {
            for remainder in [CGPoint.zero, CGPoint(x: 1e300, y: -1e300)] {
                XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: remainder, geometry: geometry,
                                                      presentation: MaskPresentation(scale: scale, opacity: 1, ready: true)), "scale \(scale)")
            }
        }
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: geometry,
                                              presentation: MaskPresentation(scale: 1, opacity: 0, ready: true)), "an invisible mask holds nothing")
        XCTAssertNil(CursorCorrection.correct(local: CGPoint(x: 0, y: 0), remainder: .zero,
                                              geometry: CornerGeometry(size: 0, radius: 14, corner: .bottomLeft, constrainsCursor: true),
                                              presentation: MaskPresentation(scale: 1, opacity: 1, ready: true)), "no window, no hit")
        let half = CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: .zero, geometry: geometry,
                                            presentation: MaskPresentation(scale: 0.5, opacity: 1, ready: true))
        XCTAssertNotNil(half, "half-way through the morph the corner is still held")
        let rested = MaskPresentation(scale: 1, opacity: 1, ready: true)
        let far = CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: CGPoint(x: 1e6, y: 1e6), geometry: geometry, presentation: rested)
        XCTAssertNotNil(far, "a large finite remainder is still put on the curve")
        for remainder in [1e300, -1e300, 1e155] {
            _ = CursorCorrection.correct(local: CGPoint(x: 1, y: 1), remainder: CGPoint(x: remainder, y: remainder), geometry: geometry,
                                         presentation: rested)
        }
    }

    func testTheMotionRuleAtItsEdges() {
        var exact = DisplayMotion()
        XCTAssertEqual(exact.update(atRest: false, now: 0), false)
        XCTAssertNil(exact.update(atRest: true, now: DisplayMotion.settle), "exactly the settle time is not past it")
        XCTAssertEqual(exact.update(atRest: true, now: DisplayMotion.settle.nextUp), true)
        var motion = DisplayMotion()
        XCTAssertEqual(motion.update(atRest: false, now: 10), false)
        XCTAssertNil(motion.update(atRest: true, now: 10.049), "inside the settle time")
        XCTAssertEqual(motion.update(atRest: true, now: 10.051), true, "past it")
        XCTAssertNil(motion.update(atRest: true, now: 11), "already rounded: no change")
        XCTAssertEqual(motion.update(atRest: false, now: 12), false)
        XCTAssertNil(motion.update(atRest: false, now: 12.01), "still moving: no change")
        XCTAssertNil(motion.update(atRest: true, now: 12.02))
        XCTAssertNil(motion.update(atRest: false, now: 12.03), "motion again restarts the wait")
        XCTAssertNil(motion.update(atRest: true, now: 12.07))
        XCTAssertEqual(motion.update(atRest: true, now: 12.09), true)
    }

    private func spec(_ id: UInt32, _ corner: CornerPosition, radius: CGFloat = 14, maxFPS: Int = 120) -> MaskSpec {
        MaskSpec(key: MaskKey(display: id, corner: corner), frame: CGRect(x: 0, y: 0, width: 28, height: 28), radius: radius,
                 colour: .black, constrainsCursor: true, topLevel: corner.isTop, backingScale: 2, maxFPS: maxFPS)
    }

    func testTheDiffIgnoresOrderAndNamesOnlyWhatChanged() {
        let a = spec(1, .bottomLeft), b = spec(1, .bottomRight), c = spec(2, .topLeft)
        XCTAssertTrue(MaskDiff.between([a, b, c], [c, a, b]).isEmpty, "a reorder is no change")
        XCTAssertTrue(MaskDiff.between([a, b, c], [b, c, a]).isEmpty)
        let changed = spec(1, .bottomRight, radius: 15)
        XCTAssertEqual(MaskDiff.between([a, b, c], [c, changed, a]), MaskDiff(added: [], removed: [], changed: [changed]))
        XCTAssertEqual(MaskDiff.between([a, b, c], [a, b, spec(2, .topLeft, maxFPS: 60)]).changed.map(\.key), [c.key],
                       "the sampler's rate is part of the spec")
        let other = spec(2, .bottomLeft)
        XCTAssertEqual(MaskDiff.between([a, b], [a, changed, other]),
                       MaskDiff(added: [other], removed: [], changed: [changed]))
        XCTAssertEqual(MaskDiff.between([a, b, c], [a, spec(2, .topRight)]),
                       MaskDiff(added: [spec(2, .topRight)], removed: [b.key, c.key], changed: []),
                       "the same display at another corner is another key")
        XCTAssertEqual(MaskDiff.between([a], [spec(3, .bottomLeft)]).removed, [a.key], "the same corner of another display is another key")
        XCTAssertEqual(MaskDiff.between([a, a], [b]).removed, [a.key], "a duplicate key is removed once")
        XCTAssertEqual(MaskDiff.between([a], [b, b]).added, [b], "and added once")
    }
}
