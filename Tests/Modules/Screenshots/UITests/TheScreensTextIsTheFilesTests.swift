import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The text on the screen stands on the pixels of the text in the file.** The engine's test holds the tile against the
/// file; this one types the texts into the overlay's own field, in each of the three steps and in Latin, Cyrillic,
/// Japanese and with an emoji, at 1× and at 2×, composites the layers the overlay drew over the picture through a
/// `CARenderer` (the texture the window server composites), exports the same layers through `CaptureSession`, and
/// compares every pixel of every text's box.
///
/// What it would print if it failed totally: a layer with no picture is the picture itself and the file's ink is
/// counted against it; a text laid a pixel off, or upside down, differs along every glyph's edge.
@MainActor
final class TheScreensTextIsTheFilesTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private func picture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.82, green: 0.86, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: width / 3, y: 0, width: width / 5, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func rgb(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testTheLayersOnTheScreenAndTheFileHoldTheSamePixels() throws {
        let screen0 = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (pw, ph) = (Int(screen0.frame.width), Int(screen0.frame.height))
        let texts = ["Hello, Helm 123", "Привет, мир 456", "日本語のテキスト", "Ship it 🚢🎉 ok"]
        let columns = (pw - 160) / texts.count
        for scale in [CGFloat(1), 2] {
            let (w, h) = (Int(CGFloat(pw) * scale), Int(CGFloat(ph) * scale))
            let ground = try picture(width: w, height: h)
            let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: pw, height: ph), scale: scale, image: ground)
            results = []
            overlay?.close()
            let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []),
                                       store: nil) { [weak self] in self?.results.append($0) }
            XCTAssertTrue(built.build())
            overlay = built
            built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: CGFloat(pw) - 50, y: CGFloat(ph) - 50), flags: [])
            built.mouseUp(on: id)
            let view = try XCTUnwrap(built.view(for: id))
            built.perform(.tool(.text))
            built.perform(.color(.blue))
            built.perform(.opacity(0.85))
            // Four texts across and the three steps down, each typed into the field and ended with Return.
            for (row, step) in AnnotationThickness.allCases.enumerated() {
                built.perform(.thickness(step))
                for (column, text) in texts.enumerated() {
                    built.mouseDown(on: id, at: CGPoint(x: 80.3 + CGFloat(column * columns), y: 90.6 + CGFloat(row * 60)), flags: [])
                    built.mouseUp(on: id)
                    let field = try XCTUnwrap(view.textField, "\(scale)x \(step) \(text): no field")
                    field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                    field.keyDown(with: key(36))
                }
            }
            XCTAssertEqual(view.drawnShapes.count, 12, "\(scale)x: the texts were not all drawn, so the pixels below say nothing")
            for shape in view.drawnShapes { XCTAssertNotNil(shape.contents, "\(scale)x: a text's layer holds no picture") }

            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            root.anchorPoint = .zero
            root.position = .zero
            root.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
            let under = CALayer()
            under.frame = CGRect(x: 0, y: 0, width: pw, height: ph)
            under.contents = ground
            under.contentsScale = scale
            under.magnificationFilter = .nearest
            root.addSublayer(under)
            for shape in view.drawnShapes { root.addSublayer(shape) }

            built.perform(.exit(.confirm))
            guard case .edited(_, _, let layers, _)? = results.last else { return XCTFail("\(scale)x: nothing was handed over: \(results)") }
            XCTAssertEqual(layers.count, 12)
            XCTAssertEqual(Set(layers.compactMap(\.text)), Set(texts), "the texts were not handed over with their words")
            let file = try rgb(try XCTUnwrap(CaptureSession.draw(layers, over: ground, at: .zero, scale: scale, display: ground)))
            let was = try rgb(ground)

            var probes: [(x: Int, y: Int)] = []
            var inked = 0
            for layer in layers {
                let tile = try XCTUnwrap(AnnotationText.tile(of: layer, scale: scale), "\(scale)x: \(layer.text ?? "")")
                let box = tile.pixels.intersection(CGRect(x: 0, y: 0, width: w, height: h))
                var own = 0
                for y in Int(box.minY)..<Int(box.maxY) {
                    for x in Int(box.minX)..<Int(box.maxX) {
                        probes.append((x, y))
                        let at = (y * w + x) * 4
                        if (0..<3).contains(where: { file[at + $0] != was[at + $0] }) { own += 1 }
                    }
                }
                XCTAssertGreaterThan(own, 40, "\(scale)x \(layer.text ?? ""): the file shows no ink in the text's box")
                inked += own
            }
            // The renderer's texture is bottom-up: the picture's row is `h - 1 - row`.
            let read = try CompositedPixels.read(root, width: w, height: h, at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
            var off = 0, worst = 0
            for (probe, got) in zip(probes, read) {
                let at = (probe.y * w + probe.x) * 4
                var gap = 0
                for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(file[at + channel]))) }
                worst = max(worst, gap)
                if gap > 3 { off += 1 }
            }
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(probes.count) pixels differ between the screen and the file, the worst by \(worst)")
            XCTAssertGreaterThan(inked, 12 * 40)
        }
    }
}
