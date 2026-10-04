import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **After every edit of a blur the layer on the screen is the mosaic of the box the file will hold.** A blur is moved,
/// pulled by a corner, nudged, given another block, recoloured, undone and redone; after each the overlay is
/// confirmed, and the layer it drew (its frame and its picture, byte for byte) is compared with
/// `Pixelate.tile` of the box it handed over. A layer kept from before the edit shows the old box, or the old block.
/// The order is the other half: a blur drawn after a shape is above it on the screen, as in the file.
@MainActor
final class TheBlurOnTheScreenFollowsEveryEditTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func pattern(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let colour = (UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ 12_345) & 0xFF_FFFF
            bytes[index * 4] = UInt8(colour >> 16)
            bytes[index * 4 + 1] = UInt8(colour >> 8 & 0xFF)
            bytes[index * 4 + 2] = UInt8(colour & 0xFF)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private func build(scale: CGFloat) throws -> (DisplayID, OverlayView, CGImage) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let picture = try pattern(width: Int(1000 * scale), height: Int(800 * scale))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: scale, image: picture)
        results = []
        overlay?.close()
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []),
                                   store: nil) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 700, y: 500), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)), picture)
    }

    private func drag(_ id: DisplayID, from: CGPoint, through: [CGPoint]) {
        overlay?.mouseDown(on: id, at: from, flags: [])
        for point in through { overlay?.mouseDragged(on: id, at: point, flags: []) }
        overlay?.mouseUp(on: id)
    }

    /// The picture a blur layer shows must be the tile of the box the engine holds, at the place the layer sits.
    private func assertTheLayerIsTheTile(_ view: OverlayView, scale: CGFloat, picture: CGImage, _ name: String) throws {
        let shape = try XCTUnwrap(view.drawnShapes.last, "\(name): no layer")
        let shown = try XCTUnwrap(shape.contents, "\(name): the layer holds no picture")
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.last, let layer = layers.last(where: { $0.tool == .blur }) else {
            return XCTFail("\(name): no blur was handed over: \(results)")
        }
        let tile = try XCTUnwrap(Pixelate.tile(of: picture, rect: layer.frame, blockPoints: layer.blockPoints, scale: scale), name)
        XCTAssertEqual(try bytes(shown as! CGImage), try bytes(tile.image), "\(name): the screen shows another mosaic than the file will hold")
        XCTAssertEqual(shape.frame.minX, tile.pixels.minX / scale, accuracy: 0.001, "\(name): x")
        XCTAssertEqual(shape.frame.width, tile.pixels.width / scale, accuracy: 0.001, "\(name): width")
        XCTAssertEqual(shape.frame.minY, view.bounds.height - tile.pixels.maxY / scale, accuracy: 0.001, "\(name): y")
        XCTAssertEqual(shape.frame.height, tile.pixels.height / scale, accuracy: 0.001, "\(name): height")
    }

    func testTheLayerOnTheScreenFollowsMoveResizeNudgeThicknessRecolourUndoAndRedo() throws {
        typealias Step = (DisplayID, CaptureOverlay) -> Void
        let steps: [(String, [Step])] = [
            ("drawn", []),
            ("moved", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: [])
                o.mouseDragged(on: id, at: CGPoint(x: 247, y: 213), flags: []); o.mouseDragged(on: id, at: CGPoint(x: 263.4, y: 229.7), flags: [])
                o.mouseUp(on: id) }]),
            ("pulled", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: [])
                o.mouseUp(on: id)
                o.mouseDown(on: id, at: CGPoint(x: 300, y: 250), flags: []); o.mouseDragged(on: id, at: CGPoint(x: 421.3, y: 330.6), flags: [])
                o.mouseUp(on: id) }]),
            ("nudged", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: []); o.mouseUp(on: id)
                o.keyDown(self.key(124)); o.keyDown(self.key(125)); o.keyDown(self.key(124, flags: .shift)) }]),
            ("thicker", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: []); o.mouseUp(on: id)
                o.perform(.thickness(.thick)) }]),
            ("thinner", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: []); o.mouseUp(on: id)
                o.perform(.thickness(.thin)) }]),
            ("recoloured", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: []); o.mouseUp(on: id)
                o.perform(.color(.blue)) }]),
            ("moved, undone", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: [])
                o.mouseDragged(on: id, at: CGPoint(x: 263.4, y: 229.7), flags: []); o.mouseUp(on: id)
                o.keyDown(self.key(6, "z", flags: .command)) }]),
            ("moved, undone, redone", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: [])
                o.mouseDragged(on: id, at: CGPoint(x: 263.4, y: 229.7), flags: []); o.mouseUp(on: id)
                o.keyDown(self.key(6, "z", flags: .command)); o.keyDown(self.key(6, "z", flags: [.command, .shift])) }]),
            ("thicker, undone", [{ id, o in o.mouseDown(on: id, at: CGPoint(x: 220, y: 200), flags: []); o.mouseUp(on: id)
                o.perform(.thickness(.thick)); o.keyDown(self.key(6, "z", flags: .command)) }]),
        ]
        var seen: [String: (CGRect, [UInt8])] = [:]
        for scale: CGFloat in [1, 2] {
            for (name, edits) in steps {
                let (id, view, picture) = try build(scale: scale)
                overlay?.perform(.tool(.blur))
                drag(id, from: CGPoint(x: 150.4, y: 150.7), through: [CGPoint(x: 300.2, y: 250.9)])
                overlay?.perform(.tool(.blur)) // the tool is put down
                for edit in edits { if let overlay { edit(id, overlay) } }
                XCTAssertEqual(view.drawnShapes.count, 1, "\(scale)x \(name)")
                try assertTheLayerIsTheTile(view, scale: scale, picture: picture, "\(scale)x \(name)")
                let shape = try XCTUnwrap(view.drawnShapes.last)
                seen["\(scale) \(name)"] = (shape.frame, try bytes(shape.contents as! CGImage))
            }
            // The subject: each edit changed what is on the screen, and an undo put the drawn one back.
            let drawn = try XCTUnwrap(seen["\(scale) drawn"])
            for name in ["moved", "pulled", "nudged", "thicker", "thinner"] {
                let edited = try XCTUnwrap(seen["\(scale) \(name)"])
                XCTAssertTrue(edited.0 != drawn.0 || edited.1 != drawn.1, "\(scale)x \(name): the edit changed nothing on the screen")
            }
            XCTAssertEqual(try XCTUnwrap(seen["\(scale) recoloured"]).0, drawn.0)
            XCTAssertEqual(try XCTUnwrap(seen["\(scale) recoloured"]).1, drawn.1, "a recolour changed a blur's picture")
            for name in ["moved, undone", "thicker, undone"] {
                XCTAssertEqual(try XCTUnwrap(seen["\(scale) \(name)"]).1, drawn.1, "\(name): the undo left the other block on the screen")
            }
            let moved = try XCTUnwrap(seen["\(scale) moved"]), redone = try XCTUnwrap(seen["\(scale) moved, undone, redone"])
            XCTAssertEqual(redone.0, moved.0, "redo did not put the moved box back")
        }
    }

    func testABlurDrawnAfterAShapeIsAboveItOnTheScreen() throws {
        let (id, view, _) = try build(scale: 1)
        overlay?.perform(.tool(.rectangle))
        drag(id, from: CGPoint(x: 150, y: 200), through: [CGPoint(x: 450, y: 230)])
        overlay?.perform(.tool(.rectangle))
        overlay?.perform(.tool(.blur))
        drag(id, from: CGPoint(x: 200, y: 150), through: [CGPoint(x: 300, y: 300)])
        overlay?.perform(.tool(.blur))
        XCTAssertEqual(view.drawnShapes.count, 2)
        let order = view.drawnShapes.compactMap { shape in view.layer?.sublayers?.firstIndex(where: { $0 === shape }) }
        XCTAssertEqual(order.count, 2, "a layer is not in the view's tree")
        XCTAssertEqual(order, order.sorted(), "the screen draws the layers in another order than the file")
        XCTAssertTrue(view.drawnShapes[0] is CAShapeLayer && !(view.drawnShapes[1] is CAShapeLayer), "the order of the layers is not the order drawn")
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.last else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.map(\.tool), [.rectangle, .blur])
    }
}
