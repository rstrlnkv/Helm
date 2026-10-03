import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A panel put back has no move to write when it closes.** «Put the Panel Back» forgets the stored move and the move
/// made since the panel opened: after it, closing the panel writes nothing, and a panel nobody moved writes nothing
/// either. The panel is ordered in for a moment, as the controller does it, and moved the way a drag moves a window
/// (its frame origin changes and AppKit announces it); the store is read from outside, key by key.
@MainActor
final class PuttingThePanelBackLeavesNoMoveBehindTests: XCTestCase {
    private var capture: CapturePanel?
    override func tearDown() { capture?.close(); capture = nil; super.tearDown() }

    private func standing() throws -> (CapturePanel, BarPanel, NamespacedStore) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let bar = CapturePanel(store: store)
        capture = bar
        bar.show()
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible })
        settle()
        return (bar, panel, store)
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }

    private func written(_ store: NamespacedStore) -> Bool {
        store.object(ScreenshotsSettings.Key.panelOffsetX) != nil || store.object(ScreenshotsSettings.Key.panelOffsetY) != nil
    }

    func testAPanelNobodyMovedWritesNoPlaceWhenItCloses() throws {
        let (bar, _, store) = try standing()
        bar.close()
        XCTAssertFalse(written(store), "a panel that stood where it opened wrote a place")
    }

    func testAPanelMovedAndLeftWritesItsMoveWhenItCloses() throws {
        let (bar, panel, store) = try standing()
        let opened = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: opened.x - 40, y: opened.y + 30))
        settle()
        bar.close()
        XCTAssertEqual(store.object(ScreenshotsSettings.Key.panelOffsetX) as? Double ?? .nan, -40, accuracy: 0.5)
        XCTAssertEqual(store.object(ScreenshotsSettings.Key.panelOffsetY) as? Double ?? .nan, 30, accuracy: 0.5)
    }

    func testAPanelMovedAndPutBackWritesNothingWhenItCloses() throws {
        let (bar, panel, store) = try standing()
        let opened = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: opened.x - 40, y: opened.y + 30))
        settle()
        bar.model.putBack()
        settle()
        XCTAssertEqual(panel.frame.origin.x, opened.x, accuracy: 0.5, "the panel did not come back")
        XCTAssertEqual(panel.frame.origin.y, opened.y, accuracy: 0.5)
        bar.close()
        XCTAssertFalse(written(store), "the move the person put back was written when the panel closed")
    }

    func testAMoveMadeAfterPuttingBackIsWritten() throws {
        let (bar, panel, store) = try standing()
        let opened = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: opened.x - 40, y: opened.y + 30))
        settle()
        bar.model.putBack()
        settle()
        panel.setFrameOrigin(NSPoint(x: opened.x + 20, y: opened.y + 10))
        settle()
        bar.close()
        XCTAssertEqual(store.object(ScreenshotsSettings.Key.panelOffsetX) as? Double ?? .nan, 20, accuracy: 0.5)
    }
}
