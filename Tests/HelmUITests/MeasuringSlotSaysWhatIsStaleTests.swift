import XCTest
import SwiftUI
@testable import HelmUI

/// **What the sweeping edge is allowed to mean, which is «running» and never
/// «this far along».**
///
/// The engine publishes a `String?` and the page reads a `Bool`; the tool it
/// drives runs down and up in parallel and prints nothing until it exits. So
/// there is no fraction anywhere in this feature, and the one way a lapping
/// border could start telling a lie is by lapping slowly enough to be read as a
/// journey. That is arithmetic, and it is what these hold.
///
/// They prove the rule and nothing about the screen; `MeasuringSlotMotionProbe`
/// is where the travel is measured in pixels.
final class MeasuringSlotSaysWhatIsStaleTests: XCTestCase {

    private typealias Sweep = HelmMeasuringSlot.Sweep
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - It laps, and a lap is not a measurement

    /// **The property that keeps this from becoming a progress bar.** A head
    /// that advanced once across the run would return `false` here; a head that
    /// laps returns to every position it has held, many times over.
    ///
    /// Nine at the shipped 2,4 s against the 22 s the measurement takes — which
    /// is the ratio the design rests on, asserted rather than described.
    func testItGetsRoundManyTimesInOneMeasurement() {
        var laps = 0
        var previous = Sweep.at(t0, lap: HelmMeasuringSlot.lap).first.lowerBound
        for step in 1...2200 {
            let head = Sweep.at(t0.addingTimeInterval(Double(step) * 0.01),
                                lap: HelmMeasuringSlot.lap).first.lowerBound
            if head < previous { laps += 1 }
            previous = head
        }
        XCTAssertGreaterThanOrEqual(laps, 8,
                                    "the border gets round \(laps) times in a 22 s "
                                    + "measurement — at that rate it reads as a "
                                    + "journey, which is the claim there is no "
                                    + "evidence for")
    }

    /// And the lap is exactly `lap` long: the same instant one period later is
    /// the same picture.
    ///
    /// **To an accuracy and not exactly**, which was worth finding out rather
    /// than assuming: written as `XCTAssertEqual` on the whole value it failed
    /// on twenty-three of twenty-four samples at the sixteenth decimal place —
    /// a period that is right and a comparison that is wrong. A guard nobody
    /// can satisfy gets deleted, and then the period has no guard at all.
    func testTheSamePictureComesRoundOnePeriodLater() {
        for step in 0..<24 {
            let now = t0.addingTimeInterval(Double(step) * 0.1)
            XCTAssertEqual(Sweep.at(now, lap: 2.4).first.lowerBound,
                           Sweep.at(now.addingTimeInterval(2.4), lap: 2.4).first.lowerBound,
                           accuracy: 1e-9,
                           "the period is not the lap, at step \(step)")
        }
    }

    /// And half a period later it is emphatically *not* the same picture — the
    /// half of the pair that stops the one above from passing over a border
    /// that never moves at all.
    func testAndHalfAPeriodLaterItIsSomewhereElse() {
        let here = Sweep.at(t0.addingTimeInterval(0.3), lap: 2.4).first.lowerBound
        let there = Sweep.at(t0.addingTimeInterval(1.5), lap: 2.4).first.lowerBound
        XCTAssertEqual(abs(here - there), 0.5, accuracy: 1e-9,
                       "the head is not travelling: \(here) then \(there)")
    }

    // MARK: - The wrap

    /// **The same amount of border is lit at every instant, including the ones
    /// where the segment is crossing the origin.**
    ///
    /// This is the whole reason `Sweep` answers with two spans instead of one,
    /// and the defect it guards against is invisible in a still: for the sixth
    /// of a lap that the segment straddles the top-left corner, a single
    /// `trim(from:to:)` clamps and the lit run shrinks to nothing and springs
    /// back. Sampled across a full lap so the wrap is inside the window.
    func testTheLitRunIsTheSameLengthWhereverItIsOnTheBorder() {
        for step in 0...240 {
            let sweep = Sweep.at(t0.addingTimeInterval(Double(step) * 0.01), lap: 2.4)
            XCTAssertEqual(sweep.lit, HelmMeasuringSlot.segment, accuracy: 0.0001,
                           "the segment changed length at step \(step): \(sweep)")
        }
    }

    /// Both spans stay inside the parametrisation a `Shape.trim` will accept,
    /// and neither runs backwards.
    func testBothSpansStayInsideTheBorder() {
        for step in 0...240 {
            let sweep = Sweep.at(t0.addingTimeInterval(Double(step) * 0.01), lap: 2.4)
            for span in [sweep.first, sweep.second] {
                XCTAssertGreaterThanOrEqual(span.lowerBound, 0, "\(sweep)")
                XCTAssertLessThanOrEqual(span.upperBound, 1, "\(sweep)")
                XCTAssertLessThanOrEqual(span.lowerBound, span.upperBound, "\(sweep)")
            }
        }
    }

    // MARK: - Refusals, in the safe direction

    /// A lap of no length is not a lap. Nothing is lit, rather than a division
    /// producing an infinity somewhere inside `trim(from:to:)`.
    func testALapOfNoLengthLightsNothing() {
        XCTAssertEqual(Sweep.at(t0, lap: 0).lit, 0)
        XCTAssertEqual(Sweep.at(t0, lap: -1).lit, 0)
        XCTAssertEqual(Sweep.at(t0, lap: 2.4, segment: 0).lit, 0)
    }

    /// A segment longer than the border is the whole border and never more.
    func testASegmentLongerThanTheBorderIsTheWholeBorder() {
        XCTAssertEqual(Sweep.at(t0, lap: 2.4, segment: 4).lit, 1, accuracy: 0.0001)
    }

    // MARK: - What the card says about the old figure

    /// **The figure is demoted while a newer one is being taken, and restored
    /// when it is not.**
    ///
    /// Asserted as arguments rather than read off a rendering, the shape
    /// `HelmMotion.spins(requested:reduceMotion:)` set. `HelmText.quiet` and not
    /// something quieter: a stale reading is still the only reading the person
    /// has, and that token is the one whose contrast has been measured against
    /// every surface this app draws.
    func testTheFigureIsDemotedOnlyWhileANewerOneIsComing() {
        XCTAssertEqual(HelmMeasuringSlot.ink(measuring: true), HelmText.quiet)
        XCTAssertEqual(HelmMeasuringSlot.ink(measuring: false), Color.primary)
        XCTAssertNotEqual(HelmMeasuringSlot.ink(measuring: true),
                          HelmMeasuringSlot.ink(measuring: false),
                          "a demotion nobody can see is a card still presenting "
                          + "the old answer as the current one")
    }
}
