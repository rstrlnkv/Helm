import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import QuartzCore
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The box round the selected object leaves with the selection, and never hides a thin object.** Read
/// off the composited pixels: the box's edge is not the object's colour while the object is selected and is
/// exactly it (or the picture) once it is not, by every way a selection ends; and on a hairline and a
/// freehand stroke the colour of the object is what shows at the box's centre.
@MainActor
final class TheSelectionFrameComesAndGoesWithTheSelectionTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private struct Rig {
        let overlay: CaptureOverlay, id: DisplayID, view: OverlayView, w: Int, h: Int, box: CGRect
        @MainActor func read(_ points: [CGPoint]) throws -> [[UInt8]] {
            let root = try XCTUnwrap(view.layer)
            _ = try CompositedPixels.read(root, width: w, height: h, at: points)
            return try CompositedPixels.read(root, width: w, height: h, at: points)
        }
        var edge: CGPoint { CGPoint(x: box.minX, y: box.midY) }
        var centre: CGPoint { CGPoint(x: box.midX, y: box.midY) }
    }

    private func rig(scale: CGFloat = 1) throws -> Rig {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: scale,
                                   image: try CompositedPixels.halfBlackPicture(width: w, height: h))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)], windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        let view = try XCTUnwrap(built.view(for: id))
        view.appearance = NSAppearance(named: .aqua)
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: w - 50, y: h - 50), flags: [])
        built.mouseUp(on: id)
        return Rig(overlay: built, id: id, view: view, w: w, h: h,
                   box: CGRect(x: w / 2 - 100, y: h / 2 - 80, width: 200, height: 160))
    }

    private func drag(_ r: Rig, _ points: [CGPoint]) {
        r.overlay.mouseDown(on: r.id, at: points[0], flags: [])
        for p in points.dropFirst() { r.overlay.mouseDragged(on: r.id, at: p, flags: []) }
        r.overlay.mouseUp(on: r.id)
    }

    /// A red filled rectangle, put down and selected.
    private func selectedRectangle(_ r: Rig) {
        r.overlay.perform(.color(.red)); r.overlay.perform(.toggleFill); r.overlay.perform(.tool(.rectangle))
        drag(r, [CGPoint(x: r.box.minX, y: r.box.minY), CGPoint(x: r.box.maxX, y: r.box.maxY)])
        r.overlay.perform(.tool(.rectangle))
        r.overlay.mouseDown(on: r.id, at: r.centre, flags: [])
        r.overlay.mouseUp(on: r.id)
    }

    private func close(_ a: [UInt8], _ b: [UInt8], _ message: String) {
        for (x, y) in zip(a, b) { XCTAssertEqual(Int(x), Int(y), accuracy: 6, message) }
    }

    func testTheFrameLeavesWithTheSelectionByEveryDoorAndTheSubjectWasThere() throws {
        let red = AnnotationColor.red.cgColor.components!.map { UInt8(($0 * 255).rounded()) }
        let doors: [(String, (Rig) -> Void, [UInt8])] = [
            ("Esc", { $0.overlay.rightMouseDown() }, red),
            ("a click on empty", { $0.overlay.mouseDown(on: $0.id, at: CGPoint(x: 80, y: 80), flags: []); $0.overlay.mouseUp(on: $0.id) }, red),
            ("delete", { $0.overlay.perform(.delete) }, [0, 0, 0]),
            ("undo", { $0.overlay.perform(.undo) }, [0, 0, 0]),
        ]
        for (name, leave, after) in doors {
            overlay?.close()
            let r = try rig()
            selectedRectangle(r)
            XCTAssertEqual(r.view.drawnHandles.count, 4, "\(name): nothing was selected")
            let during = try r.read([r.edge])[0]
            XCTAssertTrue(zip(during, red).contains { abs(Int($0) - Int($1)) > 6 }, "\(name): the frame is not on the edge while selected, \(during)")
            leave(r)
            XCTAssertEqual(r.view.drawnHandles.count, 0, "\(name): handles outlived the selection")
            close(try r.read([r.edge])[0], after, "\(name): a frame outline is still drawn on the edge")
        }
    }

    func testAThinLineAndAFreehandStrokeShowTheirColourAtTheBoxCentre() throws {
        for tool in [AnnotationTool.line, .pencil] {
            overlay?.close()
            let r = try rig()
            r.overlay.perform(.color(.red)); r.overlay.perform(.thickness(.thin)); r.overlay.perform(.tool(tool))
            let steps = (0...10).map { i in
                CGPoint(x: r.box.minX + 20 * CGFloat(i), y: r.box.minY + 16 * CGFloat(i)) }
            drag(r, tool == .line ? [steps[0], steps[10]] : steps)
            r.overlay.perform(.tool(tool))
            r.overlay.mouseDown(on: r.id, at: r.centre, flags: [])
            r.overlay.mouseUp(on: r.id)
            XCTAssertEqual(r.view.drawnShapes.count, 1, "\(tool): nothing was drawn")
            XCTAssertFalse(r.view.drawnHandles.isEmpty, "\(tool): nothing was selected")
            // The stroke is 3 points wide through the centre; the 3x3 around it is all the object.
            let around = (-1...1).flatMap { dx in (-1...1).map { dy in CGPoint(x: r.centre.x + CGFloat(dx), y: r.centre.y + CGFloat(dy)) } }
            let seen = try r.read(around)
            let reddish = seen.filter { $0[0] > 200 && $0[1] < 60 && $0[2] < 60 }.count
            XCTAssertGreaterThanOrEqual(reddish, 3, "\(tool): the object's colour is not visible at the box centre: \(seen)")
        }
    }
}
