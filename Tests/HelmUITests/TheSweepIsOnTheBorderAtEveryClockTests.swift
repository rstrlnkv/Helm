// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
@testable import HelmUI

/// **`HelmMeasuringSlot.Sweep.at` takes a `Date` and holds only for half of
/// them.**
///
/// The head is `now.timeIntervalSinceReferenceDate / lap` folded by
/// `truncatingRemainder(dividingBy: 1)`, and that operation keeps the sign of
/// its **dividend** — the C `fmod` rule. Before 2001-01-01 the interval is
/// negative, so the head is in `-1..<0` and both spans of the sweep come back
/// below zero: `trim(from: -0.375, to: -0.205)` on the card's border, which is
/// outside the `0...1` parametrisation `Shape.trim` documents and is not
/// anywhere on the rounded rectangle. The card that says «a figure is coming»
/// says it with a border nobody drew.
///
/// **`MeasuringSlotSaysWhatIsStaleTests.testBothSpansStayInsideTheBorder`
/// already asserts this invariant and cannot fail on it**, because every sample
/// it takes is `Date(timeIntervalSinceReferenceDate: 0)` plus a positive offset.
/// The guard is real and its window is one-sided — the shape ARCHITECTURE.md
/// § A check that cannot fail is not a check collects. So this is not a second
/// copy of that test; it is the same invariant asked on the other side of the
/// origin, where the arithmetic actually turns over.
///
/// **The input is not invented.** A Mac that cannot read its real-time clock
/// boots at the Unix epoch, and it is the state this component is most likely
/// to meet one: `HelmExpectedWait.Claim.at` refuses a negative elapsed time in
/// so many words — «a laptop resuming, an NTP step» — so a clock that is wrong
/// under a running measurement is a case this feature has already decided it
/// has to survive. The other half of the same feature does not.
///
/// `lit` is invariant across the origin and this deliberately does **not**
/// assert on it: the total length is correct on both sides, which is exactly
/// why a test written around `lit` alone would go on passing. What breaks is
/// *where* the lit run is, and where is the whole content of a `trim`.
final class TheSweepIsOnTheBorderAtEveryClockTests: XCTestCase {

    private typealias Sweep = HelmMeasuringSlot.Sweep

    /// Named rather than spelled at the call site, so the failure message says
    /// which Mac it is talking about.
    private let clocks: [(String, Date)] = [
        ("a Mac that cannot read its clock, at the Unix epoch",
         Date(timeIntervalSince1970: 0)),
        ("a Mac put back to the start of 2000",
         Date(timeIntervalSinceReferenceDate: -31_536_000)),
        ("one second before the reference date",
         Date(timeIntervalSinceReferenceDate: -1)),
    ]

    /// The invariant `Shape.trim` needs, over a whole lap of each clock.
    ///
    /// A whole lap and not one instant: the head sweeps the entire
    /// parametrisation once per period, so a single sample can land on the one
    /// value that happens to be legal. Reported **once per clock**, with a count
    /// and one example: a per-sample assertion prints two hundred identical
    /// lines and buries whichever other test failed in the same run.
    func testBothSpansStayInsideTheBorderWhateverTheClockReads() {
        for (mac, start) in clocks {
            var offenders: [(Int, ClosedRange<Double>)] = []
            for step in 0...240 {
                let sweep = Sweep.at(start.addingTimeInterval(Double(step) * 0.01), lap: 2.4)
                for span in [sweep.first, sweep.second]
                where span.lowerBound < 0 || span.upperBound > 1
                        || span.lowerBound > span.upperBound {
                    offenders.append((step, span))
                }
            }
            XCTAssertTrue(offenders.isEmpty, """
                on \(mac), \(offenders.count) of 482 spans are off the border the \
                card is drawn on — the first at step \(offenders.first?.0 ?? -1), \
                \(offenders.first?.1 as Any). `truncatingRemainder` keeps the sign \
                of a negative `timeIntervalSinceReferenceDate` and nothing folds it \
                back, so `trim(from:to:)` is asked for a span outside the 0...1 it \
                is defined on
                """)
        }
    }

    /// **The same lap, sampled either side of the origin, must be the same
    /// picture** — the head is a phase and a phase has no memory of which
    /// century it is in.
    ///
    /// One period before the reference date is the reference date's own frame:
    /// `2.4` divides `2.4` exactly, so nothing here rests on floating point
    /// luck. It is the sharpest statement of the defect — the same instant of
    /// the same cycle, drawn in two different places.
    func testOnePeriodBeforeTheOriginIsTheSameFrameAsTheOrigin() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        /// A frame that differs across the origin: when, and the two heads.
        struct Apart { let offset: Double; let earlier: Double; let here: Double }
        var apart: [Apart] = []
        for step in 0..<12 {
            let offset = Double(step) * 0.2
            let here = Sweep.at(origin.addingTimeInterval(offset), lap: 2.4).first.lowerBound
            let earlier = Sweep.at(origin.addingTimeInterval(offset - 2.4),
                                   lap: 2.4).first.lowerBound
            if abs(here - earlier) > 1e-9 {
                apart.append(Apart(offset: offset, earlier: earlier, here: here))
            }
        }
        XCTAssertTrue(apart.isEmpty, """
            \(apart.count) of 12 frames differ across the origin — the first at \
            offset \(apart.first?.offset ?? -1) s, where one lap earlier begins at \
            \(apart.first?.earlier ?? .nan) and this lap at \(apart.first?.here ?? .nan). \
            The border is a cycle, so a clock reading before 2001 must draw the same \
            picture the same clock reads after it
            """)
    }

    /// And the length is right on both sides — asserted so the failures above
    /// are read as «in the wrong place» and not as «the segment vanished»,
    /// which is a different repair.
    func testTheLitRunIsStillTheRightLengthBeforeTheOrigin() {
        for (mac, start) in clocks {
            for step in 0...240 {
                let sweep = Sweep.at(start.addingTimeInterval(Double(step) * 0.01), lap: 2.4)
                XCTAssertEqual(sweep.lit, HelmMeasuringSlot.segment, accuracy: 0.0001,
                               "on \(mac), the segment changed length at step \(step)")
            }
        }
    }
}
