import AppKit
import HelmContract
import HelmTestSupport
import QuartzCore
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// What a test needs to hold the overlay's layers against the file made from the same annotations: an overlay over the
/// first real screen at a scale, a picture under it, the composite a `CARenderer` makes of the view's layers over that picture,
/// and the picture's pixels read back. Shared by the tests that put the screen's pixels next to the file's.
@MainActor
enum ScreenAndFile {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    struct Rig {
        let overlay: CaptureOverlay
        let display: DisplayID
        let view: OverlayView
        let ground: CGImage
        let points: CGSize
        let scale: CGFloat
        let results: ResultBox
    }

    final class ResultBox { var all: [OverlayResult] = [] }

    /// The first screen's size in points, a uniform grey picture of it at `scale`, and an overlay over it whose area is the
    /// screen less 50 points each side, released.
    static func rig(scale: CGFloat) throws -> Rig {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (pw, ph) = (Int(screen.frame.width), Int(screen.frame.height))
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(CGFloat(pw) * scale), height: Int(CGFloat(ph) * scale), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pw) * scale, height: CGFloat(ph) * scale))
        let ground = try XCTUnwrap(context.makeImage())
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: pw, height: ph), scale: scale, image: ground)
        let box = ResultBox()
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []),
                                   store: nil) { box.all.append($0) }
        XCTAssertTrue(built.build())
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: pw - 50, y: ph - 50), flags: [])
        built.mouseUp(on: id)
        return Rig(overlay: built, display: id, view: try XCTUnwrap(built.view(for: id)), ground: ground,
                   points: CGSize(width: pw, height: ph), scale: scale, results: box)
    }

    /// A drag from `from` to `to` with whatever tool is chosen.
    static func drag(_ rig: Rig, from: CGPoint, to: CGPoint) {
        rig.overlay.mouseDown(on: rig.display, at: from, flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: to, flags: [])
        rig.overlay.mouseUp(on: rig.display)
    }

    /// A click, a press and a release at one point.
    static func click(_ rig: Rig, at point: CGPoint) {
        rig.overlay.mouseDown(on: rig.display, at: point, flags: [])
        rig.overlay.mouseUp(on: rig.display)
    }

    /// The bytes of `image` as sRGB, four to a pixel.
    static func rgb(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    /// The view's own layers over the picture: the dim of the spotlights, then the annotations' layers, as the view stacks them.
    /// Taken out of the view: the rig is not used for another composite after this.
    static func composite(_ rig: Rig) -> CALayer {
        let (w, h) = (Int(rig.points.width * rig.scale), Int(rig.points.height * rig.scale))
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        root.anchorPoint = .zero
        root.position = .zero
        root.sublayerTransform = CATransform3DMakeScale(rig.scale, rig.scale, 1)
        let under = CALayer()
        under.frame = CGRect(x: 0, y: 0, width: rig.points.width, height: rig.points.height)
        under.contents = rig.ground
        under.contentsScale = rig.scale
        under.magnificationFilter = .nearest
        root.addSublayer(under)
        let dim = rig.view.drawnSpotlightDim
        root.addSublayer(dim)
        for shape in rig.view.drawnShapes { root.addSublayer(shape) }
        return root
    }

    /// The exit with `.confirm`, and the layers it handed over.
    static func confirmed(_ rig: Rig) throws -> [Annotation] {
        rig.results.all = []
        rig.overlay.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = rig.results.all.last else {
            XCTFail("nothing was handed over: \(rig.results.all)")
            return []
        }
        return layers
    }

    /// The file made of `layers` from the area's cut of the picture (the area is the screen less 50 points each side).
    static func file(of layers: [Annotation], _ rig: Rig) throws -> CGImage {
        let cut = CGRect(x: 50 * rig.scale, y: 50 * rig.scale, width: (rig.points.width - 100) * rig.scale,
                         height: (rig.points.height - 100) * rig.scale)
        let part = try XCTUnwrap(rig.ground.cropping(to: cut))
        return try XCTUnwrap(CaptureSession.draw(layers, over: part, at: cut.origin, scale: rig.scale, display: rig.ground))
    }
}
