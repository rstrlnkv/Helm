import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A real press on ✕, sent to the real panel as a mouse event, cancels — idle, and while the ring runs.** The panel is
/// ordered in for a moment, as the controller does it. The press goes through `sendEvent`, the way the window server's
/// would, so it travels the view's own hit test and the control's own gesture, which a call to `model.cancel()` does
/// not. The control is the same press on an idle panel, so a harness that clicks nothing cannot pass for a ✕ that works.
@MainActor
final class TheCloseControlAnswersWhileTheRingRunsTests: XCTestCase {
    private var capture: CapturePanel?
    override func tearDown() { capture?.close(); capture = nil; super.tearDown() }

    private func standing(counting: Bool, hasTarget: Bool = false) throws -> (BarPanel, () -> Int) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let bar = CapturePanel(store: store)
        capture = bar
        var cancels = 0
        bar.model.cancel = { cancels += 1 }
        bar.show()
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible })
        if counting { bar.model.countdown = 3; bar.model.countdownLength = 5 }
        bar.model.hasTarget = hasTarget
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        return (panel, { cancels })
    }

    /// A press and release at a point of the panel's content, in the host's own top-left points.
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
    }

    func testAPressOnTheCloseControlOfAnIdlePanelCancels() throws {
        let (panel, cancels) = try standing(counting: false)
        try click(panel, x: 24)
        XCTAssertEqual(cancels(), 1, "the harness' click does not reach a control that works")
    }

    func testAPressOnTheCloseControlWhileTheRingRunsCancels() throws {
        let (panel, cancels) = try standing(counting: true)
        try click(panel, x: 24)
        XCTAssertEqual(cancels(), 1, "✕ did not answer while the countdown ran")
    }
}
