import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A tool taken off the palette's row answers to its key exactly as before.** `EditorKeys` does not read the list: the key
/// is a table from a physical key code to a tool, and the overlay raises the tool the same way for a visible object and a
/// hidden one. What this holds is the whole path from the key to the file: the key raises the tool, a second press puts
/// it down, the stroke drawn with it is that tool's, and a tool remembered from the last capture opens chosen even when it
/// is the one no longer on the row.
///
/// Each tool of the row is hidden in turn, and the keys asked are `EditorKeys.toolKeys`, not a list written here.
@MainActor
final class AHiddenToolStillAnswersItsKeyTests: XCTestCase {

    private let rig = HiddenPaletteRig()

    override func tearDown() {
        rig.close()
        super.tearDown()
    }

    private func code(of tool: AnnotationTool) throws -> Int {
        try XCTUnwrap(EditorKeys.toolKeys.first { $0.tool == tool }?.code, "\(tool) has no key")
    }

    /// The table of keys is the same whatever is hidden: it is a table and has no input.
    func testEveryRowToolHasAKeyAndTheKeyMeansItWhateverIsHidden() throws {
        XCTAssertFalse(EditorPalette.rowTools.isEmpty, "the subject: the row has objects")
        for tool in EditorPalette.rowTools {
            let code = try code(of: tool)
            XCTAssertEqual(EditorKeys.action(keyCode: UInt16(code), flags: []), .tool(tool), "\(tool)")
            XCTAssertNil(EditorKeys.action(keyCode: UInt16(code), flags: .command), "⌘ + the key of \(tool) is not a tool")
        }
    }

    func testTheKeysAreNotAskedOfTheList() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorKeys.swift"))
        for word in ["PaletteItem", "hidden", "isOnRow", "paletteChoices"] {
            XCTAssertFalse(source.contains(word), "EditorKeys reads «\(word)»: a hidden tool would stop answering its key")
        }
        XCTAssertTrue(source.contains("toolKeys"), "the scan found nothing of the key table: it scanned the wrong file")
    }

    /// Hidden, the tool is raised by its key, shown on the model, drawn with, and handed back as that tool's layer.
    func testTheKeyRaisesTheHiddenToolAndTheStrokeIsItsOwn() throws {
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            try rig.build(store: HiddenPaletteRig.store(hiding: [item]))
            XCTAssertFalse(try XCTUnwrap(rig.overlay?.palette).isOnRow(tool), "the subject: \(tool) is off the row")
            XCTAssertNil(rig.overlay?.palette.tool, "the subject: nothing chosen yet")
            rig.overlay?.keyDown(rig.key(try code(of: tool)))
            XCTAssertEqual(rig.overlay?.palette.tool, tool, "\(tool) hidden: its key did not raise it")
            rig.stroke()
            XCTAssertEqual(try rig.drawnTools(), [tool], "\(tool) hidden: the key drew something else")
        }
    }

    /// With every object hidden, every key still raises its tool.
    func testEveryKeyAnswersWithTheWholeRowHidden() throws {
        for tool in EditorPalette.rowTools {
            try rig.build(store: HiddenPaletteRig.store(hiding: PaletteItem.allCases))
            rig.overlay?.keyDown(rig.key(try code(of: tool)))
            XCTAssertEqual(rig.overlay?.palette.tool, tool, "\(tool) with the row empty: its key did nothing")
        }
    }

    /// The same key again puts the tool down, hidden or not: the second press is the editor's rule and not the cell's.
    func testASecondPressPutsAHiddenToolDown() throws {
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            try rig.build(store: HiddenPaletteRig.store(hiding: [item]))
            rig.overlay?.keyDown(rig.key(try code(of: tool)))
            XCTAssertEqual(rig.overlay?.palette.tool, tool, "the subject: raised")
            rig.overlay?.keyDown(rig.key(try code(of: tool)))
            XCTAssertNil(rig.overlay?.palette.tool, "\(tool) hidden: the second press did not put it down")
        }
    }

    /// Keys of the others still answer, and pressing one while a hidden tool is up replaces it.
    func testAnotherKeyReplacesTheHiddenTool() throws {
        let rowTools = EditorPalette.rowTools
        try XCTSkipIf(rowTools.count < 2, "one object on the row: there is no other")
        let hidden = rowTools[0], other = rowTools[1]
        try rig.build(store: HiddenPaletteRig.store(hiding: [try XCTUnwrap(EditorPalette.item(of: hidden))]))
        rig.overlay?.keyDown(rig.key(try code(of: hidden)))
        rig.overlay?.keyDown(rig.key(try code(of: other)))
        XCTAssertEqual(rig.overlay?.palette.tool, other)
        rig.overlay?.keyDown(rig.key(try code(of: hidden)))
        XCTAssertEqual(rig.overlay?.palette.tool, hidden, "the hidden tool's key stopped answering after another's")
    }

    /// The tool the last capture ended on is remembered whether or not it is on the row: the editor opens on it, and the menu
    /// is where it is checked. Nothing resets the person's tool because the object left the row.
    func testARememberedToolThatLeftTheRowStillOpensChosen() throws {
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            let store = HiddenPaletteRig.store(hiding: [item])
            EditorMemory.remember(tool: tool, in: store)
            try rig.build(store: store)
            XCTAssertEqual(rig.overlay?.palette.tool, tool, "\(tool) was the last tool and left the row: the editor did not open on it")
            rig.stroke()
            XCTAssertEqual(try rig.drawnTools(), [tool], "\(tool): the editor opened on another tool than the remembered one")
        }
    }

    /// Choosing by the key is remembered like choosing by a click, hidden or not.
    func testAHiddenToolPickedByKeyIsRememberedForTheNextCapture() throws {
        let tool = try XCTUnwrap(EditorPalette.rowTools.first)
        let item = try XCTUnwrap(EditorPalette.item(of: tool))
        let store = HiddenPaletteRig.store(hiding: [item])
        try rig.build(store: store)
        rig.overlay?.keyDown(rig.key(try code(of: tool)))
        XCTAssertEqual(EditorMemory.read(store).tool, tool, "the key of a hidden tool was not remembered")
    }
}
