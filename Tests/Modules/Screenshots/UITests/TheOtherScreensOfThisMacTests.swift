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
