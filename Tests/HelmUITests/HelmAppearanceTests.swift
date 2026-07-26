import AppKit
import SwiftUI
import XCTest
@testable import HelmUI

/// A dynamic colour baked into a bitmap is whatever the appearance was when
/// the bitmap was made — and inside a SwiftUI body, nothing sets that. The
/// menu-bar shape and size pickers came out white on a light window, which is
/// a control drawn in a colour nobody chose.
final class HelmAppearanceTests: XCTestCase {

    private func labelPixel(_ scheme: ColorScheme) -> NSColor? {
        let image = HelmAppearance.drawing(scheme) { () -> NSImage in
            let img = NSImage(size: NSSize(width: 8, height: 8))
            img.lockFocus()
            NSColor.labelColor.setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            img.unlockFocus()
            return img
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB)
    }

    func testTheSameDynamicColourBakesDifferentlyPerAppearance() throws {
        let light = try XCTUnwrap(labelPixel(.light))
        let dark = try XCTUnwrap(labelPixel(.dark))
        // Light: a near-black label. Dark: near-white. Without the appearance
        // block both would be whatever happened to be current, and match.
        XCTAssertLessThan(light.brightnessComponent, 0.5, "light appearance did not apply")
        XCTAssertGreaterThan(dark.brightnessComponent, 0.5, "dark appearance did not apply")
    }

    /// The lazy case: an image whose pixels are produced by a drawing handler
    /// long after any appearance block would have returned.
    func testRasterizePinsALazilyDrawnImage() throws {
        let lazyImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.labelColor.setFill()
            rect.fill()
            return true
        }
        for (scheme, wantDark) in [(ColorScheme.light, true), (ColorScheme.dark, false)] {
            let baked = HelmAppearance.rasterize(lazyImage, scheme: scheme)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(baked.tiffRepresentation)))
            let pixel = try XCTUnwrap(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB))
            if wantDark {
                XCTAssertLessThan(pixel.brightnessComponent, 0.5, "light: the label should be dark")
            } else {
                XCTAssertGreaterThan(pixel.brightnessComponent, 0.5, "dark: the label should be light")
            }
        }
    }
}
