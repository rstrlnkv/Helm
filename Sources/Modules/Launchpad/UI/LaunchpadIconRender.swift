import AppKit

/// One icon drawn into one bitmap of exactly the size it will be shown at: what `LaunchpadIcons` asks for off the main thread.
///
/// `NSWorkspace.icon(forFile:)` answers one image holding every size the system has (32 representations for Safari, Calendar and Finder on macOS 27.3: `NSWorkspace.shared.icon(forFile:).representations.count`), and drawing it
/// at a size makes the system render and keep another bitmap inside it, which is what the window did on main for each size a tile, a
/// category quadrant, a folder cell and a cluster asked for. Here the full image is drawn once into a bitmap of the asked pixels and
/// let go, so what stays is the bitmap alone.
enum LaunchpadIconRender {
    /// The bitmap of the app at `path`, `pixels` on a side, or nil when the system gave no image or the bitmap could not be made.
    /// The pool is inside the call: a loop of these (one per icon, on the queue) holds one icon's temporaries at a time, not all of them.
    static func render(path: String, pixels: Int, space: CGColorSpace) -> CGImage? {
        guard pixels > 0, pixels <= 4096 else { return nil }
        return autoreleasepool {
            let icon = NSWorkspace.shared.icon(forFile: path)
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage()
        }
    }
}
