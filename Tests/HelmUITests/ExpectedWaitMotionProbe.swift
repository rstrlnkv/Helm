import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// **Whether the arc is actually on screen, and actually moving.**
///
/// The tests next door prove the arithmetic; nothing about them would change if
/// the view drew a still circle, or drew nothing at all. So this hosts the real
/// component in a real window and counts its ink every 20 ms, which is the only
/// instrument that can tell a ramp from a picture of one.
///
/// **`cacheDisplay` can see this, and it cannot see most animations.** It
/// renders the *model* values of layers, so it is blind to an interpolation in
/// flight — which is why the Keep Awake probe next door exists in the shape it
/// does. This component has no interpolation: a `TimelineView` rebuilds the arc
/// from `context.date`, so every frame the sampler catches is a model value
/// somebody put there. That is a property of the design rather than a
/// convenience, and it is most of why the design is a clock rather than a
/// twenty-second `withAnimation`.
///
/// **The control, because a ramp test without one is a check that cannot
/// fail.** The usual control — the same view with the transaction removed —
/// does not exist here, because there is no transaction to remove. What could
/// make this pass while nothing moved is a *sampler* that reports change where
/// there is none, and the control for that is the same component with the same
/// schedule and one parameter different: an expected length of an hour, over
/// which four hundred milliseconds moves the arc by a fifth of a degree. Same
/// view, same window, same sampler, and it must arrive as one reading.
///
/// **What this cannot reach.** Reduce Motion moves the redraw *schedule* rather
/// than any curve (`HelmExpectedWait.tick(reduceMotion:)`), and the only way to
/// render that path is to turn the setting on — which is the machine's state
/// and not a test's to change. So the rule is asserted as arguments next door
/// and the one expression that carries it into `TimelineView`'s
/// `minimumInterval` is read, not measured. This machine had the setting off
/// while these numbers were taken, so what is measured below is the glide.
@MainActor
final class ExpectedWaitMotionProbe: XCTestCase {

    /// Drawn large. The shipped size is 16 pt, where a whole second of a
    /// twenty-two second wait is under a point of arc — a real ramp that no
    /// sampler could separate from noise. The thing being measured is whether
    /// the trim follows the clock, and that is scale-free.
    private static let diameter: CGFloat = 200

    // MARK: - Sampling

    /// The window's ink, as the sum of the alpha channel.
    ///
    /// Raw bytes, not `colorAt(x:y:)`. The probe one module over timestamped
    /// that call at 140 ms a frame, which turned twenty "20 ms" samples into
    /// 1.4 s of wall clock at seven frames a second — an instrument slower than
    /// the thing it was measuring, and it made a ramp look like a jump.
    private func ink<V: View>(_ host: NSHostingView<V>) -> Int {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel == 4
        else { return -1 }
        var mass = 0
        for y in 0..<rep.pixelsHigh {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    /// Installs a view in a real window and reads it every 20 ms for 400 ms.
    private func series(expected: TimeInterval) -> [Int] {
        let side = Self.diameter
        let view = HelmExpectedWait(started: Date(), expected: expected, diameter: side)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        window.layoutIfNeeded()
        // Settle before the first reading. The arc starts at zero and the first
        // sample must not be the window still coming up.
        for _ in 0..<10 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }

        var samples: [Int] = []
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            samples.append(ink(host))
        }
        window.contentView = nil
        return samples
    }

    /// How far the ink travelled across the window, as a fraction of where it
    /// started.
    ///
    /// **Counting distinct readings alone was the first instrument here and the
    /// control threw it out**, which is what a control is for. Sampled every
    /// 20 ms the still picture gave *twelve* distinct values — 65 511 climbing
    /// to 65 541, which is 0,046 %: the round cap on a 0,04° arc filling in,
    /// sub-pixel, and utterly invisible. A metric that reports twelve steps of
    /// nothing cannot tell a ramp from a rendering artefact, and it would have
    /// passed with the trim wired to a constant plus dithering. Travel is
    /// scale-aware and the two cases are three orders of magnitude apart.
    private func travel(_ samples: [Int]) -> Double {
        let good = samples.filter { $0 > 0 }
        guard let first = good.first, let last = good.last, first > 0 else { return 0 }
        return Double(last - first) / Double(first)
    }

    /// Distinct readings **at a resolution of one percent of the ink on
    /// screen** — a step somebody could see, rather than a step the byte buffer
    /// can tell apart.
    private func steps(_ samples: [Int]) -> Int {
        let good = samples.filter { $0 > 0 }
        guard let first = good.first, first > 0 else { return 0 }
        let resolution = Swift.max(1, first / 100)
        return Set(good.map { $0 / resolution }).count
    }

    // MARK: - The control

    /// An expected length of an hour. The component redraws exactly as often as
    /// it does below; what changes is that there is nothing to see, and if the
    /// sampler reports a ramp anyway then the reading beneath it means nothing.
    ///
    /// Measured 2026-08-20: 65 511 → 65 541 across the window, 0,05 % travel,
    /// one step at a visible resolution.
    func testAWaitTooLongToSeeArrivesAsOneReading() throws {
        let samples = series(expected: 3600)
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertLessThan(travel(samples), 0.01,
                          "the sampler sees motion in a still picture: \(samples)")
        XCTAssertLessThanOrEqual(steps(samples), 1,
                                 "the sampler sees motion in a still picture: \(samples)")
    }

    // MARK: - The reading

    /// A two-second wait, sampled across a fifth of it. The arc sweeps 72° in
    /// the window, and the ink has to climb through it rather than appear at the
    /// end of it.
    ///
    /// Measured 2026-08-20 on the same machine, same window, same sampler:
    /// 83 403 → 153 033, **83 % travel, monotonic, twenty readings and eighteen
    /// visible steps** — about 4 000 units of ink every 20 ms, which is the arc
    /// growing at display rate. Against the control's 0,05 %.
    func testTheArcClimbsThroughTheWaitRatherThanArrivingAtTheEnd() throws {
        let samples = series(expected: 2)
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThan(travel(samples), 0.2,
                             "the arc did not travel — it is a picture of a clock, "
                             + "not a clock: \(samples)")
        XCTAssertGreaterThanOrEqual(steps(samples), 8,
                                    "the arc arrived rather than climbed: \(samples)")
        XCTAssertEqual(samples, samples.sorted(),
                       "the arc did not grow monotonically: \(samples)")
    }
}
