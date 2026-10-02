import AppKit
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The overlay refuses to build when the freeze does not carry a frame for every real screen, so a fixture
/// that builds one frame passes on a one-display Mac and is red on a three-display one.
/// `blankFrames(besides:)` is the rest of the desk: one blank frame per other real screen, far from the first.
@MainActor
enum TheOtherScreens {
    static func blankFrames(besides id: DisplayID) -> [DisplayShot] {
        var frames: [DisplayShot] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  DisplayID(number) != id,
                  let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage() else { continue }
            frames.append(.image(FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 100_000 * CGFloat(index + 1), y: 0, width: 10, height: 10),
                                               scale: 1, image: image)))
        }
        return frames
    }
}

/// What the edge-case files of the area editor share: an overlay over every real screen with an area
/// drawn on the first, and one object drawn and selected in it.
@MainActor
enum OverlayRig {
    /// One blank 1000×800-point frame at `scale` per real screen, in screen order, 100 000 points apart.
    static func frames(scale: CGFloat = 1) throws -> [FrozenDisplay] {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(1000 * scale), height: Int(800 * scale), bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: scale, image: try XCTUnwrap(context.makeImage())))
        }
        return frames
    }

    /// An overlay over every real screen, each 1000×800 points at `scale`, an `area` released on the first.
    /// `pinRoom` is the answer the overlay is given to "may another pin open" (task 12).
    static func overlay(scale: CGFloat, area: CGRect, pinRoom: @escaping () -> Bool = { true },
                        onResult: @escaping (OverlayResult) -> Void) throws
        -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let frames = try frames(scale: scale)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil, pinRoom: pinRoom, onFinish: onResult)
        XCTAssertTrue(built.build())
        let display = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: display, at: area.origin, flags: [])
        built.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: display)
        return (built, display, try XCTUnwrap(built.view(for: display)))
    }

    /// One rectangle (200,200)-(300,260) drawn and selected by a click on its left edge.
    static func drawAndSelect(in overlay: CaptureOverlay?, on display: DisplayID) {
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.mouseUp(on: display)
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.mouseUp(on: display)
    }
}
