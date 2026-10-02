import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **What moving the annotations into one shape layer each brought with it:** the order they stack in
/// on the screen is the order of the file, undo and redo rebuild the layers without leaving one behind, and the clip is
/// geometry, so it holds on a display of 2x as it does on 1x. Panels are built and never ordered in.
@MainActor
final class TheLayerMoveMeetsInputsNobodyFedItTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
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
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    private func drag(_ id: DisplayID, _ tool: AnnotationTool, from: CGPoint, to: CGPoint) {
        overlay?.perform(.tool(tool))
        overlay?.mouseDown(on: id, at: from, flags: [])
        overlay?.mouseDragged(on: id, at: to, flags: [])
        overlay?.mouseUp(on: id)
    }

    func testTheShapesStackInTheOrderOfTheAnnotationsBelowTheDimAndOnlyTheMarkerMultiplies() throws {
        let (id, view) = try build()
        drag(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        drag(id, .highlighter, from: CGPoint(x: 120, y: 200), to: CGPoint(x: 400, y: 200))
        drag(id, .line, from: CGPoint(x: 150, y: 300), to: CGPoint(x: 400, y: 320))
        XCTAssertEqual(view.drawnShapes.count, 3, "nothing was drawn, so the order below says nothing")
        let sublayers = try XCTUnwrap(view.layer?.sublayers)
        let positions = view.drawnShapes.map { shape in sublayers.firstIndex(where: { $0 === shape }) }
        XCTAssertTrue(positions.allSatisfy { $0 != nil }, "a shape is not in the view's own layer: \(positions)")
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted(), "the shapes are not in the annotations' order")
        let dim = try XCTUnwrap(sublayers.firstIndex(where: { ($0 as? CAShapeLayer)?.fillRule == .evenOdd }))
        XCTAssertTrue(positions.compactMap { $0 }.allSatisfy { $0 < dim }, "a shape stands over the dim")
        XCTAssertEqual(view.drawnShapes.map { $0.compositingFilter != nil }, [false, true, false],
                       "the multiply is on a layer other than the marker's")
    }

    func testUndoAndRedoManyTimesLeaveNoShapeLayerBehind() throws {
        let (id, view) = try build()
        drag(id, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
        drag(id, .highlighter, from: CGPoint(x: 120, y: 200), to: CGPoint(x: 400, y: 200))
        let baseline = try XCTUnwrap(view.layer?.sublayers?.count)
        for _ in 0..<40 {
            overlay?.perform(.undo)
            XCTAssertEqual(view.drawnShapes.count, 1)
            XCTAssertEqual(view.layer?.sublayers?.count, baseline - 1, "an undo left a layer or lost one")
            overlay?.perform(.undo)
            XCTAssertEqual(view.drawnShapes.count, 0)
            overlay?.perform(.redo)
            overlay?.perform(.redo)
            XCTAssertEqual(view.drawnShapes.count, 2)
            XCTAssertEqual(view.layer?.sublayers?.count, baseline, "a redo cycle changed the layer count")
        }
    }

    func testTheClipIsTheSelectionOnADisplayOfTwoTimes() throws {
        for scale in [CGFloat(1), 2] {
            let (id, view) = try build(scale: scale)
            drag(id, .highlighter, from: CGPoint(x: 120, y: 200), to: CGPoint(x: 480, y: 200))
            let shape = try XCTUnwrap(view.drawnShapes.first, "\(scale)x: nothing drawn")
            let path = try XCTUnwrap(shape.path)
            // The selection in the layer's own space is flipped: y from the top 100...400 is the view's height less that.
            let clip = CGRect(x: 100, y: view.bounds.height - 400, width: 400, height: 300)
            XCTAssertTrue(clip.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingBoxOfPath), "\(scale)x: the marker spills over the area: \(path.boundingBoxOfPath)")
            XCTAssertEqual(shape.contentsScale, scale, "\(scale)x: the layer is not at the display's scale")
        }
    }
}
