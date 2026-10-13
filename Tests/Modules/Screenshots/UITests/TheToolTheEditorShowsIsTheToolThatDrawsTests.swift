import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **What the editor's palette draws as the tool in hand is the tool the first drag on the picture draws with**, from either door
/// (the area released on a fresh capture, and Edit on a taken shot's thumbnail), for every tool the store can remember whose drag
/// draws a layer, and the states round it: a tool the person took off the row, the eraser, Crop, the ruler and Select left in the editor before,
/// a second area of one capture (the fresh capture's door only), a click on the tool already chosen.
///
/// Each case reads what the palette itself says (`EditorBarModel.tool` and its eraser and Crop readings) and whether the overlay
/// has a pop-over open, before its first drag, so that a palette that showed nothing could not pass for one that showed the right
/// tool; the case of the tool put down reads the palette and drags nothing. The cases where a drag draws no layer are pinned as
/// they are: Select (the first launch's state: the drag draws a new area), the Emoji tool before an emoji is picked, and the first
/// press after a click on the chosen pen has opened its pop-over (it only closes the pop-over). The text tool, whose press starts
/// a field, is left out: no case here opens on it.
///
/// Every case has a store of its own, in memory; nothing here writes the app's settings.
@MainActor
final class TheToolTheEditorShowsIsTheToolThatDrawsTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let dragged = CGRect(x: 150, y: 150, width: 150, height: 100)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func store(remembering tool: AnnotationTool? = nil, hiding items: Set<PaletteItem> = []) -> NamespacedStore {
        let kept = HiddenPaletteRig.store(hiding: items)
        if let tool { EditorMemory.remember(tool: tool, in: kept) }
        return kept
    }

    /// The editor over the first real screen's frame: opened on the picture as the thumbnail's Edit does, or on an area released by a drag.
    private func open(_ kept: NamespacedStore, fromThumbnail: Bool) throws -> DisplayID {
        overlay?.close()
        let frames = try OverlayRig.frames(scale: 1)
        let id = try XCTUnwrap(frames.first?.id)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []),
                                   picture: fromThumbnail ? (id, area) : nil, store: kept) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        if !fromThumbnail {
            built.mouseDown(on: id, at: area.origin, flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
            built.mouseUp(on: id)
        }
        XCTAssertEqual(built.editedArea, area, "the subject: the editor is open on the area")
        XCTAssertTrue(built.editedLayers.isEmpty, "the subject: nothing is drawn yet")
        return id
    }

    private func drag(_ id: DisplayID) {
        overlay?.mouseDown(on: id, at: dragged.origin, flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: dragged.maxX, y: dragged.maxY), flags: [])
        overlay?.mouseUp(on: id)
    }

    /// What the palette says it has in hand, with no mode over it.
    private func assertShows(_ tool: AnnotationTool?, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(overlay?.palette.tool, tool, "\(label): the palette shows another tool", file: file, line: line)
        XCTAssertEqual(overlay?.palette.erasing, false, "\(label): the palette shows the eraser", file: file, line: line)
        XCTAssertEqual(overlay?.palette.cropping, false, "\(label): the palette shows Crop", file: file, line: line)
        XCTAssertEqual(overlay?.popoverIsOpen, false, "\(label): a pop-over is open", file: file, line: line)
    }

    private var drawn: [AnnotationTool] { overlay?.editedLayers.map(\.tool) ?? [] }

    /// Which mode the editor is in, and the tool the palette shows under it: one value, so that a mode is told from the others.
    private struct ModeReading: Equatable {
        let tool: AnnotationTool?
        let erasing: Bool
        let cropping: Bool
        let ruler: Bool
    }

    /// The eraser, Crop and the ruler as the overlay holds them; the tool is the palette's.
    private func overlayModeReading() -> ModeReading {
        ModeReading(tool: overlay?.palette.tool, erasing: overlay?.isErasing == true, cropping: overlay?.isCropping == true,
                    ruler: overlay?.rulerOnThePicture != nil)
    }

    /// The same four as the palette shows them.
    private func paletteModeReading() -> ModeReading {
        ModeReading(tool: overlay?.palette.tool, erasing: overlay?.palette.erasing == true, cropping: overlay?.palette.cropping == true,
                    ruler: overlay?.palette.ruler == true)
    }

    // MARK: - The tool the store remembers

    /// Every tool whose drag draws, remembered by the last editor and opened by either door. The two tools left out are named: the
    /// text tool's press starts a field, and the Emoji tool has a case of its own.
    func testTheRememberedToolIsTheOneTheFirstDragDraws() throws {
        let leftOut: Set<AnnotationTool> = [.text, .emoji]
        let tools = AnnotationTool.allCases.filter { !leftOut.contains($0) }
        for fromThumbnail in [false, true] {
            for tool in tools {
                let label = "\(tool) from \(fromThumbnail ? "the thumbnail" : "a fresh capture")"
                let id = try open(store(remembering: tool), fromThumbnail: fromThumbnail)
                assertShows(tool, label)
                drag(id)
                XCTAssertEqual(drawn, [tool], "\(label): the drag drew another thing, or none")
                XCTAssertEqual(overlay?.palette.tool, tool, "\(label): the drag changed the tool in hand")
            }
        }
    }

    /// A tool taken off the row stands in the ⋯ menu and still draws the first drag.
    func testARememberedToolTakenOffTheRowStillDraws() throws {
        let items = HiddenPaletteRig.rowItems.filter { AnnotationTool(rawValue: $0.rawValue).map(EditorPalette.rowTools.contains) == true }
        XCTAssertFalse(items.isEmpty, "the subject: row objects that are tools")
        for item in items {
            let tool = try XCTUnwrap(AnnotationTool(rawValue: item.rawValue))
            for fromThumbnail in [false, true] {
                let id = try open(store(remembering: tool, hiding: [item]), fromThumbnail: fromThumbnail)
                XCTAssertEqual(overlay?.palette.isOnRow(tool), false, "the subject: \(item) is off the row")
                assertShows(tool, "\(tool) hidden")
                drag(id)
                XCTAssertEqual(drawn, [tool], "\(tool) hidden, thumbnail \(fromThumbnail): the drag drew another thing, or none")
            }
        }
    }

    // MARK: - No tool: the first launch

    /// An empty store opens on Select, and Select's drag is the area's, which is what it shows and does from both doors.
    func testAnEmptyStoreOpensOnSelectAndTheDragDrawsANewArea() throws {
        for fromThumbnail in [false, true] {
            let id = try open(store(), fromThumbnail: fromThumbnail)
            assertShows(nil, "empty store, thumbnail \(fromThumbnail)")
            drag(id)
            XCTAssertEqual(drawn, [], "Select drew a layer")
            XCTAssertEqual(overlay?.editedArea, dragged, "Select's drag did not make the area it dragged")
        }
    }

    /// A tool put down in the last editor is Select in the next.
    func testAToolPutDownIsSelectInTheNextEditor() throws {
        let kept = store()
        _ = try open(kept, fromThumbnail: false)
        overlay?.perform(.tool(.pen))
        assertShows(.pen, "pen picked")
        overlay?.perform(.tool(.pen))
        assertShows(nil, "pen put down")
        for fromThumbnail in [false, true] {
            _ = try open(kept, fromThumbnail: fromThumbnail)
            assertShows(nil, "after a tool put down, thumbnail \(fromThumbnail)")
        }
    }

    // MARK: - What the last editor left

    /// The eraser, Crop and the ruler are modes of one editor and are not remembered; Select is, as no tool.
    func testTheModesOfTheLastEditorLeaveTheToolAndNothingElse() throws {
        let modes: [(String, EditorAction, AnnotationTool?, ModeReading)] = [
            ("eraser", .erase, .rectangle, ModeReading(tool: .rectangle, erasing: true, cropping: false, ruler: false)),
            ("Crop", .crop, .rectangle, ModeReading(tool: nil, erasing: false, cropping: true, ruler: false)),
            ("ruler", .toggleRuler, .rectangle, ModeReading(tool: .rectangle, erasing: false, cropping: false, ruler: true)),
            ("Select", .select, nil, ModeReading(tool: nil, erasing: false, cropping: false, ruler: false))]
        for (name, action, next, on) in modes {
            let kept = store()
            _ = try open(kept, fromThumbnail: false)
            overlay?.perform(.tool(.rectangle))
            overlay?.perform(action)
            XCTAssertEqual(overlayModeReading(), on, "the subject: \(name) is on, the overlay's modes under the palette's tool")
            XCTAssertEqual(paletteModeReading(), on, "the subject: \(name) is on, the palette's reading")
            for fromThumbnail in [false, true] {
                let id = try open(kept, fromThumbnail: fromThumbnail)
                assertShows(next, "\(name) left behind, thumbnail \(fromThumbnail)")
                XCTAssertNil(overlay?.rulerOnThePicture, "\(name): the ruler came back")
                drag(id)
                if let next { XCTAssertEqual(drawn, [next], "\(name) left behind, thumbnail \(fromThumbnail): the drag drew another thing, or none") }
            }
        }
    }

    // MARK: - A second area of one capture

    /// With the tool put down, a drag beside the area makes a second area of the same capture; a tool picked there is the one the palette shows and the drag draws with.
    func testAToolPickedInASecondAreaOfOneCaptureIsShownAndDraws() throws {
        let id = try open(store(remembering: .pen), fromThumbnail: false)
        overlay?.perform(.tool(.pen))
        assertShows(nil, "pen put down")
        overlay?.mouseDown(on: id, at: CGPoint(x: 600, y: 500), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 800, y: 700), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(overlay?.editedArea, CGRect(x: 600, y: 500, width: 200, height: 200), "the subject: a second area")
        overlay?.perform(.tool(.highlighter))
        assertShows(.highlighter, "highlighter picked in the second area")
        overlay?.mouseDown(on: id, at: CGPoint(x: 620, y: 520), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 700, y: 600), flags: [])
        overlay?.mouseUp(on: id)
        XCTAssertEqual(drawn, [.highlighter])
    }

    // MARK: - A drag that draws no layer, as it is

    /// A click on the pen already chosen opens its pop-over; the first press on the picture after that only closes it.
    func testTheFirstPressAfterAClickOnTheChosenToolOnlyClosesItsPopover() throws {
        for fromThumbnail in [false, true] {
            let id = try open(store(remembering: .pen), fromThumbnail: fromThumbnail)
            assertShows(.pen, "pen remembered")
            overlay?.perform(EditorPalette.action(forClickOn: .pen, chosen: overlay?.palette.tool, anchorX: 10))
            XCTAssertEqual(overlay?.popoverIsOpen, true, "the click on the chosen tool did not open its pop-over")
            XCTAssertEqual(overlay?.palette.tool, .pen, "the click on the chosen tool put it down")
            drag(id)
            XCTAssertEqual(drawn, [], "the press that closes the pop-over drew")
            assertShows(.pen, "after the closing press")
            drag(id)
            XCTAssertEqual(drawn, [.pen], "the press after the pop-over closed did not draw")
        }
    }

    /// The Emoji tool places nothing before an emoji is picked in its grid, and places one after; the remembered tool is the tool only.
    func testTheEmojiToolDrawsNothingUntilAnEmojiIsPickedInTheGrid() throws {
        for fromThumbnail in [false, true] {
            let id = try open(store(remembering: .emoji), fromThumbnail: fromThumbnail)
            assertShows(.emoji, "emoji remembered")
            drag(id)
            XCTAssertEqual(drawn, [], "the Emoji tool placed something with none picked")
            overlay?.perform(.pickEmoji("\u{1F600}"))
            drag(id)
            XCTAssertEqual(drawn, [.emoji], "an emoji picked in the grid was not placed by the next press")
        }
    }
}
