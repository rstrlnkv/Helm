import XCTest
import AppKit
@testable import HelmUI

/// The countdown is a fraction of the outline's perimeter, so where that
/// perimeter starts and which way it runs *is* the countdown.
///
/// Neither is a property of the path as built. `NSBezierPath(roundedRect:)`
/// and a hand-built polygon each start wherever their construction started and
/// wind whichever way it wound — so a countdown could begin at the bottom left
/// and run anti-clockwise, which is not wrong by a little. It is a clock going
/// backwards.
final class MenuBarIconPerimeterTests: XCTestCase {

    private let size: CGFloat = 15

    private func walk(_ style: MenuBarIconStyle) -> [CGPoint] {
        MenuBarIcon.perimeter(of: MenuBarIcon.outline(style: style, size: size))
    }

    func testEveryShapeStartsAtTheTop() {
        for style in MenuBarIconStyle.allCases {
            let points = walk(style)
            let top = points.map(\.y).max()!
            XCTAssertEqual(points[0].y, top, accuracy: 0.01,
                           "\(style) starts \(top - points[0].y) pt below its own top")
        }
    }

    /// Among equally high points — the square and the capsule both have a flat
    /// top edge — the one nearest the middle, so a countdown starts at twelve
    /// o'clock rather than at a corner.
    func testAFlatTopStartsInTheMiddleOfIt() {
        for style in [MenuBarIconStyle.squircle, .capsule] {
            let points = walk(style)
            let centre = (points.map(\.x).min()! + points.map(\.x).max()!) / 2
            XCTAssertEqual(points[0].x, centre, accuracy: size * 0.12,
                           "\(style) starts \(abs(points[0].x - centre)) pt off centre")
        }
    }

    func testEveryShapeRunsClockwise() {
        for style in MenuBarIconStyle.allCases {
            let points = walk(style)
            // Leaving the top, clockwise means going right before going down.
            let early = points[1..<min(points.count, 6)]
            XCTAssertTrue(early.contains { $0.x > points[0].x + 0.01 },
                          "\(style) leaves the top to the left, which is anti-clockwise")
        }
    }

    /// The control the tests above need, and it took two attempts to point at
    /// the right thing.
    ///
    /// The first version asked whether the raw paths start at their *top*, and
    /// all three do — so it read as «normalising is untested» when the part
    /// that was doing the work was something else. What none of them starts at
    /// is the top *centre*: flattening a rounded rectangle turns its top edge
    /// into one segment, whose ends are the corners. The square began its
    /// countdown 2.4 pt right of centre before the walk split that edge.
    func testNoRawPathStartsAtTheTopCentre() {
        var offenders = 0
        for style in MenuBarIconStyle.allCases {
            let raw = MenuBarIcon.outline(style: style, size: size).flattened
            var buffer = [CGPoint](repeating: .zero, count: 3)
            var points: [CGPoint] = []
            for index in 0..<raw.elementCount {
                switch raw.element(at: index, associatedPoints: &buffer) {
                case .moveTo, .lineTo: points.append(buffer[0])
                default: break
                }
            }
            guard points.count > 2 else { continue }
            let top = points.map(\.y).max()!
            let centre = (points.map(\.x).min()! + points.map(\.x).max()!) / 2
            if abs(points[0].y - top) > 0.01 || abs(points[0].x - centre) > 0.01 { offenders += 1 }
        }
        // Not all three. The hexagon is built from its apex, and a hexagon's
        // apex *is* its top centre — so on that one shape the walk is a no-op,
        // which is the right answer rather than a gap. The two rounded shapes
        // are where it does the work.
        XCTAssertGreaterThanOrEqual(offenders, 2,
                                    "the rounded shapes already start at twelve o'clock, "
                                    + "so the walk that puts them there is untested")
    }

    /// A quarter of the way round from the top is the right-hand side.
    func testAQuarterOfTheWayRoundIsOnTheRight() {
        for style in MenuBarIconStyle.allCases {
            let points = walk(style)
            let lengths = points.indices.map { index -> CGFloat in
                let next = points[(index + 1) % points.count]
                return hypot(next.x - points[index].x, next.y - points[index].y)
            }
            let total = lengths.reduce(0, +)
            var walked: CGFloat = 0
            var quarter = points[0]
            for (index, segment) in lengths.enumerated() {
                // `walked` has to grow, or the first segment is always the one
                // that clears the threshold and the answer is the second point
                // of the path — which is what this test asserted, wrongly,
                // until it was run.
                if walked + segment >= total / 4 {
                    quarter = points[(index + 1) % points.count]
                    break
                }
                walked += segment
            }
            let centre = (points.map(\.x).min()! + points.map(\.x).max()!) / 2
            XCTAssertGreaterThan(quarter.x, centre,
                                 "\(style) is a quarter of the way round on the left")
        }
    }

    // MARK: - The walk has to be as round as the curve drawn under it

    private func walkLength(_ style: MenuBarIconStyle) -> CGFloat {
        let points = walk(style)
        return points.indices.reduce(CGFloat(0)) { total, index in
            let next = points[(index + 1) % points.count]
            return total + hypot(next.x - points[index].x, next.y - points[index].y)
        }
    }

    private func meanRadius(_ style: MenuBarIconStyle) -> CGFloat {
        let centre = CGPoint(x: size / 2, y: size / 2)
        let points = walk(style)
        return points.map { hypot($0.x - centre.x, $0.y - centre.y) }.reduce(0, +)
            / CGFloat(points.count)
    }

    /// A round shape stays round while a timer is running.
    ///
    /// The countdown strokes a *part* of the outline from this walk, over the
    /// whole outline drawn as the real curve. If the walk is coarse the two
    /// disagree and the visible arc has corners — which shipped twice. The
    /// first fix set `flatness` on the path; `flattened` reads the class's
    /// `defaultFlatness` and ignored it, so nothing changed and nothing failed.
    ///
    /// **Length, not «is every point on the circle».** That was written first
    /// and cannot fail: flattening puts its points *on* the curve, so an
    /// octagon's vertices sit exactly on the circle too — as does a hexagon's,
    /// which is how the control below caught it. What a polygon loses is the
    /// bulge between its vertices, and that shows up in the perimeter: an
    /// octagon is 2.5% short of its circle, a walk fine enough to draw is
    /// under a tenth of one percent.
    func testARingsWalkIsAsLongAsItsCircumference() {
        for style in [MenuBarIconStyle.ring, .doubleRing, .ringDot] {
            let circumference = 2 * CGFloat.pi * meanRadius(style)
            XCTAssertEqual(walkLength(style), circumference, accuracy: 0.005 * circumference,
                           "\(style) walks \(walkLength(style)) where its circle is \(circumference)")
        }
    }

    /// The control. The assertion above passes on any check that always passes,
    /// and this is the shape that proves it does not: a hexagon's corners are
    /// on the same circle its walk is measured against, and its perimeter is
    /// 17% short of it.
    func testTheLengthCheckCanTellAHexagonFromARing() {
        let circumference = 2 * CGFloat.pi * meanRadius(.hexagon)
        XCTAssertLessThan(walkLength(.hexagon), circumference * 0.995,
                          "a hexagon measured as round, so this check measures nothing")
    }

    /// Global state, borrowed and given back. `perimeter` sets the class's
    /// `defaultFlatness` because that is the only value `flattened` reads —
    /// and anything drawing after it must find the value it had.
    func testTheClassFlatnessIsPutBack() {
        let before = NSBezierPath.defaultFlatness
        _ = walk(.ring)
        XCTAssertEqual(NSBezierPath.defaultFlatness, before)
    }
}
