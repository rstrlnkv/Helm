import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **What nobody fed the edits of an object on the picture:** the delete key with a modifier, held and
/// with nothing under it; the hit tolerance on a display of two pixels to the point; and the shape
/// layers the view holds, counted, through delete, undo, redo and recolour.
@MainActor
final class TheEditorsEditsMeetInputsNobodyPlannedTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func build(scale: CGFloat = 1) throws -> (DisplayID, OverlayView) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(1000 * scale), height: Int(800 * scale), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: scale,
                                   image: try XCTUnwrap(context.makeImage()))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)], windows: []), store: nil) { [weak self] in
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
        overlay?.perform(.tool(tool))
    }

    private func shapeLayers(_ view: OverlayView) -> Int {
        let all = (view.layer?.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        return all.count
    }

    // MARK: Keys

    func testTheDeleteKeyMeansDeleteOnlyBareAndAModifiedOneMeansNothing() {
        for code in [UInt16(51), 117] {
            XCTAssertEqual(EditorKeys.action(keyCode: code, flags: []), .delete)
            XCTAssertEqual(EditorKeys.action(keyCode: code, flags: [.function]), .delete, "fn+⌫ is the laptop's ⌦")
            XCTAssertEqual(EditorKeys.action(keyCode: code, flags: [.numericPad]), .delete)
            XCTAssertNil(EditorKeys.action(keyCode: code, flags: .command), "⌘⌫ must not delete a layer")
            XCTAssertNil(EditorKeys.action(keyCode: code, flags: .option))
            XCTAssertNil(EditorKeys.action(keyCode: code, flags: .control))
            XCTAssertNil(EditorKeys.action(keyCode: code, flags: .shift))
        }
    }

    func testAHeldDeleteKeyTakesTheSelectedOnceAndNotItsNeighbours() throws {
        let (id, view) = try build()
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
        draw(id, .line, from: CGPoint(x: 150, y: 380), to: CGPoint(x: 400, y: 380))
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        for _ in 0..<8 { overlay?.perform(.delete, isRepeat: true) }
        XCTAssertEqual(view.drawnShapes.count, 2, "a held ⌫ went on deleting past the selected object")
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnShapes.count, 3, "the held key made more than one step")
    }

    // MARK: Points, not pixels

    func testTheHitToleranceIsInPointsOnATwoXDisplay() throws {
        for scale in [CGFloat(1), 2] {
            let (id, view) = try build(scale: scale)
            draw(id, .line, from: CGPoint(x: 150, y: 300), to: CGPoint(x: 400, y: 300))
            // A thin line is 3 pt wide: 1.5 + 4 reaches 5.5 pt off the axis, whatever the pixels are.
            drag(id, from: CGPoint(x: 250, y: 305), through: [])
            XCTAssertEqual(view.drawnHandles.count, 2, "scale \(scale): 5 pt off the line did not select")
            drag(id, from: CGPoint(x: 250, y: 350), through: [])
            drag(id, from: CGPoint(x: 250, y: 306.5), through: [])
            XCTAssertTrue(view.drawnHandles.isEmpty, "scale \(scale): 6.5 pt off the line selected")
            overlay?.close()
        }
    }

    // MARK: No orphan shape layer

    func testTheViewHoldsExactlyTheShapeLayersOfTheListThroughEveryEdit() throws {
        let (id, view) = try build()
        let base = shapeLayers(view)
        func check(_ message: String, expecting count: Int, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(view.drawnShapes.count, count, message, file: file, line: line)
            XCTAssertEqual(shapeLayers(view) - base, count, "\(message): the view holds a shape layer the list does not", file: file, line: line)
        }
        draw(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        draw(id, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 400, y: 350))
        draw(id, .pencil, from: CGPoint(x: 350, y: 150), to: CGPoint(x: 450, y: 250))
        check("three drawn", expecting: 3)
        drag(id, from: CGPoint(x: 220, y: 150), through: [])
        for _ in 0..<3 {
            overlay?.perform(.color(.blue)); overlay?.perform(.color(.green))
            check("recoloured", expecting: 3)
            overlay?.perform(.delete)
            check("deleted", expecting: 2)
            overlay?.perform(.undo)
            check("undone", expecting: 3)
            overlay?.perform(.redo)
            check("redone", expecting: 2)
            overlay?.perform(.undo); overlay?.perform(.undo); overlay?.perform(.undo)
            check("undone to the start of the edits", expecting: 3)
            overlay?.perform(.redo); overlay?.perform(.redo); overlay?.perform(.redo)
            overlay?.perform(.undo)
            drag(id, from: CGPoint(x: 220, y: 150), through: [])
        }
        drag(id, from: CGPoint(x: 220, y: 150), through: [CGPoint(x: 240, y: 170), CGPoint(x: 260, y: 190)])
        for _ in 0..<50 { overlay?.perform(.undo) } // more than the session has steps
        check("everything undone", expecting: 0)
    }
}
