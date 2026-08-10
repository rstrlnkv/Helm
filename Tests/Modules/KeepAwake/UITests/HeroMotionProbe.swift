import XCTest
import SwiftUI
import AppKit
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The Keep Awake hero swaps one state for another and changes the height of
/// the page it is the top of, with the whole settings form underneath.
///
/// Measured in pixels, because every layout API answers with where an animation
/// is *heading*: `fittingSize`, `onGeometryChange` and `GeometryReader` all
/// compute the destination and report it at the first frame, so a probe built
/// on any of them reads a clean step where the screen shows a ramp.
///
/// Two readings, each anchored on something that moves with what it measures:
/// the top edge of a black bar drawn directly under the hero (a fixed rectangle
/// would have measured the hero's own text passing it), and the alpha mass of
/// the figure's band, which is a straight line in the cross-fade's progress
/// because everything drawn there is dark type on nothing.
///
/// **The sampler reads raw bytes, and that is not a detail.** The first version
/// used `NSBitmapImageRep.colorAt(x:y:)` and cost 140 ms a frame — timestamped
/// on the loop: `[155, 297, 459, 591 …]`. Twenty "20 ms" samples covered 1.4 s
/// at seven frames a second, so a 0.30 s transition was three readings and a
/// guess, and the hero's cross-fade looked like a jump because of the
/// instrument. `bitmapData` brings the same twenty samples inside 400 ms.
@MainActor
final class HeroMotionProbe: XCTestCase {

    private final class Box: ObservableObject {
        @Published var state: SessionHero = .idle
        @Published var suppressed = false
        /// The controls' own value, changed with no transaction anywhere near
        /// it. Nothing in the hero reads it.
        @Published var flipped = false
        /// The tick the page's `TimelineView` would hand over.
        @Published var tick = Date(timeIntervalSince1970: 1_700_000_000)
    }

    /// A fixed clock: the countdown must not tick inside the 400 ms being
    /// sampled, or the numeric transition redraws the figure in the middle of
    /// the measurement of something else.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Harness: View {
        @ObservedObject var box: Box
        /// The settings column by default — the width the hero is really drawn
        /// at, and the width at which all four states measure the same 137 pt.
        /// A narrower one is how a test gets a height change to look at: the
        /// preset row wraps, and `.automatic` (six controls) folds a line
        /// before `.idle` (five) does.
        var width: CGFloat = HelmLayout.settingsColumn
        var body: some View {
            VStack(spacing: 0) {
                KeepAwakeHero(state: box.state,
                              now: box.tick,
                              anyRuleOn: true,
                              defaultDurationMinutes: 60,
                              suppressed: box.suppressed,
                              ruleHolds: true,
                              timedNote: { _ in "until 15:42" },
                              start: { _ in }, stop: {}, resume: {})
                // The form, in one bar. It is what somebody is reading while
                // the hero changes, and where it sits is the whole question.
                Color.black.frame(height: 12)
                Spacer(minLength: 0)
            }
            .frame(width: width)
        }
    }

    /// The control for the height reading: a height written with no transaction,
    /// in the same window, read by the same sampler, moving the same bar.
    private struct HeightControl: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: box.flipped ? 260 : 140)
                Color.black.frame(height: 12)
                Spacer(minLength: 0)
            }
            .frame(width: HelmLayout.settingsColumn)
        }
    }

    /// The control for the countdown: the same figure with the same content
    /// transition on it and no animation anywhere near the change — which is
    /// what the page shipped, and why the digits cut.
    private struct DigitControl: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(spacing: 0) {
                Text(box.flipped ? "0:59:59" : "1:00:00")
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .tracking(-2)
                    .contentTransition(.numericText(countsDown: true))
                Spacer(minLength: 0)
            }
            .frame(width: HelmLayout.settingsColumn)
        }
    }

    /// The control for the fade reading: the hero's own shape — a `Group`, two
    /// branches, a transition on each — with no transaction at all.
    private struct FadeControl: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(spacing: 0) {
                Group {
                    if box.flipped {
                        Text("1:00:00").font(.system(size: 40, weight: .light))
                            .transition(.opacity)
                    } else {
                        Text(KAStr.heroIdle).font(.system(size: 40, weight: .light))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(width: HelmLayout.settingsColumn)
        }
    }

    // MARK: - Sampling

    /// The whole window's pixels, once, as bytes.
    private func pixels<V: View>(_ host: NSHostingView<V>) -> (NSBitmapImageRep, UnsafeMutablePointer<UInt8>)? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel == 4
        else { return nil }
        return (rep, data)
    }

    /// The top edge of the black bar, in raw pixels — not rounded to points,
    /// because at 2x two neighbouring rows are one point and rounding throws
    /// away half the resolution of the thing being counted. A row is the bar
    /// when nearly every column in it is opaque and dark: the hero's own 40 pt
    /// type and its accent-filled button are dark too, and neither is 744 pt
    /// wide.
    private func barTop<V: View>(_ host: NSHostingView<V>) -> Int {
        guard let (rep, data) = pixels(host) else { return -1 }
        let step = 8, row = rep.bytesPerRow
        let columns = (rep.pixelsWide + step - 1) / step
        for y in 0..<rep.pixelsHigh {
            var dark = 0
            for x in Swift.stride(from: 0, to: rep.pixelsWide, by: step) {
                let p = y * row + x * 4
                if data[p + 3] > 229, data[p] < 51, data[p + 1] < 51, data[p + 2] < 51 { dark += 1 }
            }
            if dark * 10 >= columns * 9 { return y }
        }
        return -1
    }

    /// How much is drawn in a band, as the sum of the alpha channel. Everything
    /// in the figure's band is dark type on a transparent view, so a cross-fade
    /// between two of them is a straight line between two sums.
    private func alphaMass<V: View>(_ host: NSHostingView<V>, band: Range<Int>) -> Int {
        guard let (rep, data) = pixels(host) else { return -1 }
        var mass = 0
        for y in band.clamped(to: 0..<rep.pixelsHigh) {
            for x in Swift.stride(from: 0, to: rep.pixelsWide, by: 4) {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    /// Installs a view, lets it settle, makes the change and reads every 20 ms
    /// for 400 ms — longer than `disclosure`, so a ramp finishes inside the
    /// window rather than being cut off by it.
    private func series<V: View>(_ view: V, sample: (NSHostingView<V>) -> Int,
                                 change: () -> Void) -> [Int] {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 780, height: 460)
        window.layoutIfNeeded()
        for _ in 0..<30 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }

        var samples: [Int] = []
        change()
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            samples.append(sample(host))
        }
        window.contentView = nil
        return samples
    }

    private func steps(_ samples: [Int]) -> Int { Set(samples.filter { $0 > 0 }).count }

    // MARK: - The controls
    //
    // Neither is optional. Without them every ramp below passes on a machine
    // that animates by default, which is the shape of a check that cannot fail.

    /// A height written with no transaction arrives in one step.
    func testAHeightWrittenWithNoTransactionArrivesInOneStep() throws {
        let box = Box()
        let samples = series(HeightControl(box: box), sample: barTop) { box.flipped = true }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertLessThanOrEqual(steps(samples), 2,
                                 "the machine animates an unanimated write: \(samples)")
    }

    /// And so does a `.transition(.opacity)` with no transaction around the
    /// change — a transition is an instruction for an animation, not one.
    func testASwapWithNoTransactionArrivesInOneStep() throws {
        let box = Box()
        let samples = series(FadeControl(box: box), sample: { alphaMass($0, band: 0..<130) }) {
            box.flipped = true
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertLessThanOrEqual(steps(samples), 2, "the machine fades by itself: \(samples)")
    }

    // MARK: - The hero

    /// Starting a timer: the sentence in the figure's slot becomes a countdown,
    /// the line under it changes and the fourth button goes. Nothing about that
    /// can be interpolated — they are different views — so what has to be
    /// measured is the cross-fade.
    func testTheStatesCrossFade() throws {
        let box = Box()
        let samples = series(Harness(box: box), sample: { alphaMass($0, band: 0..<130) }) {
            box.state = .timed(until: HeroMotionProbe.now.addingTimeInterval(3600))
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 4,
                                    "the figure was replaced in \(steps(samples)) step(s), "
                                    + "which is a cut: \(samples)")
    }

    /// The countdown's own digits. `.contentTransition(.numericText)` was
    /// already on this figure and did nothing: a content transition is not an
    /// animation, it is an instruction for one, and the `Text` sits inside a
    /// `TimelineView` that rebuilds it every second with no transaction
    /// anywhere near it.
    func testTheDigitsRollRatherThanCut() throws {
        let box = Box()
        box.state = .timed(until: HeroMotionProbe.now.addingTimeInterval(3600))
        let samples = series(Harness(box: box), sample: { alphaMass($0, band: 0..<130) }) {
            box.tick = HeroMotionProbe.now.addingTimeInterval(1)
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 4,
                                    "the figure changed in \(steps(samples)) step(s): \(samples)")
    }

    /// The control for it, and it is the code this replaced.
    func testTheSameFigureWithNoAnimationCuts() throws {
        let box = Box()
        let samples = series(DigitControl(box: box), sample: { alphaMass($0, band: 0..<130) }) {
            box.flipped = true
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertLessThanOrEqual(steps(samples), 2,
                                 "a content transition animated itself: \(samples)")
    }

    /// One state is a line of buttons taller than another: the form under the
    /// hero has to travel rather than jump.
    ///
    /// **Measured at 460 pt, not at the settings column, and that is the point
    /// of the test rather than an inconvenience.** The caption about Stop used
    /// to live inside `.automatic`, which made that state permanently taller
    /// than `.idle`; moved out under the block — because it made pressing «15
    /// min» shove the whole form down, which
    /// `testStartingATimerDoesNotMoveTheFormAtAll` exists to forbid — every
    /// state measures the same 137 pt at the real width, and the setup this
    /// test had could no longer produce the thing it was watching. A guard
    /// whose subject cannot happen is not a guard.
    ///
    /// What does still change the block's height is the preset row folding, and
    /// it folds at different widths for different states because they carry
    /// different numbers of controls. Measured across the range:
    /// `744: idle=137 auto=137`, `520: 137/137`, **`460: idle=137 auto=173`**,
    /// `420: 220/173`. So 460 is a width where exactly one of the two has
    /// wrapped, which is a 36 pt change to ramp through — and it is also the
    /// only assertion anywhere that `HelmWrappingRow` wraps at all.
    func testTheBlockRampsWhenTheStateChangesHeight() throws {
        let box = Box()
        box.state = .automatic([.externalDisplay])
        let samples = series(Harness(box: box, width: 460), sample: barTop) { box.state = .idle }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 3,
                                    "the page reached its new height in \(steps(samples)) "
                                    + "step(s): \(samples)")
    }

    /// And at the width it is actually drawn at, no state swap moves the form
    /// at all — which is the other half of the sentence above, and the reason
    /// the test before it had to be re-aimed.
    func testAtTheRealWidthEveryStateIsTheSameHeight() throws {
        let box = Box()
        box.state = .automatic([.externalDisplay])
        let samples = series(Harness(box: box), sample: barTop) { box.state = .idle }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertEqual(steps(samples), 1,
                       "a state swap moved the form under it: \(samples)")
    }

    /// The silenced-rule row, which arrives on the engine's say-so while
    /// somebody is reading the page. It used to be a bare `if`.
    func testTheSuppressionRowGrowsThePage() throws {
        let box = Box()
        let samples = series(Harness(box: box), sample: barTop) { box.suppressed = true }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 4,
                                    "the row appeared in \(steps(samples)) step(s): \(samples)")
    }

    /// And the one thing that must not move: `.idle` and `.timed` are the same
    /// height by design, so the form below stays exactly where it was while the
    /// figure above it changes. A page that shifted here would be the block
    /// being re-measured rather than swapped.
    func testStartingATimerDoesNotMoveTheFormAtAll() throws {
        let box = Box()
        let samples = series(Harness(box: box), sample: barTop) {
            box.state = .timed(until: HeroMotionProbe.now.addingTimeInterval(3600))
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertEqual(steps(samples), 1, "the form moved: \(samples)")
    }
}
