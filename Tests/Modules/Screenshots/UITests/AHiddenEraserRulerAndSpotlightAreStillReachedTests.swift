import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A row object that no `AnnotationTool` stands for, or that has no key, is still reached with its cell off the row.**
/// `AHiddenToolStillAnswersItsKeyTests` asks the keys of `EditorPalette.rowTools` that have one, which leaves out the
/// eraser and the ruler (no tools) and the spotlight (no key). What is asked here, through the whole overlay built on a
/// store that hides each of them: the eraser's key raises the eraser, the ruler's key raises the ruler and its second
/// press lowers it, and the spotlight is raised by the action its ⋯ menu item sends.
@MainActor
final class AHiddenEraserRulerAndSpotlightAreStillReachedTests: XCTestCase {

    private let rig = HiddenPaletteRig()

    override func tearDown() {
        rig.close()
        super.tearDown()
    }

    func testAHiddenEraserIsRaisedByItsKeyAndPutDownByItsSecondPress() throws {
        try rig.build(store: HiddenPaletteRig.store(hiding: [.eraser]))
        let palette = try XCTUnwrap(rig.overlay?.palette)
        XCTAssertFalse(palette.isOnRow(.eraser), "the subject: the eraser is off the row")
        XCTAssertFalse(palette.erasing, "the subject: nothing is erasing yet")
        rig.overlay?.keyDown(rig.key(EditorKeys.eraserKeyCode))
        XCTAssertTrue(palette.erasing, "the key of a hidden eraser did nothing")
        rig.overlay?.keyDown(rig.key(EditorKeys.eraserKeyCode))
        XCTAssertFalse(palette.erasing, "the second press did not put the hidden eraser down")
    }

    func testAHiddenRulerIsRaisedByItsKeyAndLoweredByItsSecondPress() throws {
        try rig.build(store: HiddenPaletteRig.store(hiding: [.ruler]))
        let palette = try XCTUnwrap(rig.overlay?.palette)
        XCTAssertFalse(palette.isOnRow(.ruler), "the subject: the ruler is off the row")
        XCTAssertFalse(palette.ruler, "the subject: the ruler is down")
        rig.overlay?.keyDown(rig.key(EditorKeys.rulerKeyCode))
        XCTAssertTrue(palette.ruler, "the key of a hidden ruler did nothing")
        rig.overlay?.keyDown(rig.key(EditorKeys.rulerKeyCode))
        XCTAssertFalse(palette.ruler, "the second press did not lower the hidden ruler")
    }

    func testAHiddenSpotlightHasNoKeyAndItsMenuItemRaisesIt() throws {
        XCTAssertFalse(EditorKeys.toolKeys.contains { $0.tool == .spotlight }, "the subject: the spotlight has no key")
        try rig.build(store: HiddenPaletteRig.store(hiding: [.spotlight]))
        let palette = try XCTUnwrap(rig.overlay?.palette)
        XCTAssertFalse(palette.isOnRow(.spotlight), "the subject: the spotlight is off the row")
        let item = EditorMenu.items(for: palette).compactMap { entry -> EditorAction? in
            if case .tool(let title, _, _, let action) = entry, title == ScStr.tool(.spotlight) { return action }
            return nil
        }
        XCTAssertEqual(item, [.tool(.spotlight)], "the menu does not stand in for the hidden spotlight")
        rig.overlay?.perform(try XCTUnwrap(item.first))
        XCTAssertEqual(palette.tool, .spotlight, "the menu item did not raise the hidden spotlight")
    }
}
