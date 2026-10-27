import XCTest
@testable import HelmRuntime

final class StatusPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - Which frame belongs to now

    private let frames = 36

    /// The clamp did not protect the conversion, because the conversion was
    /// inside it: `min(max(Int(phase * Double(frameCount)), 0), frameCount - 1)`
    /// evaluates `Int(_:)` first, and `Int(_:)` traps on anything outside `Int`'s
    /// range. So the bounds that exist to keep the index sane never saw the
    /// number — the process was already gone.
    ///
    /// This is the KeepAwake family one target over. `spinUntil` reaches the host
    /// from a module, over JSON, as a `Date`, and a `Date` is a `Double` of
    /// seconds: nothing between the payload and this line says how large. The
    /// module writing it is not the check.
    ///
    /// Asserted as the property the host needs — a subscript that exists — rather
    /// than as a particular index, so a fix may choose either end.
    func testASpinFartherOffThanIntCanHoldStillDrawsAFrame() {
        for wild in [1e300, .greatestFiniteMagnitude, Double.infinity] {
            let spinUntil = Date(timeIntervalSinceReferenceDate: wild)
            guard let frame = StatusPlan.frame(spinUntil: spinUntil, now: now,
                                               frameCount: frames) else { continue }
            XCTAssertTrue((0..<frames).contains(frame),
                          "a spinUntil of \(wild) gave \(frame), which is not an index "
                          + "of the array the host is about to subscript")
        }
    }

    /// The other half of the same arithmetic, and the reason the fix cannot stop
    /// at moving the conversion outwards. Bounding a `Double` cannot remove a NaN
    /// — `max(.nan, 0)` is NaN and `min(.nan, high)` is NaN — and `phase` is
    /// infinite for a wild `spinUntil`, so `phase * 0` is NaN and the conversion
    /// traps again on the far side of a clamp that looks right.
    ///
    /// An empty array has no index either way, which is the answer.
    func testAnEmptyFrameArrayHasNoFrameToDraw() {
        XCTAssertNil(StatusPlan.frame(spinUntil: now.addingTimeInterval(0.5), now: now,
                                      frameCount: 0),
                     "there is no still to draw, and -1 is not one")
        XCTAssertNil(StatusPlan.frame(spinUntil: Date(timeIntervalSinceReferenceDate: .infinity),
                                      now: now, frameCount: 0))
    }
}
