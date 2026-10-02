import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The overlay draws one plate by the pointer, and its digits sit in the middle
/// of it.** Before a drag the plate says where the pointer is; while one is open
/// it says how large the selection is, in the same place, and the coordinates
/// are gone — two plates at one offset lay one over the other and the darker
/// showed the lighter through it. The plate is the height of its digits and not
/// of its line, because a digit has no descender and a line-high plate left them
/// near the top edge.
///
/// A view is built over a synthetic frame and never ordered in: nothing here
/// reaches a screen.
@MainActor
final class ThePlatesSayOneThingByThePointerTests: XCTestCase {

    private func view() throws -> OverlayView {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frame = FrozenDisplay(id: DisplayID(0xDEAD_BEEF), frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                  scale: 2, image: try XCTUnwrap(context.makeImage()))
        let overlay = CaptureOverlay(freeze: Freeze(displays: [.image(frame)], windows: [])) { _ in }
        return OverlayView(frozen: frame, overlay: overlay)
    }

    func testBeforeADragTheOnePlateIsTheCoordinates() throws {
        let view = try view()
        var scene = OverlayScene()
        scene.pointer = CGPoint(x: 300, y: 200)
        view.apply(scene)
        XCTAssertEqual(view.visiblePlates.map(\.string), ["300, 200"])
    }

    func testWhileADragIsOpenTheSizeReplacesTheCoordinatesAndFollowsThePointer() throws {
        let view = try view()
        var scene = OverlayScene()
        scene.pointer = CGPoint(x: 700, y: 520)
        scene.selection = CGRect(x: 100, y: 100, width: 600, height: 420)
        view.apply(scene)
        let plates = view.visiblePlates
        XCTAssertEqual(plates.map(\.string), ["1200 × 840"], "one plate, and it is the size")
        let plate = try XCTUnwrap(plates.first)
        // The pointer in this view's own layers is at y = 600 - 520.
        let pointer = CGPoint(x: 700, y: 80)
        XCTAssertLessThan(abs(plate.frame.midX - pointer.x), 80, "the plate is not by the pointer: \(plate.frame)")
        XCTAssertLessThan(abs(plate.frame.midY - pointer.y), 60, "the plate is not by the pointer: \(plate.frame)")
    }

    /// Dragging up and to the left puts the selection's far corner on the other
    /// side of the screen from the pointer; the plate stays with the pointer.
    func testAnUpLeftDragKeepsThePlateWithThePointer() throws {
        let view = try view()
        var scene = OverlayScene()
        scene.pointer = CGPoint(x: 100, y: 100)
        scene.selection = CGRect(x: 100, y: 100, width: 600, height: 420)
        view.apply(scene)
        let plate = try XCTUnwrap(view.visiblePlates.first)
        XCTAssertLessThan(abs(plate.frame.midX - 100), 90, "\(plate.frame)")
    }

    func testNoPointerAndNoSelectionDrawNoPlate() throws {
        let view = try view()
        view.apply(OverlayScene())
        XCTAssertTrue(view.visiblePlates.isEmpty)
    }

    /// Rendered and measured, because a frame says nothing about where CoreText
    /// put the digits inside it: the lit rows of the plate, top gap against
    /// bottom gap.
    func testTheDigitsSitInTheMiddleOfThePlate() throws {
        let view = try view()
        var scene = OverlayScene()
        // The size plate, whose text has no comma: a comma hangs below the baseline
        // and would count as the bottom of the digits.
        scene.pointer = CGPoint(x: 300, y: 200)
        scene.selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        view.apply(scene)
        let plate = try XCTUnwrap(view.visiblePlates.first)
        XCTAssertEqual(plate.string, "400 × 200")
        let scale = 4
        let width = Int(plate.bounds.width) * scale, height = Int(plate.bounds.height) * scale
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        plate.render(in: context)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var lit: [Int] = []
        for row in 0..<height {
            let isLit = (0..<width).contains { column in
                let at = (row * width + column) * 4
                return pixels[at] > 200 && pixels[at + 1] > 200 && pixels[at + 2] > 200 && pixels[at + 3] > 200
            }
            if isLit { lit.append(row) }
        }
        let first = try XCTUnwrap(lit.first, "no digit was drawn into the plate")
        let last = try XCTUnwrap(lit.last)
        let above = Double(first) / Double(scale), below = Double(height - 1 - last) / Double(scale)
        XCTAssertLessThanOrEqual(abs(above - below), 1.0,
                                 "the digits are \(above) pt from the top edge and \(below) pt from the bottom")
    }
}
