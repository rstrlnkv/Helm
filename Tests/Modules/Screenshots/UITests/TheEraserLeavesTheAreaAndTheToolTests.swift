import AppKit
import Carbon.HIToolbox
import CoreGraphics
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The eraser is a mode and takes only layers: the area, its size, the chosen tool and what the editor remembers are
/// as they were.** It is on from its key (E) or its object in the row, raised there; a drag takes away the layers its
/// circle meets, they fade to 30 % while the drag is open and go at the release, in one undo step; Esc in the middle of
/// the drag takes none; choosing a tool, or Select, puts the eraser down. It opens no pop-over and is not remembered.
///
/// In-process: the panels are built and not ordered in. What it would print if it failed totally: an eraser that did
/// nothing leaves four shapes after the drag and fails the first count; one that took the tool with it fails
/// `palette.tool`.
@MainActor
final class TheEraserLeavesTheAreaAndTheToolTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func memory() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    /// A fresh overlay with an area released, no tool picked by this fixture.
    private func opened(store: NamespacedStore? = nil) throws -> (overlay: CaptureOverlay, display: DisplayID) {
        overlay?.close()
        results = []
        let frames = try OverlayRig.frames()
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let display = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: display, at: area.origin, flags: [])
        built.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: display)
        return (built, display)
    }

    /// An overlay with an area released and four lines drawn with the Line tool, at y 150, 200, 250 and 350; the tool is
    /// still the Line.
    private func fourLines() throws -> (display: DisplayID, view: OverlayView) {
        let (built, display) = try opened()
        built.perform(.tool(.line))
        for y in [150, 200, 250, 350] as [CGFloat] {
            built.mouseDown(on: display, at: CGPoint(x: 150, y: y), flags: [])
            built.mouseDragged(on: display, at: CGPoint(x: 450, y: y), flags: [])
            built.mouseUp(on: display)
        }
        let view = try XCTUnwrap(built.view(for: display))
        XCTAssertEqual(view.drawnShapes.count, 4, "the fixture drew fewer than four lines")
        return (display, view)
    }

    private func esc() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    }

    private func opacities(_ view: OverlayView) -> [Float] { view.drawnShapes.map(\.opacity) }

    func testADragFadesWhatItMeetsAndTheReleaseTakesItInOneStepAndTheToolIsAsItWas() throws {
        let (display, view) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.erase)
        XCTAssertTrue(overlay.isErasing)
        XCTAssertTrue(overlay.palette.erasing, "the palette does not show the eraser raised")
        XCTAssertEqual(overlay.palette.tool, .line, "the eraser took the chosen tool")
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 120), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 220), flags: [])
        XCTAssertEqual(opacities(view), [0.3, 0.3, 1, 1], "the layers the circle met do not fade to 30 %, or others do")
        XCTAssertEqual(view.drawnShapes.count, 4, "a layer went before the release")
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 270), flags: [])
        XCTAssertEqual(opacities(view), [0.3, 0.3, 0.3, 1])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 1, "the release did not take the three")
        XCTAssertEqual(opacities(view), [1], "the layer left stays faded")
        XCTAssertEqual(overlay.palette.tool, .line, "the drag changed the chosen tool")
        XCTAssertTrue(overlay.isErasing, "the eraser went off at the release")
        overlay.perform(.undo)
        XCTAssertEqual(view.drawnShapes.count, 4, "one undo did not bring back all three")
        XCTAssertEqual(opacities(view), [1, 1, 1, 1])
        overlay.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else { return XCTFail("nothing was handed over: \(results)") }
        XCTAssertEqual(local, area, "the area changed")
        XCTAssertEqual(layers.count, 4)
    }

    func testTheCircleHasTheRadiusOfTheCursor() throws {
        let (display, view) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.erase)
        // The line at y 150 is five points wide: a press 11 points under its middle is inside the circle's reach, 12.5 is not.
        overlay.mouseDown(on: display, at: CGPoint(x: 600, y: 150 + 12.5), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 150 + 12.5), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 4, "the circle took a line it does not reach")
        overlay.mouseDown(on: display, at: CGPoint(x: 600, y: 150 + 11), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 150 + 11), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 3, "the circle missed a line it reaches")
        let cursor = OverlayView.eraserCursor
        XCTAssertEqual(cursor.image.size.width, CaptureOverlay.eraserRadius * 2 + 2, "the cursor is not a circle of the eraser's radius")
        XCTAssertEqual(cursor.hotSpot, NSPoint(x: cursor.image.size.width / 2, y: cursor.image.size.height / 2))
    }

    func testEscMidDragTakesNothingAndLeavesTheEraserOn() throws {
        let (display, view) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.erase)
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 120), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 270), flags: [])
        XCTAssertEqual(opacities(view), [0.3, 0.3, 0.3, 1])
        overlay.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "Esc closed the editor: \(results)")
        XCTAssertEqual(opacities(view), [1, 1, 1, 1], "the layers stay faded after the Esc")
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 4, "the release after the Esc took the layers")
        XCTAssertTrue(overlay.isErasing, "Esc put the eraser down")
        overlay.perform(.undo)
        XCTAssertEqual(view.drawnShapes.count, 3, "the cancelled drag left a step")
        XCTAssertNotNil(overlay.chrome(on: display), "the palette did not come back")
    }

    func testTheSelectedObjectOutsideThePathStaysSelectedAndOneInsideItGoes() throws {
        let (display, view) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        // A click with the Line tool on a line selects it; the fourth, at y 350.
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 350), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertFalse(view.drawnHandles.isEmpty, "the fixture selected nothing")
        overlay.perform(.erase)
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 120), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 270), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 1)
        XCTAssertFalse(view.drawnHandles.isEmpty, "the selection outside the path was let go of")
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 340), flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: 300, y: 360), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 0)
        XCTAssertTrue(view.drawnHandles.isEmpty, "the handles of an erased object are still on the screen")
    }

    func testAPressOnAHandleOfTheSelectedObjectIsStillAnErasePress() throws {
        let (display, view) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        overlay.mouseDown(on: display, at: CGPoint(x: 300, y: 150), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertFalse(view.drawnHandles.isEmpty, "the fixture selected nothing")
        let handle = try XCTUnwrap(view.drawnHandles.first)
        overlay.perform(.erase)
        overlay.mouseDown(on: display, at: handle, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: handle.x + 5, y: handle.y + 5), flags: [])
        overlay.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 3, "a press on a handle resized the object instead of erasing it")
    }

    func testAToolOrSelectPutsTheEraserDownAndTheKeyTogglesItAndNothingIsRemembered() throws {
        let store = memory()
        let (overlay, _) = try opened(store: store)
        overlay.perform(.tool(.pen))
        overlay.perform(EditorKeys.action(keyCode: UInt16(kVK_ANSI_E), flags: []))
        XCTAssertTrue(overlay.isErasing)
        overlay.perform(EditorKeys.action(keyCode: UInt16(kVK_ANSI_E), flags: []))
        XCTAssertFalse(overlay.isErasing, "the key again did not put the eraser down")
        overlay.perform(.erase)
        overlay.perform(.tool(.pen))
        XCTAssertFalse(overlay.isErasing, "a tool did not put the eraser down")
        XCTAssertEqual(overlay.palette.tool, .pen, "the tool chosen under the eraser was put down by the same press")
        overlay.perform(.erase)
        overlay.perform(.select)
        XCTAssertFalse(overlay.isErasing, "Select did not put the eraser down")
        XCTAssertNil(overlay.palette.tool)
        overlay.perform(.tool(.pencil))
        overlay.perform(.erase)
        XCTAssertEqual(EditorMemory.read(store).tool, .pencil, "the eraser was written over the remembered tool")
        overlay.perform(.exit(.confirm))
        XCTAssertFalse(results.isEmpty)
        // The next capture opens with the last drawing tool and no eraser.
        let (next, _) = try opened(store: store)
        XCTAssertFalse(next.isErasing, "the eraser was remembered across captures")
        XCTAssertEqual(next.palette.tool, .pencil, "the next capture did not open with the last drawing tool")
        XCTAssertFalse(next.palette.erasing)
    }

    func testTheSecondClickOpensNothingAndTheMenuItemIsDisabledAndNoToolIsChecked() throws {
        let (_, _) = try fourLines()
        let overlay = try XCTUnwrap(overlay)
        XCTAssertEqual(EditorPalette.action(forClickOnEraser: false), .erase)
        overlay.perform(EditorPalette.action(forClickOnEraser: false))
        XCTAssertTrue(overlay.isErasing)
        overlay.perform(EditorPalette.action(forClickOnEraser: true))
        XCTAssertFalse(overlay.popoverIsOpen, "a second click on the raised eraser opened the pop-over")
        XCTAssertTrue(overlay.isErasing, "a second click put the eraser down")
        overlay.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertFalse(overlay.popoverIsOpen)
        let items = EditorMenu.items(for: overlay.palette)
        var checked: [String] = []
        var enabled: Bool?
        func walk(_ items: [EditorMenuItem]) {
            for item in items {
                switch item {
                case .tool(let title, _, let isOn, _): if isOn { checked.append(title) }
                case .submenu(let title, let isOn, let children): if isOn { checked.append(title) }; walk(children)
                case .action(let title, _, let isEnabled, _): if title == ScStr.thicknessAndOpacity { enabled = isEnabled }
                case .separator, .reading: break
                }
            }
        }
        walk(items)
        XCTAssertEqual(checked, [], "with the eraser on, the menu checks \(checked)")
        XCTAssertEqual(enabled, false, "Thickness and Opacity… is enabled for the eraser")
        XCTAssertNil(EditorPalette.moreBadge(for: overlay.palette), "⋯ shows a badge while the eraser's object is the raised one")
    }
}
