import AppKit
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The text-reading port of a session whose test reads no text: it answers `.failed`, the one answer that
/// cannot be mistaken for a reading, so a test that did read through it would say so.
struct NoTextReader: ScreenTextReading {
    func read(_ image: CGImage) async -> TextReading { .failed }
}

/// The overlays a controller under test was asked to present and that were built.
@MainActor final class Opened { var overlays: [CaptureOverlay] = [] }

/// What the edge-case files of the area editor share: an overlay over every real screen with an area
/// drawn on the first.
@MainActor
enum OverlayRig {
    /// One blank (or, given a `ground`, filled) 1000×800-point frame at `scale` per real screen, in screen order,
    /// 100 000 points apart.
    static func frames(scale: CGFloat = 1, ground: CGColor? = nil) throws -> [FrozenDisplay] {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = try XCTUnwrap(screen.displayID)
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(1000 * scale), height: Int(800 * scale), bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if let ground { context.setFillColor(ground); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height)) }
            frames.append(FrozenDisplay(id: id, frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: scale, image: try XCTUnwrap(context.makeImage())))
        }
        return frames
    }

    /// A press at `from`, a drag to `to` and a release, on `display`, with no modifier.
    static func drag(_ overlay: CaptureOverlay, on display: DisplayID, from: CGPoint, to: CGPoint) {
        overlay.mouseDown(on: display, at: from, flags: [])
        overlay.mouseDragged(on: display, at: to, flags: [])
        overlay.mouseUp(on: display)
    }

    /// The same drag from the origin of `area` to its far corner.
    static func drag(_ overlay: CaptureOverlay, on display: DisplayID, _ area: CGRect) {
        drag(overlay, on: display, from: area.origin, to: CGPoint(x: area.maxX, y: area.maxY))
    }

    /// An overlay over every real screen, each 1000×800 points at `scale`, an `area` released on the first.
    static func overlay(scale: CGFloat, area: CGRect, textTools: EditorTextTools = .none,
                        onResult: @escaping (OverlayResult) -> Void) throws
        -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let frames = try frames(scale: scale)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil, textTools: textTools, onFinish: onResult)
        XCTAssertTrue(built.build())
        let display = try XCTUnwrap(frames.first?.id)
        drag(built, on: display, area)
        return (built, display, try XCTUnwrap(built.view(for: display)))
    }
}
