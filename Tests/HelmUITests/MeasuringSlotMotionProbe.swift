import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// **Whether the edge really travels, and whether the figure really ramps.**
///
/// Two readings, each with a control, because neither claim survives being read
/// off a diff: a `trim` wired to a constant renders a perfectly convincing
/// still border, and a colour written outside a transaction renders a
/// perfectly convincing final colour.
///
/// The two need different samplers, and the reason is the trap this repository
/// already wrote down once — *the colour mass of black text is zero*. Everything
/// here is drawn on a clear backing, so `cacheDisplay` hands back premultiplied
/// pixels in which `Color.primary` and `Color.primary.opacity(0.66)` differ in
/// the **alpha** channel and not at all in RGB. Alpha is therefore the right
/// channel for both, and a luminance sampler would have read the demotion as
/// nothing happening.
@MainActor
final class MeasuringSlotMotionProbe: XCTestCase {

    private final class Box: ObservableObject {
        @Published var measuring = false
    }

    // MARK: - Sampling

    private func rep<V: View>(_ host: NSHostingView<V>) -> (NSBitmapImageRep, UnsafeMutablePointer<UInt8>)? {
        guard let r = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: r)
        guard let d = r.bitmapData, r.bitsPerSample == 8, r.samplesPerPixel == 4 else { return nil }
        return (r, d)
    }

    /// Ink inside a band, as the sum of the alpha channel.
    ///
    /// **The columns are a parameter because the first version of this had to
    /// grow them.** Reading the figure's rows across the full width also read
    /// the border's own left and right edges, so the demotion's series bottomed
    /// out at 114 170 and then climbed back to 118 310 as the segment swept into
    /// the band — a rising tail on a reading that is supposed to be monotonically
    /// falling, caused entirely by the other half of this modifier. A sampler
    /// that measures two things at once is a sampler whose number means neither.
    private func ink<V: View>(_ host: NSHostingView<V>, rows: Range<Int>,
                              cols: ClosedRange<Double> = 0...1) -> Int {
        guard let (r, d) = rep(host) else { return -1 }
        let from = Int(Double(r.pixelsWide) * cols.lowerBound)
        let to = Int(Double(r.pixelsWide) * cols.upperBound)
        var mass = 0
        for y in rows.clamped(to: 0..<r.pixelsHigh) {
            for x in stride(from: from, to: Swift.min(to, r.pixelsWide), by: 2) {
                mass += Int(d[y * r.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    private func series<V: View>(_ view: V, rows: Range<Int>, size: NSSize,
                                 cols: ClosedRange<Double> = 0...1,
                                 settle: Int = 15,
                                 change: () -> Void = {}) -> (band: [Int], whole: Int) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        for _ in 0..<settle { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        var samples: [Int] = []
        change()
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            samples.append(ink(host, rows: rows, cols: cols))
        }
        // **Liveness is asked of the whole frame, never of the band**, and the
        // difference is a control that quietly stopped existing. A frozen
        // segment parks wherever absolute time leaves it, so on the phases where
        // it sits away from the top edge every band reading is a legitimate
        // zero — and a skip keyed on the band then reported «nothing drew — no
        // window server» about a window that had drawn perfectly, once in every
        // few runs, with the suite calling it green. `whole` answers the
        // question that was actually being asked.
        let whole = ink(host, rows: 0..<Int(size.height * 3))
        window.contentView = nil
        return (samples, whole)
    }

    /// Distinct readings at a resolution of one percent of the largest, which is
    /// a step somebody could see rather than one the byte buffer can tell apart.
    /// The instrument the `HelmExpectedWait` control forced, for the same
    /// reason: counting raw distinct values calls antialiasing noise a ramp.
    /// How far the band's ink ranged, as a fraction of its own peak.
    ///
    /// **The control needs this and `steps` cannot give it.** A frozen segment
    /// sits wherever absolute time leaves it, so the control's baseline is
    /// whatever fraction of the segment happens to overlap the band — measured
    /// at 7 493, then 5 628, then 1 873 on three runs of the same test. The
    /// antialiasing drift under a head advancing a twentieth of a pixel is a
    /// flat ten units every time, which is 0,15 % of the first baseline and
    /// 0,53 % of the third, so a threshold in *steps at one percent of the
    /// peak* passed twice and failed the third time. That is a flake, and a
    /// flake gets fixed rather than tolerated: a ratio taken against the peak
    /// scales with the baseline and does not care where the segment parked.
    private func spread(_ samples: [Int]) -> Double {
        let good = samples.filter { $0 >= 0 }
        guard let peak = good.max(), let floor = good.min(), peak > 0 else { return 0 }
        return Double(peak - floor) / Double(peak)
    }

    private func steps(_ samples: [Int]) -> Int {
        let good = samples.filter { $0 >= 0 }
        guard let peak = good.max(), peak > 0 else { return 0 }
        return Set(good.map { $0 / Swift.max(1, peak / 100) }).count
    }

    // MARK: - The edge travels

    /// The border alone, on nothing, so every pixel sampled is the stroke.
    private struct Edge: View {
        let lap: Double
        var body: some View {
            Color.clear.frame(width: 200, height: 90).helmMeasuringSlot(true, lap: lap)
        }
    }

    private static let size = NSSize(width: 200, height: 90)
    /// The top edge of the card, six points of it. The segment sweeps through
    /// this band and out again, so the band's ink rises and falls — where a
    /// still border holds one value and the *whole* border's ink would hold one
    /// value whether it moved or not, which is the sampler this needed instead.
    private static let topBand = 0..<12

    /// **The control.** A lap of an hour: the same view, the same schedule, the
    /// same sampler, and a head that advances a twentieth of a pixel across the
    /// window. If this reports travel then the reading under it means nothing.
    ///
    /// Measured 2026-08-20 over three runs whose baselines were 7 493, 5 628 and
    /// 1 873 — the frozen segment parks where the clock leaves it — and whose
    /// spreads were 0,15 %, 0,20 % and 0,53 %. Against a subject that ranges the
    /// full way from nothing to the whole segment and back.
    func testABorderTooSlowToSeeHoldsOneReading() throws {
        let (samples, whole) = series(Edge(lap: 3600), rows: Self.topBand, size: Self.size)
        try XCTSkipIf(whole <= 0, "nothing drew — no window server")
        XCTAssertLessThan(spread(samples), 0.05,
                          "the sampler sees motion in a still border: \(samples)")
    }

    /// **The reading.** A lap of 400 ms, sampled for 400 ms, so exactly one full
    /// circuit falls inside the window and the segment is guaranteed to cross
    /// the band whatever phase the clock happens to be at — a probe that depends
    /// on the phase it starts in is a flake, and a flake gets deleted rather
    /// than read.
    ///
    /// Measured 2026-08-20, and the shape of the series is the whole claim:
    /// `0, 1 409, 4 762, 9 072, 11 963` — the segment sweeping into the band —
    /// then a plateau, then `9 997, 5 669, 2 758, 0` and nine more zeros as it
    /// carries on round the other three sides. Ten visible steps against the
    /// control's one.
    func testTheSegmentSweepsThroughTheTopOfTheCard() throws {
        let (samples, whole) = series(Edge(lap: 0.4), rows: Self.topBand, size: Self.size)
        try XCTSkipIf(whole <= 0, "nothing drew — no window server")
        XCTAssertGreaterThan(samples.max() ?? 0, 0, "no border was drawn at all")
        XCTAssertGreaterThan(spread(samples), 0.8,
                             "the segment did not sweep clear of the band: \(samples)")
        XCTAssertGreaterThanOrEqual(steps(samples), 6,
                                    "the segment did not travel through the band — "
                                    + "it is a picture of a border: \(samples)")
    }

    // MARK: - The figure steps back

    /// The figure under the real modifier.
    private struct Figure: View {
        @ObservedObject var box: Box
        var body: some View {
            Text("343 ↓  358 ↑").helmMetricFigure()
                .frame(width: 200, height: 90)
                .helmMeasuringSlot(box.measuring)
        }
    }

    /// **The control, and it is the textbook one:** the same demotion, the same
    /// two colours, written with no transaction anywhere near it. A colour that
    /// is merely *assigned* arrives in one step, which is what the card did
    /// before this modifier existed and what it would do again if the
    /// `withAnimation` were dropped from the `onChange`.
    ///
    /// Measured 2026-08-20: **113 632, twenty times, without a single other
    /// value.** A colour is not a thing that eases on its own.
    private struct FigureControl: View {
        @ObservedObject var box: Box
        var body: some View {
            Text("343 ↓  358 ↑").helmMetricFigure()
                .foregroundStyle(HelmMeasuringSlot.ink(measuring: box.measuring))
                .frame(width: 200, height: 90)
        }
    }

    /// The rows the figure's own glyphs occupy, which is where its ink is —
    /// and the middle of the width, which is where the border's edges are not.
    private static let figureBand = 60..<120
    private static let figureColumns = 0.15...0.85

    func testAColourAssignedWithNoTransactionArrivesInOneStep() throws {
        let box = Box()
        let (samples, whole) = series(FigureControl(box: box), rows: Self.figureBand,
                                      size: Self.size, cols: Self.figureColumns) { box.measuring = true }
        try XCTSkipIf(whole <= 0, "nothing drew — no window server")
        XCTAssertLessThanOrEqual(steps(samples), 2,
                                 "the machine animates an unanimated write, so the "
                                 + "ramp below proves nothing: \(samples)")
    }

    /// And the same demotion inside the modifier's own transaction ramps.
    ///
    /// Measured 2026-08-20: 168 094 → 113 390 over thirteen readings, monotonic,
    /// then flat for the last six — `HelmMotion.disclosure`'s 0,30 s, sampled at
    /// 20 ms. **It settles where the control jumps to** (113 390 against
    /// 113 632, the difference being where in the ramp the last sample fell), so
    /// the pair says exactly one thing: the two arrive at the same ink and only
    /// the journey differs.
    func testTheFigureStepsBackOverTimeRatherThanBlinking() throws {
        let box = Box()
        let (samples, whole) = series(Figure(box: box), rows: Self.figureBand,
                                      size: Self.size, cols: Self.figureColumns) { box.measuring = true }
        try XCTSkipIf(whole <= 0, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 4,
                                    "the figure blinked from one ink to the other: \(samples)")
        let good = samples.filter { $0 > 0 }
        XCTAssertLessThan(good.last ?? 0, good.first ?? 0,
                          "the figure did not get quieter: \(samples)")
    }
}
