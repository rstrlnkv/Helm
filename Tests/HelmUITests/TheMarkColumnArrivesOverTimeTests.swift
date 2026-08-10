import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// Switching a rule on moves every label in the card 26 pt sideways and puts a
/// green tick where there was nothing. Both landed in one frame.
///
/// The cause was law 1 rather than a missing curve: `markView` was a `switch`
/// over four cases, and SwiftUI interpolates between two states of *one* view
/// and never between two views — so `.space` → `.holding` was an insert and a
/// remove whatever transaction surrounded it. Four cases are properties of one
/// `Image` now.
///
/// Measured in pixels, for the reason `HeroMotionProbe` gives at length: every
/// layout API answers with where an animation is *heading*, so a probe built on
/// `fittingSize` reads a clean step where the screen shows a ramp.
@MainActor
final class TheMarkColumnArrivesOverTimeTests: XCTestCase {

    private final class Box: ObservableObject {
        @Published var mark: HelmRowMark = .none
        @Published var note = "While a display is connected"
        /// The control's own value, changed with no transaction near it.
        @Published var flipped = false
    }

    private struct Harness: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(spacing: 0) {
                HelmSettingRow("External display", note: box.note,
                               mark: box.mark) { Toggle("", isOn: .constant(false)).labelsHidden() }
                Spacer(minLength: 0)
            }
            .frame(width: 420)
        }
    }

    /// A row whose mark never changes, in the same window, read by the same
    /// sampler. Without it every ramp below passes on a machine that animates
    /// by default.
    private struct Control: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Opaque, and inset by a width that changes: the sampler looks
                // for the first inked column, so a *clear* rectangle is a
                // control that draws nothing and skips itself — which is how
                // this file first ran with its only control switched off.
                // 25 pt, because the band above is in **pixels** and this
                // renders at 2x: the note sits at points 24–36, which is
                // pixels 48–72. A control drawn at point 50 lands at pixel 100
                // and is outside the window the sampler looks through — which
                // skipped itself silently, twice.
                Color.clear.frame(height: 25)
                HStack(spacing: 0) {
                    Color.clear.frame(width: box.flipped ? 60 : 20, height: 20)
                    Color.black.frame(width: 40, height: 20)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 420)
        }
    }

    private func pixels<V: View>(_ host: NSHostingView<V>) -> (NSBitmapImageRep, UnsafeMutablePointer<UInt8>)? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        return (rep, data)
    }

    /// The left edge of the **label column**, read low in the row where the
    /// note is and the mark is not.
    ///
    /// **Anchored on the thing that moves**, and the first version was not:
    /// it took the first ink in the row's *top* band, which is the mark's own
    /// left edge whenever there is a mark — and the mark column is leading, so
    /// that edge sits at x=0 in both states and never travels. It read `[1, 2,
    /// 2, 2 …]` for a 26 pt indent, and would have gone on reading that with
    /// the animation deleted.
    private func firstInkX<V: View>(_ host: NSHostingView<V>) -> Int {
        guard let (rep, data) = pixels(host) else { return -1 }
        for x in 0..<rep.pixelsWide {
            for y in 46..<min(80, rep.pixelsHigh) where data[y * rep.bytesPerRow + x * 4 + 3] > 40 {
                return x
            }
        }
        return -1
    }

    /// Alpha in the mark's own column — the leftmost 30 px of the row's top
    /// band, which is the 14 pt glyph at 2x with a little air round it.
    private func markInk<V: View>(_ host: NSHostingView<V>) -> Int {
        guard let (rep, data) = pixels(host) else { return -1 }
        var mass = 0
        for y in 0..<min(44, rep.pixelsHigh) {
            for x in 0..<min(30, rep.pixelsWide) {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    /// Alpha in the note's band — below the title, across the label column.
    private func noteInk<V: View>(_ host: NSHostingView<V>) -> Int {
        guard let (rep, data) = pixels(host) else { return -1 }
        var mass = 0
        for y in 40..<min(80, rep.pixelsHigh) {
            for x in 0..<min(600, rep.pixelsWide) {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    private func series<V: View>(_ view: V, sample: @escaping (NSHostingView<V>) -> Int,
                                 change: @escaping () -> Void) -> [Int] {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 200)
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

    private func steps(_ s: [Int]) -> Int { Set(s.filter { $0 >= 0 }).count }

    /// The control: a width written with no transaction arrives in one step, so
    /// a ramp below is the transaction and not the machine.
    func testAWidthWrittenWithNoTransactionArrivesInOneStep() throws {
        let box = Box()
        let samples = series(Control(box: box), sample: firstInkX) { box.flipped = true }
        try XCTSkipIf(samples.allSatisfy { $0 < 0 }, "nothing drew — no window server")
        XCTAssertEqual(steps(samples), 1, "the control animated by itself: \(samples)")
    }

    /// The column arriving: `.none` → `.holding`, which is the first rule in a
    /// card being switched on. This one is a layout change and would ramp
    /// whatever the mark is built from — it is here for the indent, not for the
    /// glyph.
    func testTheColumnGrowsRatherThanAppearing() throws {
        let box = Box()
        let samples = series(Harness(box: box), sample: firstInkX) {
            withAnimation(HelmMotion.disclosure) { box.mark = .holding }
        }
        try XCTSkipIf(samples.allSatisfy { $0 < 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 3,
                                    "every label in the card stepped 26 pt sideways in "
                                    + "\(steps(samples)) frame(s): \(samples)")
    }

    /// **What the pressed row plays.** Its column already had the width — the
    /// card was showing marks before, or the column arrived with it — and what
    /// changes is that this row now has something to say: `.space` → `.waiting`,
    /// an invisible glyph becoming a clock.
    ///
    /// One `Image` whose opacity changes, so it ramps. As four branches it was
    /// `Color.clear` being removed and an `Image` inserted, which is a cut
    /// however long the curve.
    func testAMarkArrivingInAColumnThatAlreadyExistsFadesUp() throws {
        let box = Box()
        box.mark = .space
        let samples = series(Harness(box: box), sample: { self.markInk($0) }) {
            withAnimation(HelmMotion.disclosure) { box.mark = .waiting }
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 3,
                                    "the mark appeared in \(steps(samples)) frame(s) on the "
                                    + "row somebody had just pressed: \(samples)")
    }

    /// **The one the identity bug actually showed in.** Clock → tick changes no
    /// width at all, so nothing about the layout can carry it: either the two
    /// marks are one view whose symbol is replaced, or they are two views and
    /// the glyph is swapped in a single frame.
    ///
    /// Read as ink in the mark's own column, which is where the difference is —
    /// the tick is a filled circle and the clock an outline, so a replacement
    /// in progress is a mass between the two.
    ///
    /// **This one guards identity, not the transaction, and the difference was
    /// measured.** Deleting every `withAnimation` in this file fails the column
    /// and the note and leaves this passing: `.symbolEffect(.replace)` plays on
    /// its own. Rebuilding `markView` as two views instead of one fails this
    /// and leaves the other two passing. Two defects, one for each test, and
    /// neither covers the other.
    func testTheGlyphIsReplacedRatherThanSwapped() throws {
        let box = Box()
        box.mark = .waiting
        let samples = series(Harness(box: box), sample: { self.markInk($0) }) {
            withAnimation(HelmMotion.disclosure) { box.mark = .holding }
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 3,
                                    "the tick replaced the clock in \(steps(samples)) "
                                    + "frame(s), which is a cut: \(samples)")
    }

    /// The third thing that used to arrive in one frame: the note. «While an
    /// external display is connected» becomes «Applies right now» under the
    /// same title, and one `Text` whose string changes redraws instantly
    /// however many transactions surround it — a string is not an animatable
    /// property. The `.id` makes the two different views so that a transition
    /// has something to fire on, which is law 1 used deliberately rather than
    /// tripped over.
    ///
    /// Read low in the row, where the note is and the title is not.
    func testTheNoteCrossFadesRatherThanBeingReplaced() throws {
        let box = Box()
        let samples = series(Harness(box: box), sample: { self.noteInk($0) }) {
            withAnimation(HelmMotion.disclosure) { box.note = "Applies right now" }
        }
        try XCTSkipIf(samples.allSatisfy { $0 <= 0 }, "nothing drew — no window server")
        XCTAssertGreaterThanOrEqual(steps(samples), 3,
                                    "the note changed in \(steps(samples)) frame(s): "
                                    + "\(samples)")
    }

    /// A spacer draws nothing.
    ///
    /// `.space` holds the column's width so a card of mixed rows keeps one left
    /// edge, and it must hold it *empty* — the mark reports the world, and a
    /// tick on a row that can never carry one is the row saying something that
    /// is not true. Since all four marks are now one `Image`, the only thing
    /// keeping it invisible is an opacity, which is one character from being
    /// wrong: a mutation to `.opacity(1)` broke nothing else in this file.
    func testASpacerHoldsTheWidthAndDrawsNothing() throws {
        let empty = Box(); empty.mark = .space
        let marked = Box(); marked.mark = .holding
        let blank = still(Harness(box: empty))
        let tick = still(Harness(box: marked))
        try XCTSkipIf(blank < 0 || tick < 0, "nothing drew — no window server")

        XCTAssertEqual(blank, 0, "a row that can never carry a mark drew one: \(blank)")
        XCTAssertGreaterThan(tick, 0, "…and a row that can drew nothing, so the check "
                             + "above is measuring an empty window")
    }

    /// One settled frame's worth of ink in the mark column.
    private func still<V: View>(_ view: V) -> Int {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 200)
        window.layoutIfNeeded()
        for _ in 0..<20 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        let mass = markInk(host)
        window.contentView = nil
        return mass
    }

    /// And the mark itself is one view across the change, so the tick can
    /// replace the clock rather than being inserted in its place. Asserted on
    /// the type, because a `switch` returning four different views is the
    /// defect and it is invisible in any single frame.
    func testTheFourMarksAreOneViewAndNotFour() {
        let ink = HelmSettingRow<EmptyView>("t", mark: .waiting)
        let tick = HelmSettingRow<EmptyView>("t", mark: .holding)
        XCTAssertEqual(String(describing: type(of: ink.body)),
                       String(describing: type(of: tick.body)),
                       "waiting and holding produce different view types, so SwiftUI has "
                       + "nothing to interpolate between them")
    }
}
