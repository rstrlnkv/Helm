import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_UI

/// The window's end and the module switched off take an open row and everything it held.
@MainActor
final class TheRowTakesKeyOnlyFromAClickOnItselfTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    /// The window's end with the row open: the row is not open any more, and no state of it is left to be keyed by.
    func testTheEndOfTheWindowAndTheModuleSwitchedOffTakeTheRowAndEverythingItHeld() async throws {
        let s = try PileScene(self, name: "key-off")
        scenes.append(s)
        for width in [400, 420, 440] { try await s.take(width: width) }
        s.toast.unfold()
        s.toast.model.focus = s.toast.model.shot(0)?.id ?? -1
        XCTAssertTrue(s.toast.model.unfolded)
        s.controller.cancel()
        XCTAssertFalse(s.toast.model.unfolded, "the module is off and its row is open")
        XCTAssertNil(s.toast.model.focus)
        XCTAssertTrue(s.toast.model.shots.isEmpty)
        XCTAssertTrue(s.toast.holds.isEmpty)
        XCTAssertFalse(s.toast.model.shown)
        s.toast.unfold()
        XCTAssertFalse(s.toast.model.unfolded, "a dead window unfolded")
    }
}
