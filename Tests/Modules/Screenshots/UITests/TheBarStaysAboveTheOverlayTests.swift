import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// When the module goes off, the bar leaves the screen and forgets the overlay it picked on.
@MainActor
final class TheBarStaysAboveTheOverlayTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []

    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func rig(timer: CaptureTimer = .none, tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> PanelRig.Rig {
        let box = try PanelRig.rig(timer: timer, presentBar: { $0.show() }, tick: tick)
        boxes.append(box)
        return box
    }

    private func standingBar() -> BarPanel? {
        NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible }
    }

    func testWhenTheModuleGoesOffTheBarIsGoneAndForgetsTheOverlay() async throws {
        let box = try rig()
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        box.controller.teardown()
        XCTAssertNil(standingBar())
        XCTAssertFalse(box.controller.bar.selecting)
        XCTAssertFalse(try XCTUnwrap(box.held.overlay).isOpen)
    }
}
