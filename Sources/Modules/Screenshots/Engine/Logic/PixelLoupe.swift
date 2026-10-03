import CoreGraphics

/// Nine by nine pixels of the frozen display around a point, and the colour of the middle one.
///
/// **Read from `FrozenDisplay.image`, the frame without the pointer**, so what the loupe shows is what
/// the person sees under the overlay and never the pointer drawn into a `withCursor` frame. It reads a
/// colour; nothing here magnifies, the layer that shows the pixels does.
///
/// **The colour is sRGB.** A display's frame is in the display's own space (Display P3 on the built-in
/// ones), and a hex taken from its raw bytes would differ from what a colour meter reads off the same
/// pixel, so the pixels are drawn into an sRGB bitmap and read there.
///
/// **Edges are clamped, not shrunk:** a point within four pixels of a side repeats the last row or column,
/// so the picture is always nine by nine and its middle is always the pixel under the point.
public struct PixelLoupe: @unchecked Sendable {
    public static let side = 9

    /// The nine by nine pixels in sRGB, for a layer to magnify without smoothing.
    public let image: CGImage
    /// The pixel under the point, in the frame's own pixels, top-left origin.
    public let pixel: (x: Int, y: Int)
    /// The middle pixel's colour, 0...255 a channel.
    public let centre: (red: UInt8, green: UInt8, blue: UInt8)

    /// `#RRGGBB`, upper case: the form a design tool and the system's colour meter both print.
    public var hex: String {
        String(format: "#%02X%02X%02X", centre.red, centre.green, centre.blue)
    }

    /// The loupe at `point`, in `display`'s own top-left points; nil for a point that is no number or a
    /// frame with no pixels.
    public static func around(_ point: CGPoint, in display: FrozenDisplay) -> PixelLoupe? {
        let frame = display.image
        guard point.x.isFinite, point.y.isFinite, display.scale > 0, display.scale.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        // Clamped as doubles before the conversion: a huge point is not an Int that traps.
        let px = Int(min(max((point.x * display.scale).rounded(.down), 0), CGFloat(frame.width - 1)))
        let py = Int(min(max((point.y * display.scale).rounded(.down), 0), CGFloat(frame.height - 1)))
        let half = side / 2
        let columns = (0..<side).map { min(max(px - half + $0, 0), frame.width - 1) }
        let rows = (0..<side).map { min(max(py - half + $0, 0), frame.height - 1) }
        guard let lowX = columns.min(), let highX = columns.max(), let lowY = rows.min(), let highY = rows.max(),
              let box = frame.cropping(to: CGRect(x: lowX, y: lowY, width: highX - lowX + 1, height: highY - lowY + 1)),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let source = CGContext(data: nil, width: box.width, height: box.height, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: srgb,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let target = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        source.interpolationQuality = .none
        source.draw(box, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
        guard let from = source.data?.assumingMemoryBound(to: UInt8.self),
              let to = target.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // Memory rows run from the top, as the frame's own do.
        for (row, y) in rows.enumerated() {
            for (column, x) in columns.enumerated() {
                let at = (y - lowY) * source.bytesPerRow + (x - lowX) * 4
                let into = row * target.bytesPerRow + column * 4
                for channel in 0..<4 { to[into + channel] = from[at + channel] }
            }
        }
        guard let image = target.makeImage() else { return nil }
        let middle = half * target.bytesPerRow + half * 4
        let alpha = Int(to[middle + 3])
        // A frame is opaque; a clear pixel is read as the black under it rather than divided by nothing.
        func plain(_ channel: UInt8) -> UInt8 { alpha == 0 ? 0 : UInt8(min(255, Int(channel) * 255 / alpha)) }
        return PixelLoupe(image: image, pixel: (px, py),
                          centre: (plain(to[middle]), plain(to[middle + 1]), plain(to[middle + 2])))
    }
}
