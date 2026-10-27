import AppKit
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The text-reading port of a session whose test reads no text: it answers `.failed`, the one answer that
/// cannot be mistaken for a reading, so a test that did read through it would say so.
struct NoTextReader: ScreenTextReading {
    func read(_ image: CGImage) async -> TextReading { .failed }
}

/// What the edge-case files of the area editor share: an overlay over every real screen with an area
/// drawn on the first.
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
    static func overlay(scale: CGFloat, area: CGRect, textTools: EditorTextTools = .none,
                        onResult: @escaping (OverlayResult) -> Void) throws
        -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let frames = try frames(scale: scale)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil, textTools: textTools, onFinish: onResult)
        XCTAssertTrue(built.build())
        let display = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: display, at: area.origin, flags: [])
        built.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: display)
        return (built, display, try XCTUnwrap(built.view(for: display)))
    }
}
