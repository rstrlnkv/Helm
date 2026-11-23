import AppKit
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// When the module goes off, the bar leaves the screen and forgets the overlay it picked on.
@MainActor
final class TheModuleOffTakesTheBarAndForgetsTheOverlayTests: XCTestCase {
    private func standingBar() -> BarPanel? {
        NSApplication.shared.windows.compactMap { $0 as? BarPanel }.last { $0.isVisible }
    }

    func testWhenTheModuleGoesOffTheBarIsGoneAndForgetsTheOverlay() async throws {
        let box = try PanelRig.rig(in: self, presentBar: { $0.show() })
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.window)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        box.controller.cancel()
        XCTAssertNil(standingBar())
        XCTAssertFalse(box.controller.bar.selecting)
        XCTAssertFalse(try XCTUnwrap(box.held.overlay).isOpen)
    }
}
