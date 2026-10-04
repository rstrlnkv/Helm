import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The window follows the content's width when Capture comes or goes, and keeps its leading edge where it was.**
/// The panel is laid out and never ordered in, so there is no `show()`: the window is the one `makePanel` returns, and
/// nothing here sizes it by hand after the first settle — the width it ends at is the host's own call to the panel.
@MainActor
final class ThePanelFollowsItsContentsWidthByItsLeadingEdgeTests: XCTestCase {
    private func standing() throws -> (CapturePanel, BarPanel) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(PanelMode.area.rawValue, for: ScreenshotsSettings.Key.panelMode)
        let capture = CapturePanel(store: store)
        let panel = capture.makePanel()
        let host = try XCTUnwrap(panel.contentView)
        panel.setContentSize(host.fittingSize)
        panel.setFrameOrigin(NSPoint(x: 300, y: 200))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (capture, panel)
    }

    func testTheWindowGrowsToTheRightWithATargetAndShrinksBackWithout() throws {
        let (capture, panel) = try standing()
        let narrow = panel.frame
        capture.model.hasTarget = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(panel.frame.width, narrow.width + 40, "the window did not follow the content to its new width")
        XCTAssertEqual(panel.frame.minX, narrow.minX, accuracy: 0.01, "the leading edge moved")
        XCTAssertEqual(panel.frame.minY, narrow.minY, accuracy: 0.01)
        XCTAssertEqual(panel.contentView?.fittingSize.width ?? 0, panel.contentLayoutRect.width, accuracy: 0.5)
        capture.model.hasTarget = false
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(panel.frame.width, narrow.width, accuracy: 0.5, "the window kept the room after the target went")
        XCTAssertEqual(panel.frame.minX, narrow.minX, accuracy: 0.01)
    }

    // The tests below order the real panel in for a moment, as the controller does, to have a screen to be held inside.

    private var shown: CapturePanel?
    override func tearDown() { shown?.close(); shown = nil; super.tearDown() }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }

    private func open(_ store: NamespacedStore) throws -> (CapturePanel, BarPanel) {
        store.set(PanelMode.area.rawValue, for: ScreenshotsSettings.Key.panelMode)
        let bar = CapturePanel(store: store)
        shown = bar
        bar.show()
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible })
        settle()
        return (bar, panel)
    }

    /// The right edge of the screen: the leading edge stays only while the wide panel is whole there; otherwise the window
    /// is drawn inside `visibleFrame`, and it goes back in the narrow width without leaving it.
    func testNearTheRightEdgeTheWidePanelIsPulledInsideTheScreen() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let (bar, panel) = try open(store)
        let visible = try XCTUnwrap(panel.screen?.visibleFrame)
        let narrow = panel.frame.width
        panel.setFrameOrigin(NSPoint(x: visible.maxX - narrow - 5, y: panel.frame.minY))
        settle()
        let edgeBefore = panel.frame.minX
        bar.model.hasTarget = true
        settle()
        XCTAssertGreaterThan(panel.frame.width, narrow + 40, "the window did not widen: the check watched nothing")
        XCTAssertLessThanOrEqual(panel.frame.maxX, visible.maxX + 0.01, "the wide panel leaves the screen's right end")
        XCTAssertLessThan(panel.frame.minX, edgeBefore - 40, "the leading edge was kept though the wide panel would not fit")
        bar.model.hasTarget = false
        settle()
        XCTAssertEqual(panel.frame.width, narrow, accuracy: 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxX, visible.maxX + 0.01)
    }

    /// The leading edge holds with the real panel too, and a place left wide is stored against the narrow panel: it
    /// opens again narrow at the same leading edge.
    func testAPanelLeftWideOpensAgainNarrowAtTheSameLeadingEdge() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let (bar, panel) = try open(store)
        let opened = panel.frame
        bar.model.hasTarget = true
        settle()
        XCTAssertGreaterThan(panel.frame.width, opened.width + 40, "the window did not widen: the check watched nothing")
        XCTAssertEqual(panel.frame.minX, opened.minX, accuracy: 0.01, "the target moved the leading edge")
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX - 40, y: panel.frame.minY + 30))
        settle()
        bar.close()
        shown = nil
        XCTAssertEqual(store.object(ScreenshotsSettings.Key.panelOffsetX) as? Double ?? .nan, -40, accuracy: 0.5, "the move was stored against the wide panel")
        let (_, again) = try open(store)
        XCTAssertEqual(again.frame.width, opened.width, accuracy: 0.5)
        XCTAssertEqual(again.frame.minX, opened.minX - 40, accuracy: 0.5, "the stored place does not reopen at the leading edge it was left at")
        XCTAssertEqual(again.frame.minY, opened.minY + 30, accuracy: 0.5)
    }
}
