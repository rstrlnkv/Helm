import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_UI

/// **While the strip over the SSH text box grows in, nothing inside either of
/// them re-lays itself — only the edge between them moves.**
///
/// The strip is revealed by a measured height under a clip, and its content is
/// measured before it is drawn: empty it is 13 pt, and on the first typed
/// letter it grows to 37 pt with Revert and Apply on it, in the same pass that
/// opens it. What a person sees during that growth is the question here, not
/// whether it grows (`TheSSHHeaderRevealsAndTheBannerAlignsTests` holds that):
///
/// - the part of the strip already uncovered is, pixel for pixel, the top of
///   the strip as it finally rests — its content slides out from under the
///   edge rather than being laid out again at each height;
/// - the text view keeps focus and its selection, and the caret's line keeps
///   its distance from the box's top at every sample: the box travels, the
///   text in it does not move inside it;
/// - typing and deleting faster than the curve, so the strip is told to open
///   and close several times before it has finished either, still rests where
///   the last keystroke says, with the caret where it was.
///
/// Each check first requires that the box *travelled* — several positions
/// strictly between rest and open — because a strip put in by `if` moves in
/// one frame and would satisfy every stillness check vacuously.
@MainActor
final class TheSSHStripRevealLeavesTheCaretAndItsTextStillTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    private func bench(_ appearance: NSAppearance.Name) async throws -> SSHStripBench {
        let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-strip-still"))
        benches.append(bench)
        return bench
    }

    /// Fraction of bytes differing by more than a rounding step between two
    /// captures, over the first `bytes` of each.
    private func differing(_ a: Data, _ b: Data, bytes: Int) -> Double {
        let n = min(a.count, b.count, bytes)
        guard n > 0 else { return 1 }
        var differ = 0
        a.withUnsafeBytes { pa in b.withUnsafeBytes { pb in
            for i in 0..<n where abs(Int(pa[i]) - Int(pb[i])) > 24 { differ += 1 }
        } }
        return Double(differ) / Double(n)
    }

    func testTheUncoveredStripIsAlwaysTheTopOfTheRestingOne() async throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on: the reveal is a cut, with nothing between")
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await bench(appearance)
            let margin = HostsSettingsPage.textBoxMargin
            let rest = try XCTUnwrap(bench.boxTop, "\(what): no text box")
            XCTAssertEqual(rest, margin, accuracy: 0.5, "\(what): precondition — the strip was open at rest")

            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)
            tv.insertText("X", replacementRange: NSRange(location: 0, length: 0))
            // The visible strip, from the page's top to just above the box's
            // margin, captured at every sample of the ramp.
            let frames = bench.sample(seconds: 0.6, step: 0.01) { () -> (top: CGFloat, strip: Data?) in
                let top = bench.boxTop ?? -1
                let rows = Int(top - margin) - 2
                return (top, rows > 2 ? bench.mounted.pixels(0...rows) : nil)
            }
            bench.mounted.settle(20)
            let open = try XCTUnwrap(bench.boxTop)
            XCTAssertGreaterThan(open, rest + 20, "\(what): precondition — the strip never opened")
            let travelling = frames.filter { $0.value.top > rest + 1 && $0.value.top < open - 1 && $0.value.strip != nil }
            XCTAssertGreaterThanOrEqual(travelling.count, 3,
                                        "\(what): the box reached \(open) through \(travelling.count) positions — a jump, and nothing here can be still or not")
            let resting = try XCTUnwrap(bench.mounted.pixels(0...Int(open)))
            let rowBytes = resting.count / Int(open)
            for frame in travelling {
                let rows = Int(frame.value.top - margin) - 2
                let share = differing(try XCTUnwrap(frame.value.strip), resting, bytes: rows * rowBytes)
                XCTAssertLessThan(share, 0.001,
                                  "\(what) at \(frame.ms) ms, box at \(frame.value.top): \(String(format: "%.2f", share * 100)) % of the uncovered strip is not what the resting strip draws there — its content was laid out again mid-reveal")
            }
            bench.drop()
        }
    }

    func testTheCaretRidesWithTheBoxAndKeepsFocus() async throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on: the reveal is a cut, with nothing between")
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await bench(appearance)
            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)
            // The caret on the second line, mid-word: past the letter typed.
            tv.setSelectedRange(NSRange(location: 14, length: 0))
            let rest = try XCTUnwrap(bench.boxTop)
            tv.insertText("X", replacementRange: tv.selectedRange())
            let typedAt = tv.selectedRange()
            let readings = bench.sample(seconds: 0.6, step: 0.005) { () -> (top: CGFloat, caret: CGFloat, focused: Bool, selection: NSRange, view: NSTextView?) in
                (bench.boxTop ?? -1, bench.caretTop ?? -1, bench.mounted.window?.firstResponder === tv,
                 tv.selectedRange(), bench.textView)
            }
            let open = try XCTUnwrap(bench.boxTop)
            XCTAssertGreaterThan(open, rest + 20, "\(what): precondition — the strip never opened")
            XCTAssertGreaterThanOrEqual(SSHStripBench.between(readings.map(\.value.top), rest, open).count, 3,
                                        "\(what): precondition — the box jumped from \(rest) to \(open)")
            let offsets = readings.map { $0.value.caret - $0.value.top }
            let spread = (offsets.max() ?? 0) - (offsets.min() ?? 0)
            XCTAssertLessThanOrEqual(spread, 1.0,
                                     "\(what): the caret's line moved \(spread) pt inside the box while the box travelled — the text re-laid itself")
            for reading in readings {
                XCTAssertTrue(reading.value.focused, "\(what) at \(reading.ms) ms: the text view lost focus mid-reveal")
                XCTAssertEqual(reading.value.selection, typedAt, "\(what) at \(reading.ms) ms: the selection moved")
                XCTAssertTrue(reading.value.view === tv, "\(what) at \(reading.ms) ms: the text view was rebuilt")
            }
            bench.drop()
        }
    }

    /// **The first frame that moves moves a little.** The strip's height is
    /// measured twice on the way in — 13 pt empty, then 37 pt once Revert and
    /// Apply are on it — and the second measurement carries its own
    /// transaction, so a flag flipped *without* one still ramps from 13 to 37
    /// and passes a count of in-between positions: the box steps 13 pt in one
    /// frame and then glides. The first position off rest has to be near rest,
    /// and the first position off open near open, on the way back.
    func testTheBoxLeavesEachEndWithoutAStep() async throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on: the reveal is a cut, with nothing between")
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await bench(appearance)
            let rest = try XCTUnwrap(bench.boxTop)
            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)
            tv.insertText("X", replacementRange: NSRange(location: 0, length: 0))
            let down = bench.sample(seconds: 0.6, step: 0.003) { bench.boxTop ?? -1 }
            let open = try XCTUnwrap(down.last?.value)
            XCTAssertGreaterThan(open, rest + 20, "\(what): precondition — the strip never opened")
            let leftRest = try XCTUnwrap(down.first { $0.value > rest + 0.1 }, "\(what): the box never left rest")
            XCTAssertLessThan(leftRest.value - rest, 6,
                              "\(what): the first frame off rest put the box at \(leftRest.value) (\(leftRest.ms) ms), \(leftRest.value - rest) pt down in one step")

            bench.hvm.revertSSH()
            let up = bench.sample(seconds: 0.6, step: 0.003) { bench.boxTop ?? -1 }
            let leftOpen = try XCTUnwrap(up.first { $0.value < open - 0.1 }, "\(what): the box never left open")
            XCTAssertLessThan(open - leftOpen.value, 6,
                              "\(what): the first frame off open put the box at \(leftOpen.value) (\(leftOpen.ms) ms), \(open - leftOpen.value) pt up in one step")
            bench.drop()
        }
    }

    /// Seven keystrokes, alternately adding and deleting one letter, every
    /// ~40 ms — faster than the 300 ms curve, so each lands on a strip still
    /// travelling. An odd count ends with an edit on screen, an even one
    /// without; the strip must rest on whichever the last keystroke left.
    func testKeystrokesFasterThanTheCurveRestWhereTheLastOneSays() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            for strokes in [7, 8] {
                let bench = try await bench(appearance)
                let rest = try XCTUnwrap(bench.boxTop)
                let tv = try XCTUnwrap(bench.textView)
                bench.mounted.window?.makeFirstResponder(tv)
                var done = 0
                let tops = bench.sample(seconds: 0.8, step: 0.005, act: { index in
                    guard index % 8 == 0, done < strokes else { return }
                    done += 1
                    if bench.hvm.sshHasUnsavedChanges {
                        tv.setSelectedRange(NSRange(location: 1, length: 0))
                        tv.deleteBackward(nil)
                    } else {
                        tv.setSelectedRange(NSRange(location: 0, length: 0))
                        tv.insertText("X", replacementRange: tv.selectedRange())
                    }
                }) { bench.boxTop ?? -1 }
                bench.mounted.settle(40)
                XCTAssertEqual(done, strokes, "\(what): precondition — \(done) of \(strokes) keystrokes landed")
                XCTAssertEqual(bench.hvm.sshHasUnsavedChanges, strokes % 2 == 1,
                               "\(what), \(strokes) strokes: precondition — the model disagrees with the count")
                XCTAssertGreaterThanOrEqual(SSHStripBench.between(tops.map(\.value), rest, rest + 37).count, 3,
                                            "\(what), \(strokes) strokes: precondition — the strip never travelled")
                let settled = try XCTUnwrap(bench.boxTop)
                if strokes % 2 == 1 {
                    XCTAssertGreaterThan(settled, rest + 20,
                                         "\(what), \(strokes) strokes: an edit is on screen and the strip rests closed at \(settled)")
                } else {
                    XCTAssertEqual(settled, rest, accuracy: 0.5,
                                   "\(what), \(strokes) strokes: nothing to say and the strip rests at \(settled)")
                }
                XCTAssertTrue(bench.mounted.window?.firstResponder === tv, "\(what), \(strokes) strokes: focus lost")
                XCTAssertTrue(bench.textView === tv, "\(what), \(strokes) strokes: the text view was rebuilt")
                bench.drop()
            }
        }
    }
}
