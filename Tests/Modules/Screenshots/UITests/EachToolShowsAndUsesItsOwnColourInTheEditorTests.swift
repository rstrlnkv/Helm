import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Every tool of the editor shows, uses and keeps its own colour: a pick with the Pen is not the Marker's.**
///
/// The engine half is `EachToolKeepsItsOwnColourTests`; this file asks the overlay, where a pick is made, with a store behind it
/// and a colour panel that is never shown (`FakeColourPanel`). The seams are the ones the neighbours reach: `perform`,
/// `palette.style` / `palette.lit` / `palette.selectedTool`, the panel's `opened`, and the finished layers handed to the result.
/// The tool artwork's tinted tip is drawn from `EditorPalette.objectCell`; no render here, a scan of what it reads (below).
@MainActor
final class EachToolShowsAndUsesItsOwnColourInTheEditorTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var disk = InMemoryKeyValueStore()
    private var store: NamespacedStore { NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: disk) }

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    @discardableResult
    private func build(panel: FakeColourPanel = FakeColourPanel()) throws -> DisplayID {
        overlay?.close()
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store, colourPanel: panel) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        return id
    }

    private func colours() -> [AnnotationTool: AnnotationInk?] {
        let read = EditorMemory.read(store)
        return Dictionary(uniqueKeysWithValues: AnnotationTool.allCases.map { ($0, read.style(for: $0).color) })
    }

    /// Every tool but `except` holds what it held in `before`.
    private func assertOthersUnchanged(_ before: [AnnotationTool: AnnotationInk?], except allowed: Set<AnnotationTool>, _ what: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let now = colours()
        for tool in AnnotationTool.allCases where !allowed.contains(tool) {
            XCTAssertEqual(now[tool]!, before[tool]!, "\(what): \(tool)'s colour changed", file: file, line: line)
        }
    }

    // MARK: a pick is one tool's, shown and used, and kept for the next editor

    func testAPickWithThePenIsNotTheMarkersAndComesBackWithThePen() throws {
        try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.color(.orange))
        XCTAssertEqual(overlay.palette.style.color, .orange, "the pick shows on the palette")
        overlay.perform(.tool(.highlighter))
        XCTAssertNil(overlay.palette.style.color, "Marker has no colour of its own picked: the Pen's orange followed it")
        XCTAssertEqual(overlay.palette.lit, .yellow, "the Marker's ring is its own default, yellow")
        overlay.perform(.color(.blue))
        XCTAssertEqual(overlay.palette.style.color, .blue)
        overlay.perform(.tool(.pen))
        XCTAssertEqual(overlay.palette.style.color, .orange, "the Pen got its own back")
        XCTAssertEqual(overlay.palette.lit, .orange)
        overlay.perform(.tool(.highlighter))
        XCTAssertEqual(overlay.palette.style.color, .blue, "the Marker kept its own")
        let read = EditorMemory.read(store)
        XCTAssertEqual(read.style(for: .pen).color, .orange)
        XCTAssertEqual(read.style(for: .highlighter).color, .blue)
        XCTAssertNil(read.style(for: .pencil).color, "a tool nobody picked for took a pick")
    }

    func testTheObjectIsDrawnInTheColourOfTheToolItWasDrawnWith() throws {
        let id = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.color(.orange))
        overlay.perform(.tool(.rectangle))
        overlay.perform(.color(.blue))
        // A rectangle with the Rectangle's blue, then a line with the Line's own (nothing picked: red).
        overlay.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 250, y: 220), flags: [])
        overlay.mouseUp(on: id)
        overlay.perform(.tool(.line))
        overlay.mouseDown(on: id, at: CGPoint(x: 300, y: 300), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 400, y: 330), flags: [])
        overlay.mouseUp(on: id)
        overlay.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.map(\.tool), [.rectangle, .line])
        XCTAssertEqual(layers.first?.style.color, .blue)
        XCTAssertNil(layers.last?.style.color, "the Line was drawn in the Rectangle's pick")
        XCTAssertEqual(layers.last?.style.ink(for: .line), AnnotationStyle().ink(for: .line))
    }

    func testEveryToolsPickSurvivesARelaunchAndAFreshOverlayShowsEachOwn() throws {
        try build()
        let first = try XCTUnwrap(overlay)
        first.perform(.tool(.pen))
        first.perform(.color(.orange))
        first.perform(.tool(.highlighter))
        first.perform(.color(.blue))
        first.perform(.tool(.arrow))
        first.perform(.color(.green))
        first.close()
        // The same store, a new overlay: what the next capture reads.
        try build()
        let second = try XCTUnwrap(overlay)
        XCTAssertEqual(second.palette.style.color, .green, "it opens on the last tool, with that tool's colour")
        second.perform(.tool(.pen))
        XCTAssertEqual(second.palette.style.color, .orange)
        second.perform(.tool(.highlighter))
        XCTAssertEqual(second.palette.style.color, .blue)
        second.perform(.tool(.pencil))
        XCTAssertNil(second.palette.style.color, "the Pencil was never picked for")
    }

    // MARK: what the palette shows follows the tool in hand

    func testTheColourPanelIsShownTheColourOfTheToolInHand() throws {
        let panel = FakeColourPanel()
        try build(panel: panel)
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.color(.orange))
        overlay.perform(.tool(.highlighter))
        overlay.perform(.allColours)
        overlay.perform(.tool(.pen))
        overlay.perform(.allColours)
        XCTAssertEqual(panel.opened, [AnnotationStyle().ink(for: .highlighter), .orange],
                       "the panel is not shown the colour of the tool in hand: \(panel.opened)")
    }

    /// `EditorPalette.objectCell` tints each row object from `model.memory.style(for: tool)`, so the palette's model must hold every
    /// tool's own ink after the picks: this reads the value the cell reads, not a render (the source line is checked below as a backstop).
    func testThePaletteModelHoldsEachToolsOwnInkForTheCellsToTint() throws {
        try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.color(.orange))
        overlay.perform(.tool(.highlighter))
        overlay.perform(.color(.blue))
        overlay.perform(.tool(.arrow))   // neither of the two is in hand now
        let memory = overlay.palette.memory
        XCTAssertEqual(memory.style(for: .pen).ink(for: .pen), AnnotationInk.orange, "the Pen's cell would not be orange")
        XCTAssertEqual(memory.style(for: .highlighter).ink(for: .highlighter), AnnotationInk.blue, "the Marker's cell would not be blue")
        XCTAssertNotEqual(memory.style(for: .pen).ink(for: .pen), memory.style(for: .highlighter).ink(for: .highlighter))
        XCTAssertEqual(memory.style(for: .arrow).ink(for: .arrow), AnnotationStyle().ink(for: .arrow), "a tool nobody picked for is tinted by another's pick")
    }

    func testTheCellIsTintedFromTheMemoryOfItsOwnToolInTheSource() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        let after = try XCTUnwrap(source.components(separatedBy: "private func objectCell").dropFirst().first, "no objectCell in the palette")
        let body = String(after.prefix(900))
        XCTAssertTrue(body.contains("PaletteObject(tool: tool"), "control: the scan is on the cell that draws the artwork")
        XCTAssertFalse(body.contains("model.style.ink(for: tool)"), "every row object is tinted with the one style of the tool in hand")
        XCTAssertTrue(body.contains("model.memory.style(for: tool)"), "the cell does not read its own tool's memory")
    }

    /// The Settings row's write is a closure in a SwiftUI view with no seam, so it is read as source: the row that writes `editorColor`
    /// also clears `editorInk`, else the shared ink hides the row's pick (the read half is in `EachToolKeepsItsOwnColourTests`).
    func testTheSettingsRowsWriteClearsTheSharedInkInTheSameBreath() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenshotsSettingsPage.swift"))
        let after = try XCTUnwrap(source.components(separatedBy: "store.set(color.rawValue, for: ScreenshotsSettings.Key.editorColor)").dropFirst().first,
                                  "control: the row's write is not where it was")
        XCTAssertTrue(String(after.prefix(200)).contains("store.set(nil, for: ScreenshotsSettings.Key.editorInk)"), "the row leaves the shared ink in place")
    }

    // MARK: recolouring a selected finished object

    /// The rule (`CaptureOverlay.perform(.color)`): a pick belongs to the selected object's tool, else to the tool last put in hand
    /// (`styleTool`); it recolours the selected object (`layers.recolor`) and is written under that owner. So with a rectangle
    /// selected by the Select pointer after the Pen, the pick is the Rectangle's and never the Pen's.
    func testRecolouringASelectedObjectDoesNotRecolourTheToolThatWasInHandLast() throws {
        let id = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.color(.orange))
        OverlayRig.drawAndSelect(in: overlay, on: id)   // a rectangle, drawn and selected with the Rectangle put down again
        overlay.perform(.tool(.pen))
        overlay.perform(.tool(.pen))                    // the Pen put down: Select pointer, the Pen the last tool in hand
        overlay.mouseDown(on: id, at: CGPoint(x: 200, y: 230), flags: [])
        overlay.mouseUp(on: id)
        XCTAssertEqual(overlay.palette.selectedTool, .rectangle, "control: the rectangle is selected")
        XCTAssertNil(overlay.palette.tool, "control: no tool is chosen")
        let before = colours()
        XCTAssertEqual(before[.pen]!, .orange, "control")
        overlay.perform(.color(.blue))
        XCTAssertEqual(overlay.palette.style.color, .blue, "the selected object takes the pick")
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .orange, "recolouring a rectangle recoloured the Pen")
        assertOthersUnchanged(before, except: [.rectangle], "a pick on a selected rectangle")
        XCTAssertEqual(EditorMemory.read(store).style(for: .rectangle).color, .blue, "the pick is not stored under the selected object's tool")
        XCTAssertEqual(overlay.palette.memory.style(for: .rectangle).color, .blue, "the palette's memory does not show the object's tool")
        XCTAssertEqual(overlay.palette.memory.style(for: .pen).color, .orange, "the palette's memory moved the tool in hand")
        overlay.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.first?.style.color, .blue, "the object was not recoloured")
    }

    // MARK: a pick while a tool with no colour is in hand

    /// The tools whose ink is not read (`Annotation.swift` docs: blur, spotlight; the emoji's colour is its own). A pick made with
    /// one of them chosen is written under that tool (it is `styleTool`) and reaches no other: it may stay that
    /// tool's alone, it may be nobody's, it must not be another tool's.
    func testAPickWhileAColourlessToolIsInHandReachesNoOtherTool() throws {
        for colourless in [AnnotationTool.blur, .spotlight, .emoji] {
            disk = InMemoryKeyValueStore()
            try build()
            let overlay = try XCTUnwrap(overlay)
            overlay.perform(.tool(.pen))
            overlay.perform(.color(.orange))
            overlay.perform(.tool(colourless))
            let before = colours()
            overlay.perform(.color(.blue))
            assertOthersUnchanged(before, except: [colourless], "a pick with \(colourless) in hand")
            XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .orange, "\(colourless): the pick reached the Pen")
        }
    }

    /// Modes with no tool in hand: Select (nothing chosen), the eraser, the ruler, Crop. `styleTool` is still the last tool put in hand, so
    /// a pick made here is written under it. Pinned: a pick in these modes may change one tool's colour at most, the last in hand,
    /// and no other. (The code gives it to the last in hand; the assertion would also pass if it gave it to nobody.)
    func testAPickInAModeWithNoToolChangesAtMostTheToolLastInHand() throws {
        let modes: [(String, EditorAction?)] = [("select", .select), ("eraser", .erase), ("ruler", .toggleRuler), ("crop", .crop)]
        for (name, enter) in modes {
            disk = InMemoryKeyValueStore()
            let panel = FakeColourPanel()
            try build(panel: panel)
            let overlay = try XCTUnwrap(overlay)
            overlay.perform(.tool(.arrow))
            overlay.perform(.color(.orange))
            overlay.perform(.tool(.pen))
            overlay.perform(.color(.green))
            if let enter { overlay.perform(enter) }
            let before = colours()
            overlay.perform(.color(.blue))
            assertOthersUnchanged(before, except: [.pen], "a pick in \(name) mode, the Pen last in hand")
            XCTAssertEqual(EditorMemory.read(store).style(for: .arrow).color, .orange, "\(name): the pick reached the Arrow")
        }
    }
}
