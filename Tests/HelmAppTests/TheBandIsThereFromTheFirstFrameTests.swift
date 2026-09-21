import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The band the page declares is *there*, not faded into place.**
///
/// `TheWindowsBandReadsTheDeclarationTests` proves the declaration reaches the
/// window's own band and lights it, and it reads every pixel after the window
/// has settled. A band that dissolves into place over a fifth of a second on
/// every page open passes all of it: the readings are taken when the fade is
/// long over.
///
/// The owner's rule is «the background must always be there», and this is the
/// half of it a settled reading cannot see. The defect it was written for:
/// `HelmPageStandsOnStillContentKey` is a preference, so it lands one frame
/// after the page mounts, `lit` goes false → true, and an animation keyed on
/// `lit` reads that first delivery as a change and plays the band arriving
/// from a state it was never in. CLAUDE.md states the rule for a measured
/// height — do not animate the first measurement — and this was the same
/// defect with a `Bool` in place of a `CGFloat`.
///
/// # What makes this a measurement and not a number in a log
///
/// Three panes, all of them the settings window's shape, all of them read in
/// **dark** (the window names its own appearance, so this reading does not
/// belong to the hour the machine was in):
///
/// - the **subject** — a page that declares, traced from the instant the
///   window is built;
/// - the **ramp control** — the same modifier in the same place, lit by a
///   value flipped *after* the window has settled, so what is traced is
///   `HelmMotion.hover`'s own 0,19 s entering curve at its shipping duration.
///   Without it a sampler that cannot see motion at all — an offscreen window
///   whose animation never ticks — would report every band as instant and this
///   file would pass over the defect it exists for;
/// - the **silent pane** — a page that declares nothing, whose band never
///   lights, so «settled at once» cannot be scored by a band that was never on.
///
/// Every reading is taken more than once (`runs`) and the assertions are made
/// against the worst of them.
@MainActor
final class TheBandIsThereFromTheFirstFrameTests: XCTestCase {

    /// How long a trace runs. `HelmMotion.hover(entering: true)` is 0,19 s and
    /// a spring settles asymptotically after it, so a span shorter than this
    /// would read the ramp's tail as its end — CLAUDE.md's «measure at the
    /// shipping duration».
    private static let span: TimeInterval = 0.9

    /// How many times each reading is taken before it is believed.
    private static let runs = 3

    /// A tenth of the band's own excursion, taken from the trace itself rather
    /// than from a constant: the rule's row reads 40,0 unlit and 65,2 lit in
    /// this fixture, so a tenth is 2,5 luma. Far enough down the curve that a
    /// spring's asymptotic tail does not count as motion, coarse enough that
    /// compositing noise does not.
    private static let closeEnough: CGFloat = 0.1

    /// **The ceiling on the subject**, and the whole discrimination this file
    /// is for.
    ///
    /// Measured on this Mac, dark, three runs each. With the band keyed on the
    /// live facts the trace never leaves the settled value at all: the first
    /// readable sample — 137 ms, 33 ms and 36 ms after the window was built,
    /// which is the cost of building it and of the first `cacheDisplay` — is
    /// already 65,2 against 65,2 at 900 ms, so the settle reads **0 ms** three
    /// times. With the animation keyed on `lit` instead, the same trace opens
    /// at 40,0 and settles at **243, 145 and 148 ms**.
    ///
    /// 60 ms sits between the two with room on both sides: half the floor
    /// under the ramp below, and a quarter of the ramp's own measured 112 ms.
    private static let ceiling: Double = 0.060

    /// **The floor under the ramp control.** The same three runs put a real
    /// fade — `HelmMotion.hover(entering:)`'s shipping 0,19 s, measured to the
    /// last tenth of its excursion — at 112, 114 and 115 ms; 80 ms is under
    /// that and well over the ceiling above.
    ///
    /// It is here because a harness that cannot see motion at all reports
    /// every band as instant, and that is indistinguishable from the fix: an
    /// offscreen window whose animation never ticks, a `HelmMotion` collapsed
    /// to a cut, a sampler reading the same cached bitmap every turn. Any of
    /// them trips this before the subject is read.
    private static let rampFloor: Double = 0.080

    // MARK: - The panes

    private final class Flip: ObservableObject {
        @Published var on: Bool
        init(on: Bool) { self.on = on }
    }

    /// The subject and the silent pane: the band applied from outside the page,
    /// exactly where `SettingsSplitViewController` applies it, over a page that
    /// declares or does not.
    private struct Page: View {
        let declares: Bool

        var body: some View {
            Group {
                if declares {
                    ground.helmPageStandsOnStillContent()
                } else {
                    ground
                }
            }
            .helmToolbarBackdrop()
            // A page without one drops the window's toolbar, and with it the
            // safe area the band is drawn in.
            .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }

        /// Flat and opaque: the band's fill and its rule are plain fills over
        /// it, so `cacheDisplay` composites them exactly. The material is not
        /// composited offscreen and nothing here claims it.
        private var ground: some View {
            Color(nsColor: .windowBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The ramp control: the same modifier, in the same overlay, at the same
    /// place in the same window — lit by a value that changes long after the
    /// window has settled, which is a change and not a first delivery.
    private struct Ramp: View {
        @ObservedObject var flip: Flip

        var body: some View {
            Color(nsColor: .windowBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        Color.clear
                            .frame(height: proxy.safeAreaInsets.top)
                            .modifier(HeaderEdgeLight(lit: flip.on, live: flip.on,
                                                      overContent: true))
                            .offset(y: -proxy.safeAreaInsets.top)
                    }
                    .allowsHitTesting(false)
                }
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }

    /// The settings window's shape: `.fullSizeContentView` and a transparent
    /// title bar are what give the pane a 52 pt top safe area for the band to
    /// live in, and a window without them hands `GeometryReader` a zero inset —
    /// which reads exactly like a band that never lit.
    @MainActor private final class Pane {
        /// The settings window's own default, so the band is traced at the
        /// width the app opens at.
        static let width: CGFloat = 1060

        let window: NSWindow
        private var rep: NSBitmapImageRep?

        init(_ root: some View) {
            let controller = NSHostingController(rootView: root)
            controller.sceneBridgingOptions = [.toolbars]
            controller.sizingOptions = []
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: Pane.width, height: 300))
            window.appearance = NSAppearance(named: .darkAqua)
        }

        func settle(_ turns: Int = 30) {
            for _ in 0..<turns {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        /// One turn of the run loop, short enough that a 0,19 s fade is sampled
        /// dozens of times. The cost of reading the pixels is real — CLAUDE.md
        /// says to timestamp the loop rather than count its turns — so every
        /// sample carries the clock rather than an assumed interval.
        func turn() {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
        }

        func drop() { window.contentViewController = nil }

        /// The luma of the one pixel row the rule occupies — the band's largest
        /// excursion, and the row `HeaderEdgeLight` draws its rule in.
        ///
        /// The bitmap is made once and cached: a fresh one per sample costs
        /// more than the interval being measured.
        func edgeLuma() throws -> CGFloat {
            let host = try XCTUnwrap(window.contentView, "the window has no content view")
            let inset = host.safeAreaInsets.top
            guard inset > 1 else {
                throw Failure.noBand(inset)
            }
            let rep = try cachedRep(host)
            host.cacheDisplay(in: host.bounds, to: rep)
            // Points in, pixels out: the rule is one device pixel at the very
            // bottom of the inset, and sampled at the point coordinate it lands
            // halfway up the strip — a rule reported as absent.
            let scale = CGFloat(rep.pixelsHigh) / host.bounds.height
            let y = Int(inset * scale) - 1
            // Far from the traffic lights and far from the trailing edge.
            let x = Int(Pane.width / 2 * CGFloat(rep.pixelsWide) / host.bounds.width)
            let colour = try XCTUnwrap(rep.colorAt(x: x, y: y), "no pixel at \(x), \(y)")
            let rgb = try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
            return (0.299 * rgb.redComponent + 0.587 * rgb.greenComponent
                    + 0.114 * rgb.blueComponent) * 255
        }

        private func cachedRep(_ host: NSView) throws -> NSBitmapImageRep {
            if let rep { return rep }
            let made = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                     "the pane would not cache its display")
            rep = made
            return made
        }

        enum Failure: Error, CustomStringConvertible {
            case noBand(CGFloat)

            var description: String {
                switch self {
                case let .noBand(inset):
                    return """
                        the pane's top safe area is \(inset) pt, so the band has no height to be \
                        drawn in and every reading of it is the ground. The toolbar or \
                        `.fullSizeContentView` has gone from this fixture
                        """
                }
            }
        }
    }

    private var panes: [Pane] = []

    override func tearDown() {
        panes.forEach { $0.drop() }
        panes = []
        super.tearDown()
    }

    private func hold(_ pane: Pane) -> Pane {
        panes.append(pane)
        return pane
    }

    // MARK: - The trace

    private struct Sample {
        let at: Double
        let luma: CGFloat
    }

    /// Reads the band for `span` seconds, timestamping every reading against
    /// `from` — the instant the thing being measured was set going.
    private func trace(_ pane: Pane, from start: CFAbsoluteTime) throws -> [Sample] {
        var samples: [Sample] = []
        repeat {
            pane.turn()
            samples.append(Sample(at: CFAbsoluteTimeGetCurrent() - start,
                                  luma: try pane.edgeLuma()))
        } while CFAbsoluteTimeGetCurrent() - start < Self.span
        return samples
    }

    /// **When the band stopped moving**, in seconds from the instant the trace
    /// was started: the earliest reading from which every reading, itself
    /// included, sits within a tenth of the whole excursion of the last one.
    ///
    /// Not «when it first crossed half way» — a band that is simply *there*
    /// crosses nothing, and this has to give it zero rather than a number off
    /// the sampler's first turn.
    private func settled(_ samples: [Sample]) -> Double {
        guard let last = samples.last, let first = samples.first else { return 0 }
        let excursion = abs(last.luma - first.luma)
        let tolerance = max(excursion * Self.closeEnough, 0.25)
        var answer = 0.0
        for sample in samples where abs(sample.luma - last.luma) > tolerance {
            answer = sample.at
        }
        return answer
    }

    private func report(_ samples: [Sample]) -> String {
        let shown = samples.prefix(6).map { String(format: "%.0f ms %.1f", $0.at * 1000, $0.luma) }
        guard let last = samples.last else { return "nothing was sampled" }
        return shown.joined(separator: " · ")
            + String(format: " … %.0f ms %.1f", last.at * 1000, last.luma)
    }

    // MARK: - The measurement

    func testTheDeclaredBandIsAdoptedWhereAChangeIsAnimated() throws {
        try XCTSkipIf(HelmMotion.reduceMotion, """
            Reduce Motion is on, so `HelmMotion.hover` is a 0,01 s cut and there is no ramp on \
            this machine to measure the band against. The reading this file takes needs the \
            shipping curve
            """)

        var subject: [Double] = []
        var traces: [String] = []
        var lit: [CGFloat] = []
        for _ in 0..<Self.runs {
            let start = CFAbsoluteTimeGetCurrent()
            let pane = hold(Pane(Page(declares: true)))
            let samples = try trace(pane, from: start)
            subject.append(settled(samples))
            traces.append(report(samples))
            lit.append(try XCTUnwrap(samples.last).luma)
        }

        var ramp: [Double] = []
        var ramps: [String] = []
        for _ in 0..<Self.runs {
            let flip = Flip(on: false)
            let pane = hold(Pane(Ramp(flip: flip)))
            pane.settle()
            let start = CFAbsoluteTimeGetCurrent()
            flip.on = true
            let samples = try trace(pane, from: start)
            ramp.append(settled(samples))
            ramps.append(report(samples))
        }

        let silent = hold(Pane(Page(declares: false)))
        silent.settle()
        let dark = try silent.edgeLuma()
        let worst = try XCTUnwrap(subject.max())
        let slowestRamp = try XCTUnwrap(ramp.max())
        let quickestRamp = try XCTUnwrap(ramp.min())
        let ms = { (seconds: Double) in String(format: "%.0f ms", seconds * 1000) }

        // The subject before the absence: a band that never lights settles
        // instantly and would score perfectly on every assertion below.
        XCTAssertTrue(try XCTUnwrap(lit.min()) > dark + 3, """
            precondition, dark: the declared page's band ends the trace at \(lit) against \
            \(dark) for a page that declares nothing, so the band under measurement is not lit \
            at all and «it settled at once» is being scored on a band that never came on
            """)
        // And the control before the subject: a sampler that cannot see a fade
        // reports every band as instant, which is what this file must not
        // mistake for the fix.
        XCTAssertGreaterThan(quickestRamp, Self.rampFloor, """
            the ramp control — the same modifier lit by a change, at \
            `HelmMotion.hover`'s shipping 0,19 s — settled in \(ramp.map(ms)), under the \
            \(ms(Self.rampFloor)) floor. This harness cannot see the fade it is here to \
            measure, so the subject's reading below is not evidence of anything: trace \
            \(ramps.first ?? "none")
            """)

        XCTAssertLessThan(worst, Self.ceiling, """
            the band of a page that declares that nothing scrolls under it takes \
            \(subject.map(ms)) from the window being built to reach its lit value, against a \
            ceiling of \(ms(Self.ceiling)) and \(ramp.map(ms)) for a band that is genuinely \
            animated. The declaration arrives as a preference one frame after the page mounts, \
            so `lit` goes false → true and an animation keyed on `lit` reads that first \
            delivery as a change: the band fades in on every page open instead of being there. \
            CLAUDE.md says it for a measured height — do not animate the first measurement — \
            and this is the same defect with a `Bool`. Traces: \(traces)
            """)
        XCTAssertLessThan(worst * 3, quickestRamp, """
            the declared band settles in \(subject.map(ms)) and the animated one in \
            \(ramp.map(ms)) — the two are the same order, so what the declaration gets is the \
            fade and not the value. The slowest ramp was \(ms(slowestRamp))
            """)
    }
}
