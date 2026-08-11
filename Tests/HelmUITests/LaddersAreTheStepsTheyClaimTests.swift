import XCTest
@testable import HelmUI

/// **The two ladders are the steps their own documentation claims.**
///
/// `HelmSpace` and `HelmRadius` open by naming their steps — *2 · 4 · 6 · 8 · 12
/// · 18 · 28 · 40* and *4 · 6 · 10 · 14 · 26* — and the three ratchets that
/// police the ladders cannot see a token drift off one: `SpaceLadderRatchetTests`
/// scans for `.padding(10)` and `spacing: 10`, not for `let s5: CGFloat = 13`, and
/// `RadiusLadderRatchetTests` reads the render, where a token nobody has adopted
/// yet draws nothing at all. So the declaration is the one place with no guard
/// over it, which is where a ladder would quietly stop being one.
///
/// Written literally on purpose: both sides spelling the numbers out is what
/// makes this a check rather than a restatement — change either and it fails.
final class LaddersAreTheStepsTheyClaimTests: XCTestCase {

    private static let space: [CGFloat] = [
        HelmSpace.s1, HelmSpace.s2, HelmSpace.s3, HelmSpace.s4,
        HelmSpace.s5, HelmSpace.s6, HelmSpace.s7, HelmSpace.s8,
    ]

    private static let radius: [CGFloat] = [
        HelmRadius.tiny, HelmRadius.ctl, HelmRadius.card, HelmRadius.frame, HelmRadius.panel,
    ]

    func testTheSpaceLadderIsTheEightStepsItNames() {
        XCTAssertEqual(Self.space, [2, 4, 6, 8, 12, 18, 28, 40],
                       "the ladder in `HelmSpace`'s own documentation is not what it declares")
    }

    func testTheRadiusLadderIsTheFiveStepsItNames() {
        XCTAssertEqual(Self.radius, [4, 6, 10, 14, 26],
                       "the ladder in `HelmRadius`'s own documentation is not what it declares")
    }

    /// The card is the step v3 moved it to, and the one value in either ladder
    /// that had a predecessor: `HelmSurface.cardRadius` was 12, on no step.
    func testTheCardIsTenAndNothingElseIs() {
        XCTAssertEqual(HelmRadius.card, 10)
        XCTAssertEqual(Self.radius.filter { $0 == 10 }.count, 1, "one step is 10 pt")
    }

    // MARK: - The shape a ladder has to have, whatever the numbers are

    /// A step follows the one under it, or two names mean one size and a call
    /// site's choice between them says nothing.
    func testEveryStepIsLargerThanTheOneBelowIt() {
        for ladder in [Self.space, Self.radius] {
            for (lower, upper) in zip(ladder, ladder.dropFirst()) {
                XCTAssertGreaterThan(upper, lower, "\(ladder) is not ascending")
            }
        }
    }

    /// And the gaps never shrink, which is the claim both comments make about
    /// *why* these numbers: dense where the values are small, because 2 pt is
    /// visible at 4 pt and invisible at 40, and spreading out from there.
    func testTheGapsNeverShrinkGoingUp() {
        for ladder in [Self.space, Self.radius] {
            let gaps = zip(ladder, ladder.dropFirst()).map { $1 - $0 }
            for (lower, upper) in zip(gaps, gaps.dropFirst()) {
                XCTAssertGreaterThanOrEqual(upper, lower,
                                            "the gaps in \(ladder) are \(gaps), which narrows")
            }
        }
    }

    /// Above the dense end, a step is between a third and two thirds larger than
    /// the one below — near enough that anything drawn by eye has one obvious
    /// neighbour to round to, far enough that the neighbour is not ambiguous.
    func testTheUpperStepsGrowByAboutHalfAgain() {
        for ladder in [Array(Self.space.dropFirst(3)), Array(Self.radius.dropFirst(2))] {
            for (lower, upper) in zip(ladder, ladder.dropFirst()) {
                let factor = Double(upper / lower)
                XCTAssertGreaterThanOrEqual(factor, 1.33, "\(lower) → \(upper)")
                XCTAssertLessThanOrEqual(factor, 1.90, "\(lower) → \(upper)")
            }
        }
    }
}
