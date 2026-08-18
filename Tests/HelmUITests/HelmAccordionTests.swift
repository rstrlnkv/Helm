import XCTest
import SwiftUI
import AppKit
import HelmTestSupport
@testable import HelmUI

/// The two modifiers the app's hand-written reveals were folded into, measured
/// rather than read.
///
/// **Every claim here is about pixels over time**, because none of it can be
/// seen any other way: `fittingSize`, `onGeometryChange` and `GeometryReader`
/// all answer with the size an animation is *heading for*, so a probe built on
/// one of them reads a clean step where the screen shows a ramp. And every ramp
/// has its control — the same view, the same sampler, the transaction taken
/// away — because without one these pass on a machine that animates everything
/// by default, which is the shape of a check that cannot fail.
@MainActor
final class HelmAccordionTests: XCTestCase {

    private final class Box: ObservableObject {
        @Published var open = false
        @Published var rows = 2
        /// A height nothing measured, for the control: written raw, by hand.
        @Published var raw: CGFloat = 0
    }

    /// The accordion under test: a block of literal-coloured rows, the modifier,
    /// and a bar under it so something moves when the block does.
    private struct Bench: View {
        @ObservedObject var box: Box
        @State private var measured: CGFloat?
        var body: some View {
            VStack(spacing: 0) {
                rows.helmAccordion(open: box.open, height: $measured)
                Color.black.frame(height: 8)
                Spacer(minLength: 0)
            }
        }

        /// `Color.primary.opacity` and not `.secondary`: inside a block whose
        /// height animates, `.clipped()` wants a layer of its own and a
        /// hierarchical style resolves again when it goes away.
        private var rows: some View {
            VStack(spacing: 4) {
                ForEach(0..<box.rows, id: \.self) { _ in
                    Color.primary.opacity(0.9).frame(height: 24)
                }
                // A named element inside the block: what VoiceOver reaches for.
                Text(HelmAccordionTests.marker)
            }
        }
    }

    /// The control's own view: the same drawing with the same bar under it, and
    /// a height written by hand with no transaction anywhere near it.
    private struct RawBench: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(spacing: 0) {
                Color.primary.opacity(0.9)
                    .frame(height: box.raw)
                    .clipped()
                Color.black.frame(height: 8)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sampling

    /// Top edge of the black bar, in raw pixels — never rounded to points,
    /// because at 2x two rows are one point and rounding throws away half the
    /// resolution of the thing being counted.
    private func barTop(_ view: NSView) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel == 4
        else { return -1 }
        let step = 4
        let columns = (rep.pixelsWide + step - 1) / step
        for y in 0..<rep.pixelsHigh {
            var dark = 0
            for x in Swift.stride(from: 0, to: rep.pixelsWide, by: step) {
                let at = y * rep.bytesPerRow + x * 4
                if data[at + 3] > 229, data[at] < 51, data[at + 1] < 51, data[at + 2] < 51 {
                    dark += 1
                }
            }
            if dark * 10 >= columns * 9 { return y }
        }
        return -1
    }

    private func mounted<V: View>(_ view: V) -> (NSWindow, NSHostingView<V>) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        // Pinned by name. `NSApp.effectiveAppearance` in a test process is
        // whatever this Mac is set to that hour, and the bar is read as «dark».
        window.appearance = NSAppearance(named: .aqua)
        host.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 400)
        window.layoutIfNeeded()
        return (window, host)
    }

    /// Settles, makes the change, then reads every 20 ms for 400 ms — longer
    /// than `disclosure`, so a ramp finishes inside the window.
    private func series<V: View>(_ view: V, change: @escaping () -> Void) -> [Int] {
        let (window, host) = mounted(view)
        for _ in 0..<40 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        var samples: [Int] = []
        change()
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            samples.append(barTop(host))
        }
        window.contentView = nil
        return samples
    }

    /// Samples that are neither where the value started nor where it ended.
    ///
    /// **Counting distinct values is not measuring travel**, and it is not
    /// stable either: a ramp sampled every 20 ms lands in three or four buckets
    /// depending on what else the machine is doing. What tells a ramp from a cut
    /// is whether anything was drawn *between* the two ends — a cut has none
    /// however often it is sampled.
    private func intermediates(_ samples: [Int]) -> Int {
        let good = samples.filter { $0 > 0 }
        guard let first = good.first, let last = good.last else { return 0 }
        return Set(good.filter { $0 != first && $0 != last }).count
    }

    // MARK: - The gate

    /// Opening it grows the block rather than switching it on.
    func testTheBlockGrowsWhenItOpens() throws {
        let box = Box()
        let samples = series(Bench(box: box)) {
            withAnimation(HelmMotion.disclosure) { box.open = true }
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(intermediates(samples), 3,
                                    "the block was drawn at \(intermediates(samples)) height(s) "
                                    + "between shut and open, which is a cut: \(samples)")
    }

    /// The control for it. Without this the test above passes on a machine that
    /// animates by default.
    func testAHeightWrittenWithNoTransactionArrivesInOneStep() throws {
        let box = Box()
        let samples = series(RawBench(box: box)) { box.raw = 120 }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertEqual(intermediates(samples), 0,
                       "the machine animates an unanimated write: \(samples)")
    }

    // MARK: - The measurement

    /// **The half that cannot come from the call site.** The block is already
    /// open and its content changes height, with no `withAnimation` anywhere
    /// near the change — which is what an engine publishing a value looks like.
    /// The only thing that can make this travel is the write inside the
    /// modifier's own geometry callback.
    ///
    /// Its control is the test above: the same sampler, the same bar, a height
    /// written raw, arriving in one step.
    func testALaterMeasurementTravelsWithNoTransactionAtTheCallSite() throws {
        let box = Box()
        box.open = true
        let samples = series(Bench(box: box)) { box.rows = 6 }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(intermediates(samples), 3,
                                    "the measurement landed in one frame: \(samples)")
    }

    /// **And the first measurement is not a change.** Animated, it plays the
    /// block collapsing from whatever the unmeasured layout happened to be —
    /// on the first frame anybody sees. Sampled from the mount rather than
    /// after it, so the frames under test are the ones the page opens with.
    func testTheFirstMeasurementDoesNotAnimate() throws {
        let box = Box()
        box.open = true
        let (window, host) = mounted(Bench(box: box))
        var samples: [Int] = []
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            samples.append(barTop(host))
        }
        window.contentView = nil
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertEqual(intermediates(samples), 0,
                       "the block was still arriving at its first measured height: \(samples)")
    }

    // MARK: - What the clip does not hide

    /// `.clipped()` takes a view off the screen and leaves it in the
    /// accessibility tree: VoiceOver read both of Keep Awake's collapsed rows
    /// aloud before the gate was added, and a modifier a caller can forget it on
    /// ships a focusable invisible bar to every call site.
    ///
    /// **Read out of the source, and that is a compromise with a reason.** The
    /// honest check is behavioural — mount it collapsed and ask AppKit what an
    /// assistive client would reach — and it is not reachable from here: SwiftUI
    /// builds its accessibility tree when a client connects, so an offscreen
    /// `NSHostingView` in a test process answers `accessibilityChildren()` with
    /// **0** even with the block wide open. Measured before this was written; a
    /// test asserting an absence against an empty tree is an absence that proves
    /// nothing, so it is not the check that shipped. What is left is the next
    /// best thing: the gate is not an argument a call site passes, so it is
    /// enough that these two lines are in the one body that has them.
    func testTheClipCannotShipWithoutTheGate() throws {
        let source = try RepoSource.text(of: Self.modifierFile)
        XCTAssertTrue(source.contains(".clipped()"),
                      "the accordion no longer clips — this guard is about a clip")
        XCTAssertTrue(source.contains(".accessibilityHidden(!open)"),
                      "a collapsed block is off the screen and still in the accessibility tree")
        XCTAssertTrue(source.contains(".allowsHitTesting(open)"),
                      "a collapsed block is off the screen and still answers the pointer")
    }

    /// And neither gate is a parameter with a permissive default: a caller
    /// cannot ask for the clip without them.
    func testNeitherGateIsSomethingACallSitePasses() throws {
        // To `-> some View`, so the *whole* parameter list is read. The first
        // spelling stopped at the first `{` and cut the last parameter off —
        // which passed against a mutant that added exactly the argument this
        // forbids. A scan that reads less than it claims to is the check that
        // cannot fail, in miniature.
        let source = try RepoSource.text(of: Self.modifierFile)
        guard let opens = source.range(of: "func helmAccordion"),
              let closes = source.range(of: "-> some View", range: opens.upperBound..<source.endIndex)
        else { return XCTFail("the modifier was renamed or is no longer a function") }
        let signature = String(source[opens.lowerBound..<closes.upperBound])
        for word in ["accessibilityHidden", "allowsHitTesting", "hidden", "hitTesting"] {
            XCTAssertFalse(signature.contains(word),
                           "«\(word)» is an argument of \(signature.trimmingCharacters(in: .whitespaces))")
        }
    }

    private static let modifierFile = "Sources/HelmUI/DesignSystem/HelmAccordion.swift"

    /// A word nothing else in the tree says.
    fileprivate static let marker = "zebracrossing"
}
