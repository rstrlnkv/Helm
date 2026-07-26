import AppKit
import XCTest
import Module_Layout_Engine
@testable import Module_Layout_UI

/// Every drawn flag keeps its rounded corners.
///
/// The trap: `drawn(_:points:scale:)` sets the rounded-rect clip with
/// `setClip()`, and `setClip()` *replaces* the clip rather than intersecting
/// it. Any construction that later calls `setClip()` again — the Union Jack
/// clips to its own rectangle, the taegeuk to its disc — throws the corner
/// rounding away for everything it paints afterwards. GB paints its field
/// square into all four corners; AU paints the canton square into the
/// top-left one. Every other flag rounds, so the two stand out in the menu
/// bar as the badges with different corners — the one thing an indicator
/// family must not do.
///
/// The existing opacity test samples the *middle* column, where every flag is
/// opaque by design, so it cannot see this. These read the corners.
final class BadgeCornerTests: XCTestCase {

    /// Renders at a fixed scale and reads the raw pixels, in device pixels.
    private func pixels(_ art: FlagArt, points: CGFloat, scale: CGFloat = 2)
    -> (rep: NSBitmapImageRep, width: Int, height: Int) {
        let image = BadgeImage.drawn(art, points: points, scale: scale)
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return (rep, width, height)
    }

    /// The corner radius is at least 2 px at every size, so the exact corner
    /// pixel lies outside the rounded rectangle for every badge: transparent,
    /// or at most the faint tail of antialiasing.
    func testEveryFlagKeepsItsRoundedCorners() {
        for points in [CGFloat(11), 13, 18] {
            for region in FlagArt.drawnRegions {
                guard let art = FlagArt.flag(region: region) else { continue }
                let (rep, width, height) = pixels(art, points: points)
                for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1),
                               (width - 1, height - 1)] {
                    let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    XCTAssertLessThan(alpha, 0.5,
                                      "\(region) at \(points) pt paints its corner at "
                                      + "(\(x), \(y)) — the rounding clip was replaced, "
                                      + "not intersected")
                }
            }
        }
    }
}
