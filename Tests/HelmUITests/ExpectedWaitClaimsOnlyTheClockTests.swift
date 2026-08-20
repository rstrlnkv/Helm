import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// **What `HelmExpectedWait` is allowed to say, and the one thing it must never
/// say.**
///
/// The component exists because a port reports a run starting and a run
/// stopping and nothing in between, and somebody still has to be told how the
/// wait is going. Everything it draws is therefore derived from a clock, and
/// `HelmExpectedWait.Claim.at` is that derivation entire — so these are tests of
/// arithmetic, and they are the only part of this design that a test *can*
/// reach. They prove the rule. They do not prove anything is on screen:
/// `ExpectedWaitMotionProbe` is where that is measured, in pixels, because a
/// modifier's presence in a diff proves its spelling and no more.
final class ExpectedWaitClaimsOnlyTheClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The three honest cases

    func testAWaitNobodySawBeginMakesNoClaim() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0, started: nil, expected: 22), .unknown)
    }

    func testHalfWayThroughTheExpectedLengthIsHalf() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0.addingTimeInterval(11),
                                                 started: t0, expected: 22),
                       .within(0.5))
    }

    func testTheMomentItBeginsIsZeroAndNotUnknown() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0, started: t0, expected: 22), .within(0))
    }

    // MARK: - The lie with a deadline

    /// **The whole point of the design, as one assertion.**
    ///
    /// A bar that reaches the end of its track and waits there is telling
    /// somebody the work is finished when it is not, and it goes on telling them
    /// for as long as the overrun lasts. So the fraction is defined on a half
    /// open interval: at the expected length exactly, and at every instant
    /// after it, the claim is withdrawn rather than parked.
    ///
    /// Sampled across two full expected lengths rather than at the boundary
    /// alone, because a boundary test passes against `elapsed <= expected` for
    /// every value that is not the boundary.
    func testTheClaimIsWithdrawnRatherThanParkedAtTheEnd() {
        let expected: TimeInterval = 22
        var parked: [Double] = []
        for step in 0...440 {
            let now = t0.addingTimeInterval(Double(step) * 0.1)
            switch HelmExpectedWait.Claim.at(now, started: t0, expected: expected) {
            case .within(let fraction):
                XCTAssertLessThan(fraction, 1,
                                  "the arc reached the end of its own track at "
                                  + "\(Double(step) * 0.1) s and is still claiming")
                if fraction >= 0.999 { parked.append(fraction) }
            case .overrun:
                XCTAssertGreaterThanOrEqual(Double(step) * 0.1, expected,
                                            "it gave up before the expected length")
            case .unknown:
                XCTFail("a wait with a start and a length is neither unknown")
            }
        }
        XCTAssertTrue(parked.isEmpty, "it dwelt at the end of the track: \(parked)")
    }

    func testPastTheExpectedLengthItSaysSoInsteadOfSittingAtTheEnd() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0.addingTimeInterval(22),
                                                 started: t0, expected: 22), .overrun)
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0.addingTimeInterval(60),
                                                 started: t0, expected: 22), .overrun)
    }

    /// And it climbs the whole way there — a claim that stalls somewhere in the
    /// middle is the same defect one instant earlier.
    func testItClimbsStrictlyForTheWholeExpectedLength() {
        var last = -1.0
        for step in 0..<220 {
            guard case .within(let fraction) =
                    HelmExpectedWait.Claim.at(t0.addingTimeInterval(Double(step) * 0.1),
                                              started: t0, expected: 22)
            else { return XCTFail("withdrawn inside the expected length, at step \(step)") }
            XCTAssertGreaterThan(fraction, last, "it stalled at step \(step)")
            last = fraction
        }
    }

    // MARK: - Refusals, all in the safe direction

    /// A wait of no length is not a wait, and dividing by it is how a fraction
    /// becomes an infinity somewhere inside `trim(from:to:)`.
    func testAWaitOfNoLengthMakesNoClaim() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0, started: t0, expected: 0), .unknown)
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0, started: t0, expected: -5), .unknown)
    }

    /// A laptop resuming, or an NTP step under a running measurement. A negative
    /// elapsed time is not a small fraction; it is the stamp saying it cannot be
    /// trusted, and the answer is the indeterminate control rather than an arc
    /// drawn backwards.
    func testAClockThatWentBackwardsMakesNoClaim() {
        XCTAssertEqual(HelmExpectedWait.Claim.at(t0.addingTimeInterval(-3),
                                                 started: t0, expected: 22), .unknown)
    }

    // MARK: - Reduce Motion

    /// **Not «shorter», and not «off».** The setting moves the *schedule*: the
    /// arc is redrawn once a second instead of at display rate, so it steps
    /// where it used to glide and still answers the question it was put there
    /// to answer.
    ///
    /// Asserted as arguments, the shape `HelmMotion.spins(requested:reduceMotion:)`
    /// established — a check that reads `NSWorkspace` proves only that the
    /// machine it ran on was set the way the test assumed.
    func testReduceMotionPutsASecondUnderEveryRedraw() {
        XCTAssertEqual(HelmExpectedWait.tick(reduceMotion: true), 1)
        XCTAssertNil(HelmExpectedWait.tick(reduceMotion: false))
    }

    // MARK: - The handover moves nothing

    /// The arc becomes the indeterminate spinner mid-run, in a row that also
    /// holds a word and, beside it, the tunnel switcher. If the two faces are
    /// not the same size the row reflows at the moment of handover, which is a
    /// page twitching at a person who is waiting and looking elsewhere.
    ///
    /// `fittingSize` is the right instrument here and the wrong one two files
    /// over: it answers with where a layout is *heading*, which is useless for a
    /// ramp and exactly what is wanted for a settled state.
    @MainActor
    func testBothFacesTakeTheSameSpaceSoTheRowDoesNotTwitch() {
        let ramping = NSHostingView(rootView: HelmExpectedWait(started: Date(), expected: 22))
        let withdrawn = NSHostingView(rootView: HelmExpectedWait(started: nil, expected: 22))
        XCTAssertEqual(ramping.fittingSize, withdrawn.fittingSize)
        XCTAssertEqual(ramping.fittingSize, NSSize(width: 16, height: 16))
    }
}
