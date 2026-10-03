import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A press on the panel's empty glass moves the panel; a press on a cell is a press and never the start of a drag.**
/// What `hitTest` answers along the panel's middle line, one point at a time: the cells are runs that no drag handle
/// answers, the glass between them and around them is the handle (`WindowDragHandle.DragView`, which hands the press to
/// `performDrag`), the room Capture takes is the handle while there is nothing to take and a button once there is, and
/// the window is not movable by its background (that would make every cell a handle). The panel is laid out and never
/// ordered in.
@MainActor
final class ThePanelIsDraggedOnlyByItsGlassTests: XCTestCase {

    private struct Panel {
        let capture: CapturePanel
        let panel: BarPanel
        let host: NSView
    }

    private func panel(_ values: [String: Any] = [:]) throws -> Panel {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        for (key, value) in values { store.set(value, for: key) }
        let capture = CapturePanel(store: store)
        let panel = capture.makePanel()
        let host = try XCTUnwrap(panel.contentView)
        settle(panel)
        return Panel(capture: capture, panel: panel, host: host)
    }

    /// A turn of the run loop for SwiftUI to take the model's change, then the size and the layout it asks for.
    private func settle(_ panel: BarPanel) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        if let host = panel.contentView { panel.setContentSize(host.fittingSize); host.layoutSubtreeIfNeeded() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func isHandle(_ view: NSView?) -> Bool {
        var walk = view
        while let current = walk {
            if current is WindowDragHandle.DragView { return true }
            walk = current.superview
        }
        return false
    }

    /// For every point of the middle line, one point apart, whether the press there would reach the drag handle.
    private func line(_ p: Panel, y: CGFloat? = nil) -> [Bool] {
        let row = y ?? p.host.bounds.midY
        return stride(from: CGFloat(0.5), to: p.host.bounds.width, by: 1).map { isHandle(p.host.hitTest(NSPoint(x: $0, y: row))) }
    }

    /// Runs of points that are not the handle, between the corners' 12 points.
    private func cells(_ line: [Bool]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for index in 12..<(line.count - 12) {
            if !line[index], start == nil { start = index }
            if line[index], let from = start { runs.append(from..<index); start = nil }
        }
        if let from = start { runs.append(from..<(line.count - 12)) }
        return runs
    }

    func testTheCellsAreSixRunsAndTheGlassBetweenAndAroundThemIsTheHandle() throws {
        let p = try panel()
        let row = line(p)
        let runs = cells(row)
        XCTAssertEqual(runs.count, 6, "✕, Screen, Window, Area, the timer and the gear are six places no drag starts on: \(runs)")
        for (first, second) in zip(runs, runs.dropFirst()) {
            XCTAssertTrue(row[first.upperBound..<second.lowerBound].allSatisfy { $0 }, "the glass between two cells is not the handle")
        }
        XCTAssertTrue(row[(runs.last?.upperBound ?? 0)...].dropLast(12).allSatisfy { $0 }, "the room Capture will take is dead glass while there is nothing to take, and a press there does not move the panel")
        let top = line(p, y: 2), bottom = line(p, y: p.host.bounds.height - 2)
        XCTAssertTrue(top[16..<(top.count - 16)].allSatisfy { $0 }, "the glass above the cells does not move the panel")
        XCTAssertTrue(bottom[16..<(bottom.count - 16)].allSatisfy { $0 }, "the glass below the cells does not move the panel")
    }

    func testTheWindowIsNotMovableByItsBackgroundOrEveryCellWouldBeAHandle() throws {
        let p = try panel()
        XCTAssertFalse(p.panel.isMovableByWindowBackground)
        let handle = WindowDragHandle.DragView()
        XCTAssertTrue(handle.mouseDownCanMoveWindow)
        XCTAssertTrue(handle.acceptsFirstMouse(for: nil), "the first press on the glass is spent on making the panel key")
    }

    func testCaptureIsAButtonOnlyWhereItIsOfferedAndTheRoomIsTheHandleOtherwise() throws {
        let p = try panel()
        let idle = line(p)
        let room = idle.count - 24
        XCTAssertTrue(idle[room], "the room for Capture is no handle while there is no target")
        p.capture.model.hasTarget = true
        settle(p.panel)
        let offered = line(p)
        XCTAssertFalse(offered[room], "a button that is offered lies on glass that drags the panel")
        XCTAssertEqual(cells(offered).count, 7, "Capture is not a cell of its own once there is a target: \(cells(offered))")
    }

    /// While the ring runs the other cells are dimmed and off, and ✕ stands outside what is dimmed, the one way out with
    /// the pointer: a press on it must reach it, and not the handle behind it (which would start dragging the panel instead).
    func testTheCloseControlIsStillACellWhileTheRingRuns() throws {
        let p = try panel()
        let idle = cells(line(p))
        p.capture.model.countdown = 3
        p.capture.model.countdownLength = 5
        settle(p.panel)
        let counting = line(p)
        let close = try XCTUnwrap(idle.first)
        XCTAssertTrue(counting[close].allSatisfy { !$0 }, "a press on ✕ while the ring runs reaches the drag handle, not ✕: \(cells(counting)) against \(idle)")
    }

    func testThePanelIsAsWideCountingAsIdleAndWithATargetAsWithout() throws {
        let p = try panel()
        let idle = p.host.fittingSize
        p.capture.model.hasTarget = true
        settle(p.panel)
        XCTAssertEqual(p.host.fittingSize.width, idle.width, accuracy: 0.5, "the panel grew a button under the pointer")
        p.capture.model.countdown = 4
        p.capture.model.countdownLength = 30
        settle(p.panel)
        XCTAssertEqual(p.host.fittingSize.width, idle.width, accuracy: 0.5, "the ring changed the width")
        XCTAssertEqual(p.host.fittingSize.height, idle.height, accuracy: 0.5)
    }

    func testNothingOutsideThePanelAnswersAndNothingInsideItAnswersNothing() throws {
        let p = try panel()
        let size = p.host.bounds.size
        for point in [NSPoint(x: -1, y: size.height / 2), NSPoint(x: size.width + 1, y: size.height / 2),
                      NSPoint(x: size.width / 2, y: -1), NSPoint(x: size.width / 2, y: size.height + 1),
                      NSPoint(x: CGFloat.nan, y: 3), NSPoint(x: 1e300, y: 1e300)] {
            XCTAssertNil(p.host.hitTest(point), "a press outside the panel was taken: \(point)")
        }
        XCTAssertNotNil(p.host.hitTest(NSPoint(x: size.width / 2, y: 2)))
    }
}
