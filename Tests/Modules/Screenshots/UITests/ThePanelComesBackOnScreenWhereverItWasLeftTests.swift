import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The real panel, on the real screens of whoever runs this, comes up inside the visible frame of the screen under the
/// pointer, whatever the store says about where it was left.** An offset made on a desk that is gone, one that is
/// huge, one that is not a number, each axis alone, and «Put the Panel Back». The place is **written only if the person
/// moved the panel**: an untouched panel, however long it stood and wherever it had to be pulled to, leaves the
/// stored move as it found it. The panel is ordered in for a moment, as the controller does, and put away.
@MainActor
final class ThePanelComesBackOnScreenWhereverItWasLeftTests: XCTestCase {

    private var open: [CapturePanel] = []
    override func tearDown() {
        open.forEach { $0.close() }
        open = []
        super.tearDown()
    }

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        for (key, value) in values { store.set(value, for: key) }
        return store
    }

    private func visible() throws -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)
        return screen.visibleFrame
    }

    /// The panel `show()` ordered in, found as a window of the application.
    private func shown(_ capture: CapturePanel) throws -> BarPanel {
        capture.show()
        open.append(capture)
        let found = NSApplication.shared.windows.compactMap { $0 as? BarPanel }.filter(\.isVisible)
        return try XCTUnwrap(found.last, "show() put no panel on a screen")
    }

    private let x = ScreenshotsSettings.Key.panelOffsetX, y = ScreenshotsSettings.Key.panelOffsetY

    func testAnOffsetThatIsHugeOrNotANumberOrNotEvenANumberLeavesThePanelOnTheScreen() throws {
        let visible = try visible()
        let hostile: [Any] = [1e300, -1e300, 1e6, -1e6, Double.nan, Double.infinity, "left", true, 0]
        for dx in hostile {
            for dy in hostile {
                let capture = CapturePanel(store: store([x: dx, y: dy]))
                let panel = try shown(capture)
                let frame = panel.frame
                XCTAssertTrue(visible.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                              "x=\(dx) y=\(dy): the panel stands at \(frame), outside \(visible)")
                capture.close()
                open.removeAll()
            }
        }
    }

    func testAFarOffsetPutsThePanelAgainstTheEdgeItWasPushedTowardAndNotTheOther() throws {
        let visible = try visible()
        let right = try shown(CapturePanel(store: store([x: 1e300, y: 1e300]))).frame
        XCTAssertEqual(right.maxX, visible.maxX, accuracy: 1)
        XCTAssertEqual(right.maxY, visible.maxY, accuracy: 1)
        open.forEach { $0.close() }; open = []
        let left = try shown(CapturePanel(store: store([x: -1e300, y: -1e300]))).frame
        XCTAssertEqual(left.minX, visible.minX, accuracy: 1)
        XCTAssertEqual(left.minY, visible.minY, accuracy: 1)
    }

    func testEachAxisIsJudgedAlone() throws {
        let visible = try visible()
        let standard = try shown(CapturePanel(store: store())).frame
        XCTAssertEqual(standard.midX, visible.midX, accuracy: 1, "the place by default is not the bottom centre")
        open.forEach { $0.close() }; open = []
        let bad = try shown(CapturePanel(store: store([x: "left", y: -40.0]))).frame
        XCTAssertEqual(bad.midX, visible.midX, accuracy: 1, "a bad x took a good y with it, or moved the panel")
        XCTAssertEqual(bad.minY, max(visible.minY, standard.minY - 40), accuracy: 1, "a bad x lost the good y")
        open.forEach { $0.close() }; open = []
        let other = try shown(CapturePanel(store: store([x: -60.0, y: Double.nan]))).frame
        XCTAssertEqual(other.minX, standard.minX - 60, accuracy: 1, "a bad y lost the good x")
        XCTAssertEqual(other.minY, standard.minY, accuracy: 1)
    }

    func testPutThePanelBackStandsItWhereItOpensAndForgetsTheMove() throws {
        let visible = try visible()
        let s = store([x: -80.0, y: 120.0])
        let capture = CapturePanel(store: s)
        let panel = try shown(capture)
        let away = panel.frame
        capture.model.putBack()
        XCTAssertNotEqual(panel.frame.origin, away.origin, "Put the Panel Back left the panel where it was")
        XCTAssertEqual(panel.frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(panel.frame.minY, visible.minY + PanelPlace.rise, accuracy: 1)
        XCTAssertNil(s.object(x)); XCTAssertNil(s.object(y))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        capture.close()
        open = []
        XCTAssertNil(s.object(x), "the way back was undone at close: the place it moved to was written as a drag")
        XCTAssertNil(s.object(y))
    }

    func testAPanelThatWasMovedIsWrittenAtCloseAndStandsThereNextTime() throws {
        let visible = try visible()
        let s = store()
        let capture = CapturePanel(store: s)
        let panel = try shown(capture)
        panel.setFrameOrigin(NSPoint(x: visible.minX + 37, y: visible.minY + 211))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        capture.close()
        open = []
        XCTAssertNotNil(s.object(x), "a dragged panel was not remembered")
        let again = try shown(CapturePanel(store: s)).frame
        XCTAssertEqual(again.minX, visible.minX + 37, accuracy: 1)
        XCTAssertEqual(again.minY, visible.minY + 211, accuracy: 1)
    }

    /// The panel opens, stands for a while and closes with nobody touching it: the stored move is not written, least of
    /// all the move that was only pulled in to fit this screen.
    func testAPanelNobodyMovedWritesNothingEvenAfterItStoodAWhile() throws {
        let s = store()
        let capture = CapturePanel(store: s)
        _ = try shown(capture)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        capture.close()
        open = []
        XCTAssertNil(s.object(x), "an untouched panel wrote its place at close")
        XCTAssertNil(s.object(y))
    }

    func testAnOffsetPulledInToFitIsNotRewrittenByAnUntouchedPanel() throws {
        let s = store([x: 1e6, y: -1e6])
        let capture = CapturePanel(store: s)
        _ = try shown(capture)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        capture.close()
        open = []
        XCTAssertEqual(s.object(x) as? Double, 1e6, "the move made on a larger desk was overwritten with the clamped one")
        XCTAssertEqual(s.object(y) as? Double, -1e6)
    }

    func testShowingTheSamePanelTwiceKeepsOneWindow() throws {
        let capture = CapturePanel(store: store())
        _ = try shown(capture)
        let before = NSApplication.shared.windows.compactMap { $0 as? BarPanel }.filter(\.isVisible).count
        capture.show()
        let after = NSApplication.shared.windows.compactMap { $0 as? BarPanel }.filter(\.isVisible).count
        XCTAssertEqual(after, before, "a second show() put a second panel on the screen")
    }
}
