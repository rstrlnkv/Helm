import AppKit
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The panel's glass ends at the gear while there is nothing to capture, and is wider by Capture when there is.**
/// Nothing to capture is Area mode with nothing drawn and Window mode with the pointer over no window: there the glass
/// has no empty stretch where Capture would stand. A target (an area, a window under the pointer) or Screen mode, and
/// Capture is drawn after a divider and the glass is wider by exactly that. This replaces "one width in every state":
/// what must still hold is that the width answers to `showsCapture` alone, not to the timer or the seconds counted.
///
/// The gear is found as the rendered tree names it (its accessibility label, in the language under test) and read in the
/// hosting view's own points; the glass is the hosting view's natural width, as the real panel asks for it. The check
/// does not say which edge of the panel stays put between the two widths: that is the controller's choice.
@MainActor
final class ThePanelEndsAtTheGearUntilThereIsATargetTests: XCTestCase {
    override func tearDown() { AppLanguage.override = nil; super.tearDown() }

    /// `gearLeft` is where the sixth place begins; `gearRun` is its length when something drags after it (a closed run),
    /// nil when it is the last thing and its run is open to the corner cut.
    private struct Measured { let width: CGFloat; let height: CGFloat; let gearLeft: CGFloat?; let gearRun: CGFloat?; let nextLeft: CGFloat? }

    /// The natural width, and where the sixth place no drag starts on (✕, Screen, Window, Area, the timer, the gear) ends
    /// along the panel's middle line: what `hitTest` answers a point at a time, the way the drag-handle tests read the cells.
    private func measure(_ model: CapturePanelModel) -> Measured {
        let host = NSHostingView(rootView: CapturePanelView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let size = host.fittingSize
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        func isHandle(_ view: NSView?) -> Bool {
            var walk = view
            while let current = walk {
                if current is WindowDragHandle.DragView { return true }
                walk = current.superview
            }
            return false
        }
        let row = stride(from: CGFloat(0.5), to: size.width, by: 1).map { isHandle(host.hitTest(NSPoint(x: $0, y: host.bounds.midY))) }
        var runs: [Range<Int>] = []
        var start: Int?
        for index in 12..<(row.count - 12) {
            if !row[index], start == nil { start = index }
            if row[index], let from = start { runs.append(from..<index); start = nil }
        }
        // The last run is open when the gear is the last thing: it is cut at the corner (width - 12), which says nothing of
        // where the gear ends. Its right edge is then its left edge and the cell's width, never read from the panel's width.
        var openLast = false
        if let from = start { runs.append(from..<(row.count - 12)); openLast = true }
        guard runs.count >= 6 else { return Measured(width: size.width, height: size.height, gearLeft: nil, gearRun: nil, nextLeft: nil) }
        let gear = runs[5]
        return Measured(width: size.width, height: size.height, gearLeft: CGFloat(gear.lowerBound),
                        gearRun: openLast && runs.count == 6 ? nil : CGFloat(gear.count),
                        nextLeft: runs.count > 6 ? CGFloat(runs[6].lowerBound) : nil)
    }

    private func state(mode: PanelMode, timer: CaptureTimer = .none, target: Bool, counting: Int? = nil) -> CapturePanelModel {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        model.choose(mode)
        model.choose(timer)
        model.hasTarget = target
        model.countdown = counting
        model.countdownLength = counting.map { $0 > 5 ? 30 : 5 } ?? 0
        return model
    }

    func testTheGlassEndsAtTheGearWithNoTargetAndIsWiderByCaptureWithOne() {
        var compared = 0
        AppLanguage.each { language in
            for mode in [PanelMode.window, .area] {
                for timer in [CaptureTimer.none, .five, .ten, .thirty] {
                    let none = measure(state(mode: mode, timer: timer, target: false))
                    let some = measure(state(mode: mode, timer: timer, target: true))
                    compared += 1
                    guard let gearLeft = none.gearLeft, let gearLeftWith = some.gearLeft, let run = some.gearRun else {
                        XCTFail("\(language): \(mode) \(timer): the gear was not found in the rendered panel (none \(String(describing: none.gearLeft)), target \(String(describing: some.gearLeft)) run \(String(describing: some.gearRun)))")
                        continue
                    }
                    // Where the gear ends is read, where a closed run proves the cell is as wide as its constant; then the
                    // same constant is applied where nothing follows the gear.
                    XCTAssertEqual(run, CapturePanelView.cellWidth, accuracy: 1.5, "\(language): the gear's run is \(run) wide, not the cell's \(CapturePanelView.cellWidth)")
                    let gearRight = gearLeft + CapturePanelView.cellWidth
                    let gearRightWith = gearLeftWith + run
                    XCTAssertEqual(none.width, gearRight + HelmSpace.s4, accuracy: 1.5,
                                   "\(language): \(mode) \(timer): no target, the glass is \(none.width) wide and the gear ends at \(gearRight): empty glass past the gear")
                    XCTAssertGreaterThan(some.width - (gearRightWith + HelmSpace.s4), 40,
                                         "\(language): \(mode) \(timer): with a target, the glass is \(some.width) wide, the gear ends at \(gearRightWith): no room for Capture")
                    XCTAssertGreaterThan(some.width - none.width, 40, "\(language): \(mode) \(timer): with a target the panel is \(some.width), without \(none.width): not wider by Capture")
                    // The gap from the gear to Capture is the divider (1 + 5 + 5) between two `HelmSpace.s2`s, and no third: the
                    // row's own spacing would add one on top of `trailing`'s padding.
                    if let next = some.nextLeft {
                        XCTAssertEqual(next - gearRightWith, 2 * HelmSpace.s2 + 11, accuracy: 1.5,
                                       "\(language): \(mode) \(timer): the gear and Capture are \(next - gearRightWith) apart, not two gaps and a divider")
                    } else {
                        XCTFail("\(language): \(mode) \(timer): Capture was not found after the gear")
                    }
                    XCTAssertEqual(none.height, CapturePanelView.height, accuracy: 0.5)
                    XCTAssertEqual(some.height, CapturePanelView.height, accuracy: 0.5)
                }
            }
            // Screen mode always has Capture: it is as wide as any other mode with a target, with or without `hasTarget`.
            let withTarget = measure(state(mode: .window, target: true)).width
            for target in [false, true] {
                XCTAssertEqual(measure(state(mode: .screen, target: target)).width, withTarget, accuracy: 0.01, "\(language): Screen, target \(target)")
            }
        }
        XCTAssertEqual(compared, AppLanguage.allCases.count * 2 * 4, "the loop compared \(compared) states: the check watched less than it says")
    }

    /// Whatever the timer or the seconds counted, the width is the one `showsCapture` gives: with Capture, a countdown's
    /// ring takes its place at the same width; without, it never stands there.
    func testTheTimerAndTheCountdownDoNotMoveTheEdge() {
        AppLanguage.each { language in
            for target in [false, true] {
                let base = measure(state(mode: .area, target: target)).width
                for timer in [CaptureTimer.five, .ten, .thirty] {
                    XCTAssertEqual(measure(state(mode: .area, timer: timer, target: target)).width, base, accuracy: 0.01,
                                   "\(language): the timer at \(timer.seconds) moved the panel's edge, target \(target)")
                }
            }
            let with = measure(state(mode: .screen, target: false)).width
            for counting in [5, 2, 30, 1] {
                XCTAssertEqual(measure(state(mode: .screen, target: false, counting: counting)).width, with, accuracy: 0.01,
                               "\(language): counting \(counting) moved the panel's edge")
            }
        }
    }
}
