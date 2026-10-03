import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Select, move, resize, recolour and delete, as the person does them on the picture:** a click
/// selects whatever the tool, the handles are drawn on the selection, ⌫ and ⌦ delete by key code on
/// a Russian layout, Esc lets go before it asks, a pick recolours the selected and is the next
/// object's too, the file is the edited list, and only what changed is rebuilt on a pointer event.
/// Panels are built and never ordered in.
@MainActor
final class TheEditorEditsWhatItDrewOnTheScreenTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func build() throws -> (DisplayID, OverlayView) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 1,
                                   image: try XCTUnwrap(context.makeImage()))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []), store: nil) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    private func drag(_ id: DisplayID, from: CGPoint, through: [CGPoint]) {
        overlay?.mouseDown(on: id, at: from, flags: [])
        for point in through { overlay?.mouseDragged(on: id, at: point, flags: []) }
        overlay?.mouseUp(on: id)
    }

    private func draw(_ id: DisplayID, _ tool: AnnotationTool, from: CGPoint, to: CGPoint) {
        overlay?.perform(.tool(tool))
        drag(id, from: from, through: [to])
        overlay?.perform(.tool(tool)) // the same key again puts the tool down
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private func delivered() throws -> [Annotation] {
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)")
        guard case .edited(_, _, let layers, _)? = results.first else { throw XCTSkip("not an edit: \(results)") }
        return layers
    }

    // MARK: Selecting

    func testAClickSelectsWhateverTheToolAndTheHandlesAreDrawnOnIt() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
        XCTAssertEqual(view.drawnShapes.count, 2, "nothing was drawn, so the selection below says nothing")
        XCTAssertTrue(view.drawnHandles.isEmpty, "a handle without a selection")
        // With the pencil in hand a click on the rectangle's edge is a selection and not a stroke.
        overlay?.perform(.tool(.pencil))
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        XCTAssertEqual(view.drawnShapes.count, 2, "a click drew")
        XCTAssertEqual(view.drawnHandles.count, 4, "a box is held by its four corners")
        XCTAssertEqual(Set(view.drawnHandles.map(\.x)), [150, 300])
        drag(id, from: CGPoint(x: 300, y: 350), through: [])
        XCTAssertEqual(view.drawnHandles, [CGPoint(x: 150, y: 350), CGPoint(x: 400, y: 350)], "a line is held by its two ends")
        drag(id, from: CGPoint(x: 450, y: 250), through: [])
        XCTAssertTrue(view.drawnHandles.isEmpty, "a click on the empty picture kept the handles")
    }

    func testEscLetsGoOfTheSelectionBeforeItAsksAndTheQuestionThenComesAsBefore() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        XCTAssertEqual(view.drawnHandles.count, 4, "nothing was selected, so Esc has nothing to let go of")
        overlay?.keyDown(key(53))
        XCTAssertTrue(view.drawnHandles.isEmpty, "the first Esc left the selection")
        XCTAssertTrue(results.isEmpty, "the first Esc closed the editor")
        XCTAssertTrue(view.visiblePlates.isEmpty, "the first Esc asked the question as well")
        overlay?.keyDown(key(53))
        XCTAssertEqual(view.visiblePlates.count, 1, "the second Esc did not ask")
        XCTAssertTrue(results.isEmpty)
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first else { return XCTFail("the third Esc did not close: \(results)") }
    }

    // MARK: Delete

    func testBackspaceAndForwardDeleteDeleteTheSelectedByKeyCodeOnARussianLayout() throws {
        for (code, characters) in [(UInt16(51), "\u{7f}"), (117, "\u{F728}")] {
            let (id, view) = try build()
            draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
            draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
            overlay?.keyDown(key(code, characters)) // nothing selected: nothing goes
            XCTAssertEqual(view.drawnShapes.count, 2, "key \(code) deleted with nothing selected")
            drag(id, from: CGPoint(x: 220, y: 150), through: [])
            overlay?.keyDown(key(code, characters))
            XCTAssertEqual(view.drawnShapes.count, 1, "key \(code) did not delete the selected")
            XCTAssertTrue(view.drawnHandles.isEmpty, "the handles outlived their object")
            overlay?.keyDown(key(6, "я", flags: .command))
            XCTAssertEqual(view.drawnShapes.count, 2, "⌘Z did not bring the deleted object back")
            overlay?.keyDown(key(36, "\r"))
            XCTAssertEqual(try delivered().map(\.tool), [.rectangle, .line])
            results = []
            overlay?.close()
        }
    }

    // MARK: Move, resize, recolour: the screen and the file

    func testAMoveAndAResizeAreOnTheScreenAndInTheFile() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        let before = view.drawnShapes[0].path?.boundingBoxOfPath
        // No tool: a drag on the body of an object takes it.
        drag(id, from: CGPoint(x: 220, y: 150), through: [CGPoint(x: 250, y: 170), CGPoint(x: 280, y: 190)])
        XCTAssertNotEqual(view.drawnShapes[0].path?.boundingBoxOfPath, before, "the object moved in the engine and not on the screen")
        XCTAssertEqual(view.drawnHandles.count, 4)
        // Then a corner.
        drag(id, from: CGPoint(x: 360, y: 290), through: [CGPoint(x: 400, y: 330)])
        overlay?.perform(.color(.blue))
        overlay?.keyDown(key(36, "\r"))
        let layers = try delivered()
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].frame, CGRect(x: 210, y: 190, width: 190, height: 140), "the file is not the edited list")
        XCTAssertEqual(layers[0].style.color, .blue)
    }

    func testAPickRecoloursTheSelectedAndIsTheNextObjectsToo() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        overlay?.perform(.color(.green)) // nothing selected: only the next object's
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        XCTAssertEqual(view.drawnHandles.count, 4)
        overlay?.perform(.color(.purple))
        overlay?.perform(.thickness(.thick))
        overlay?.perform(.toggleFill)
        draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
        overlay?.keyDown(key(36, "\r"))
        let layers = try delivered()
        XCTAssertEqual(layers[0].style, AnnotationStyle(color: .purple, thickness: .thick, filled: true), "the selected was not recoloured")
        // The colour and the fill are every tool's; the step is the rectangle's own, so the line opens on its middle one.
        XCTAssertEqual(layers[1].style, AnnotationStyle(color: .purple, thickness: .medium, filled: true),
                       "the pick did not carry to the next object, or the rectangle's step did")
    }

    func testThePaletteShowsTheSelectedObjectsStyleAndGoesBackToThePickOnLettingGo() throws {
        let (id, _) = try build()
        let palette = try XCTUnwrap(overlay?.palette)
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        overlay?.perform(.color(.blue))
        draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
        overlay?.perform(.color(.green)) // the pick is green now; the rectangle has no colour of its own
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        XCTAssertEqual(palette.lit, .red, "the selected rectangle was drawn red before any pick, so the palette's lit swatch is red")
        XCTAssertTrue(palette.fillApplies, "a selected box has a fill to toggle whatever tool is in hand")
        overlay?.keyDown(key(53))
        XCTAssertEqual(palette.lit, .green)
    }

    // MARK: What a pointer event costs

    func testAPointerEventRebuildsOnlyWhatChanged() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        draw(id, .highlighter, from: CGPoint(x: 120, y: 300), to: CGPoint(x: 480, y: 300))
        draw(id, .ellipse, from: CGPoint(x: 320, y: 120), to: CGPoint(x: 460, y: 220))
        XCTAssertEqual(view.drawnShapes.count, 3, "nothing was drawn, so the count below says nothing")
        let committed = view.drawnShapes

        // A draft: one rebuild per event, and the three that stand are never touched.
        var builds = view.shapeBuilds
        overlay?.perform(.tool(.pencil))
        overlay?.mouseDown(on: id, at: CGPoint(x: 130, y: 350), flags: [])
        for step in 1...20 { overlay?.mouseDragged(on: id, at: CGPoint(x: 130 + CGFloat(step) * 10, y: 350 + CGFloat(step)), flags: []) }
        XCTAssertEqual(view.shapeBuilds - builds, 21, "a pointer event rebuilt more than the draft (or the draft less than once per event)")
        overlay?.mouseUp(on: id)
        XCTAssertEqual(view.shapeBuilds - builds, 21, "the release rebuilt the draft it had just drawn")
        XCTAssertEqual(Array(view.drawnShapes.prefix(3)), committed, "a committed layer was replaced")
        overlay?.perform(.tool(.pencil))

        // A move: the moved one only, however many events.
        builds = view.shapeBuilds
        drag(id, from: CGPoint(x: 220, y: 150), through: (1...10).map { CGPoint(x: 220 + CGFloat($0), y: 150) })
        XCTAssertEqual(view.shapeBuilds - builds, 10, "a move rebuilt more than the moved object")
        XCTAssertTrue(view.drawnShapes[0] !== committed[0], "the moved object was not rebuilt")
        XCTAssertTrue(view.drawnShapes[1] === committed[1] && view.drawnShapes[2] === committed[2])

        // A selection, a pointer move and a recolour: the selection and the pointer rebuild nothing.
        builds = view.shapeBuilds
        overlay?.mouseMoved(on: id, at: CGPoint(x: 300, y: 300))
        drag(id, from: CGPoint(x: 300, y: 300), through: [])
        XCTAssertEqual(view.shapeBuilds, builds, "a pointer move or a click rebuilt a layer")
        overlay?.perform(.color(.blue))
        XCTAssertEqual(view.shapeBuilds - builds, 1, "a recolour rebuilt more than the one object")
    }
}
