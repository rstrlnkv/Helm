import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **While the ring runs, the mode cells and the timer take no press, and ✕ does; once the countdown is over they answer
/// again.** The real panel is ordered in for a moment and pressed with real mouse events through `sendEvent`, the way the
/// window server's would arrive, at the places the cells really stand (found by what answers a hit-test, not by a
/// number): a cell that is merely drawn dim and still answers is the defect, and a harness whose clicks reach nothing
/// is ruled out by the same presses on the same cells after the countdown. The gear is the timer's neighbour in the one
/// dimmed group and is not pressed here: its press opens a menu, which would block a run.
@MainActor
final class TheDimmedCellsAreDeadWhileTheRingRunsTests: XCTestCase {
    private var capture: CapturePanel?
    override func tearDown() { capture?.close(); capture = nil; super.tearDown() }

    private struct Standing {
        let bar: CapturePanel
        let panel: BarPanel
        /// The middle of ✕, Screen, Window, Area, the timer and the gear, in the host's points.
        let centres: [CGFloat]
        let chosen: () -> [PanelMode]
        let cancels: () -> Int
    }

    private func isHandle(_ view: NSView?) -> Bool {
        var walk = view
        while let current = walk {
            if current is WindowDragHandle.DragView { return true }
            walk = current.superview
        }
        return false
    }

    /// The middle of every place no drag starts on, left to right: ✕, Screen, Window, Area, the timer and the gear.
    private func centres(of panel: BarPanel) throws -> [CGFloat] {
        let host = try XCTUnwrap(panel.contentView)
        let row = stride(from: CGFloat(0.5), to: host.bounds.width, by: 1).map { isHandle(host.hitTest(NSPoint(x: $0, y: host.bounds.midY))) }
        var runs: [Range<Int>] = []
        var start: Int?
        for index in 12..<(row.count - 12) {
            if !row[index], start == nil { start = index }
            if row[index], let from = start { runs.append(from..<index); start = nil }
        }
        if let from = start { runs.append(from..<(row.count - 12)) }
        XCTAssertEqual(runs.count, 6, "✕, Screen, Window, Area, the timer and the gear are six places no drag starts on: \(runs)")
        return runs.map { CGFloat($0.lowerBound + $0.upperBound) / 2 }
    }

    private func standing(timer: CaptureTimer = .none) throws -> Standing {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        // Area with nothing drawn: Capture is not on the panel, so the cells are the only six places to press.
        store.set(PanelMode.area.rawValue, for: ScreenshotsSettings.Key.panelMode)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let bar = CapturePanel(store: store)
        capture = bar
        var chosen: [PanelMode] = [], cancels = 0
        bar.model.modeChosen = { chosen.append($0) }
        bar.model.cancel = { cancels += 1 }
        bar.show()
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible })
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let places = try centres(of: panel)
        return Standing(bar: bar, panel: panel, centres: places,
                        chosen: { chosen }, cancels: { cancels })
    }

    private func click(_ panel: BarPanel, x: CGFloat) throws {
        let host = try XCTUnwrap(panel.contentView)
        let point = host.convert(NSPoint(x: x, y: host.bounds.midY), to: nil)
        for (type, number) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: panel.windowNumber, context: nil, eventNumber: number,
                                                         clickCount: 1, pressure: 1))
            panel.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private func count(_ s: Standing) {
        s.bar.model.countdown = 3
        s.bar.model.countdownLength = 5
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    func testTheModeCellsAndTheTimerTakeNoPressWhileTheRingRuns() throws {
        let s = try standing()
        count(s)
        try click(s.panel, x: s.centres[2])
        try click(s.panel, x: s.centres[3])
        try click(s.panel, x: s.centres[4])
        XCTAssertEqual(s.chosen(), [], "a mode cell answered a press while the ring ran")
        XCTAssertEqual(s.bar.model.mode, .area, "the mode changed under a running countdown")
        XCTAssertFalse(s.bar.model.timerOn, "the timer cell switched the timer on under a running countdown")
    }

    func testTheTimerTakesNoPressWhileTheRingRunsEvenWhenItIsOn() throws {
        let s = try standing(timer: .ten)
        XCTAssertTrue(s.bar.model.timerOn)
        count(s)
        try click(s.panel, x: s.centres[4])
        XCTAssertEqual(s.bar.model.settings.timer, .ten)
        XCTAssertEqual(s.cancels(), 0)
    }

    func testTheSamePressesAnswerOnceTheCountdownIsOver() throws {
        let s = try standing()
        count(s)
        try click(s.panel, x: s.centres[2])
        XCTAssertEqual(s.chosen(), [])
        s.bar.model.countdown = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        try click(s.panel, x: s.centres[2])
        XCTAssertEqual(s.chosen(), [.window], "the harness' press reaches nothing, or the cell stayed dead after the countdown")
        XCTAssertEqual(s.bar.model.mode, .window)
        try click(s.panel, x: s.centres[4])
        XCTAssertTrue(s.bar.model.timerOn, "the timer cell stayed dead after the countdown")
        try click(s.panel, x: s.centres[0])
        XCTAssertEqual(s.cancels(), 1)
    }

    func testTheCloseControlAnswersWhileTheRingRunsAndOnlyItDoes() throws {
        let s = try standing()
        count(s)
        try click(s.panel, x: s.centres[0])
        XCTAssertEqual(s.cancels(), 1, "✕ did not answer while the ring ran")
        XCTAssertEqual(s.chosen(), [])
    }

    /// After ✕ in a real countdown the machine is free and the panel that opens next has live cells.
    func testAPanelOpenedAfterACancelledCountdownHasLiveCells() async throws {
        let gate = PromptGate()
        let box = try PanelRig.rig(timer: .five, presentBar: { $0.show() }, tick: { _ in await gate.arrive() })
        defer { box.controller.teardown() }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.screen)
        box.controller.capture(from: .screen)
        await gate.reached()
        XCTAssertEqual(box.controller.bar.model.countdown, 5)
        box.controller.bar.model.cancel()
        await gate.open()
        await grace(0.2)
        XCTAssertFalse(box.controller.isBusy)
        XCTAssertNil(box.controller.bar.model.countdown)
        box.controller.bar.model.choose(.area)
        box.controller.begin(.panel)
        await grace(0.5)
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible })
        let places = try centres(of: panel)
        try click(panel, x: places[2])
        await grace(0.3)
        XCTAssertEqual(box.controller.bar.model.mode, .window, "Window did not answer on the panel opened after a cancelled countdown")
    }

    /// **A weaker instrument, said so.** A real press cannot tell `.disabled` from the dimming: the 35 % opacity alone
    /// already takes a cell out of the hosting view's hit-testing (measured: with `.disabled` taken out, the presses above
    /// still reach nothing). What `.disabled` adds is for the ways in that are not a pointer — VoiceOver's press and the
    /// keyboard on a focused cell — which an offscreen hosting view publishes no tree for. So the declaration is read:
    /// the modifier that dims the groups must also disable them.
    func testTheModifierThatDimsTheGroupsAlsoDisablesThem() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/CapturePanelView.swift")
        let start = try XCTUnwrap(source.range(of: "private struct Dimmed: ViewModifier"), "the dimming modifier is gone or renamed")
        let body = source[start.lowerBound...].prefix(400)
        XCTAssertTrue(body.contains(".opacity(counting ? CapturePanelView.dimmed : 1)"), "the scan does not see the dimming: \(body)")
        XCTAssertTrue(body.contains(".disabled(counting)"), "the groups are dimmed and still enabled to VoiceOver and the keyboard")
        XCTAssertEqual(source.components(separatedBy: ".modifier(Dimmed(counting: model.counting))").count - 1, 2,
                       "the modes and the timer-and-gear groups are the two dimmed; ✕ and Capture are not")
    }
}
