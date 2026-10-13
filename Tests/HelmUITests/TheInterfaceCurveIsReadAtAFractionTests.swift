import QuartzCore
import XCTest
@testable import HelmUI

/// **`HelmMotion.interfaceProgress(at:)` answers how far `HelmMotion.interfaceCurve` has come at a fraction of its
/// length, and the literals here are an independent solution of the same curve.** The curve is a cubic Bezier from
/// (0, 0) to (1, 1) with control points (0.2, 0.8) and (0.2, 1); the progress at a fraction is the curve's y where
/// its x is that fraction. The literals are given to six places; the rows hold them to 1e-4. One row reads the
/// token's control points back from `interfaceCurve` itself, so the literals and the token cannot part without a
/// row going red.
final class TheInterfaceCurveIsReadAtAFractionTests: XCTestCase {

    /// The fractions and the progress the curve has at each, to six places.
    private let literals: [(Double, Double)] = [
        (0.0625, 0.252461), (0.125, 0.483573), (0.25, 0.767284), (0.5, 0.946079), (0.75, 0.991108),
    ]

    /// Total failure prints: "at <fraction> the progress was <p>, not <literal>".
    func testTheProgressAtAFractionIsTheCurvesY() {
        for (fraction, literal) in literals {
            let p = HelmMotion.interfaceProgress(at: fraction)
            XCTAssertEqual(p, literal, accuracy: 0.000_1, "at \(fraction) the progress was \(p), not \(literal)")
        }
    }

    /// The ends: the curve starts at 0 and arrives at 1. Total failure prints: "the progress at 0 was <p>" / "the
    /// progress at 1 was <p>".
    func testTheCurveStartsAtNothingAndArrivesAtAll() {
        let start = HelmMotion.interfaceProgress(at: 0)
        let end = HelmMotion.interfaceProgress(at: 1)
        XCTAssertEqual(start, 0, accuracy: 1e-9, "the progress at 0 was \(start)")
        XCTAssertEqual(end, 1, accuracy: 1e-9, "the progress at 1 was \(end)")
    }

    /// Outside 0...1 the answer is the end it is past, and a fraction that is not a number reads as the end: a
    /// travel that does not know where it is ends at its target. Total failure prints: "at <fraction> the progress
    /// was <p>, not <expected>".
    func testAFractionOutsideTheLengthReadsAsTheEndItIsPast() {
        let cases: [(Double, Double)] = [
            (-0.5, 0), (-1e-9, 0), (-1e9, 0), (-.infinity, 0),
            (1.000_000_1, 1), (1.5, 1), (1e9, 1), (.infinity, 1),
            (.nan, 1),
        ]
        for (fraction, expected) in cases {
            let p = HelmMotion.interfaceProgress(at: fraction)
            XCTAssertEqual(p, expected, "at \(fraction) the progress was \(p), not \(expected)")
        }
    }

    /// The curve never goes back: over a sweep of a thousand steps the answer does not fall and stays in 0...1,
    /// and over 0 to 0.9 it rises at every step of a hundredth, so a constant cannot pass. Total failure prints:
    /// "at <x> the progress fell to <p> from <q>" / "at <x> the progress was <p>, outside 0 to 1" / "at <x> the
    /// progress was <p>, no more than <q> at the step before".
    func testTheProgressNeverGoesBack() {
        var previous = HelmMotion.interfaceProgress(at: 0)
        for i in 1...1000 {
            let x = Double(i) / 1000
            let p = HelmMotion.interfaceProgress(at: x)
            XCTAssertGreaterThanOrEqual(p, previous, "at \(x) the progress fell to \(p) from \(previous)")
            XCTAssertTrue(p >= 0 && p <= 1, "at \(x) the progress was \(p), outside 0 to 1")
            previous = p
        }
        var before = HelmMotion.interfaceProgress(at: 0)
        for i in 1...90 {
            let x = Double(i) / 100
            let p = HelmMotion.interfaceProgress(at: x)
            XCTAssertGreaterThan(p, before, "at \(x) the progress was \(p), no more than \(before) at the step before")
            before = p
        }
    }

    /// The token's own control points are (0, 0), (0.2, 0.8), (0.2, 1), (1, 1), read through
    /// `getControlPoint(at:values:)`: the literals above are of this curve and no other. The two ends are read too,
    /// so a reading that answers nothing for every index cannot pass. Total failure prints: "control point <i> was
    /// (<x>, <y>), not (<x>, <y>)".
    func testTheTokensControlPointsAreTheOnesTheLiteralsWereSolvedFor() {
        let expected: [(Float, Float)] = [(0, 0), (0.2, 0.8), (0.2, 1), (1, 1)]
        for (index, point) in expected.enumerated() {
            var values: [Float] = [-1, -1]
            HelmMotion.interfaceCurve.getControlPoint(at: index, values: &values)
            XCTAssertEqual(values[0], point.0, accuracy: 0.000_001, "control point \(index) was (\(values[0]), \(values[1])), not (\(point.0), \(point.1))")
            XCTAssertEqual(values[1], point.1, accuracy: 0.000_001, "control point \(index) was (\(values[0]), \(values[1])), not (\(point.0), \(point.1))")
        }
    }
}
