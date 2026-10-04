import CoreGraphics
import Foundation

/// The blur tool's picture: a mosaic of the pixels under a box, computed from the bytes.
///
/// **A mosaic and not a blur.** Every pixel of a block is replaced by the mean of that block's two or more pixels;
/// a block of one pixel is never drawn. The mean is rounded, so it can equal one of the block's pixels. It is taken
/// here, from bytes (a downscale is a filter's weighted sum and not the mean), by the one function the screen and
/// the export both call, so neither can show a block the other does not.
///
/// **Where the grid starts.** At the display's own pixel (0, 0), whatever the box: a block is `blockPoints` times
/// the display's scale, rounded to whole pixels and at least one. A box that is moved or pulled out keeps the
/// mosaic of the picture under it and does not shimmer, and the cut of the file, which has its own origin,
/// lands on the same blocks the screen drew.
///
/// **What a partial block averages.** A block the box's edge cuts takes the mean of **its pixels inside the box**
/// and no others, so a strip the edge leaves is the mean of its own picture and not of the picture beside it,
/// which a whole-block mean would pull into the strip. No pixel outside the box is read. A strip narrower than half a block (`edges`) joins its
/// neighbour, in each axis, so a corner the box's edge leaves one pixel past a grid line is not a block of one
/// pixel, which would be that pixel verbatim. A box narrower than half a block in an axis is one block in it; a box
/// of a single pixel has no block of two pixels to be the mean of, and `tile` is nil for it.
///
/// **Whole pixels.** The box is rounded outward to the pixels it touches and clipped to the display, and the tile
/// is opaque: the export draws it with no antialiasing, so there is no half-covered pixel with the picture in it.
public enum Pixelate {
    /// A mosaic and where it sits: `pixels` in the display's pixels, top-left origin, whole numbers.
    public struct Tile {
        public let image: CGImage
        public let pixels: CGRect
    }

    /// The colour spaces an 8-bit bitmap of `image` is made in, first choice first: its own when that is an RGB one
    /// a bitmap can be made in (an extended-range space cannot hold one), sRGB after it.
    static func spaces(for image: CGImage) -> [CGColorSpace] {
        var spaces = [CGColorSpace(name: CGColorSpace.sRGB)!]
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput { spaces.insert(own, at: 0) }
        return spaces
    }

    /// The block's side in pixels: `points` at `scale`, rounded, never under one.
    static func block(points: CGFloat, scale: CGFloat) -> Int {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 1 }
        return max(1, Int((points * scale).rounded()))
    }

    /// The box `rect` (display-local points, top-left) in whole pixels of a `width` × `height` display: rounded
    /// outward and clipped; nil when nothing of it is on the display, it is not finite, or it is too big to hold.
    static func pixels(of rect: CGRect, scale: CGFloat, width: Int, height: Int) -> CGRect? {
        guard scale > 0, scale.isFinite,
              [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite) else { return nil }
        let x0 = max(0, (rect.minX * scale).rounded(.down)), y0 = max(0, (rect.minY * scale).rounded(.down))
        let x1 = min(CGFloat(width), (rect.maxX * scale).rounded(.up)), y1 = min(CGFloat(height), (rect.maxY * scale).rounded(.up))
        guard x1 > x0, y1 > y0, (x1 - x0) * (y1 - y0) < 1e9 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Where a run of `length` pixels that starts at pixel `start` of the display breaks into blocks of `side`: 0, each
    /// grid line inside it, `length`. An end strip narrower than half a block (`side / 2`, rounded up, and never under
    /// two) is joined to its neighbour and so is not a block of a pixel or two.
    static func edges(start: Int, length: Int, side: Int) -> [Int] {
        var edges = [0]
        var line = (start / side + 1) * side - start
        while line < length { edges.append(line); line += side }
        edges.append(length)
        let least = max(2, (side + 1) / 2)
        if edges.count > 2, edges[1] - edges[0] < least { edges.remove(at: 1) }
        if edges.count > 2, edges[edges.count - 1] - edges[edges.count - 2] < least { edges.remove(at: edges.count - 2) }
        return edges
    }

    /// The mosaic of the box `rect` over `display`, `blockPoints` a block at `scale` pixels to a point; nil when
    /// the box has no pixel on the display, it is one pixel (no block of two pixels), or the bitmap cannot be made.
    public static func tile(of display: CGImage, rect: CGRect, blockPoints: CGFloat, scale: CGFloat) -> Tile? {
        guard let part = pixels(of: rect, scale: scale, width: display.width, height: display.height),
              let cut = display.cropping(to: part) else { return nil }
        let side = block(points: blockPoints, scale: scale)
        let w = cut.width, h = cut.height, left = Int(part.minX), top = Int(part.minY)
        for space in spaces(for: display) {
            guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data
            else { continue }
            context.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            let rows = edges(start: top, length: h, side: side), columns = edges(start: left, length: w, side: side)
            for r in 1..<rows.count {
                let y = rows[r - 1], yEnd = rows[r]
                for c in 1..<columns.count {
                    let x = columns[c - 1], xEnd = columns[c]
                    let count = (yEnd - y) * (xEnd - x)
                    guard count > 1 else { return nil }
                    var sum = [0, 0, 0, 0]
                    for row in y..<yEnd {
                        var at = row * w * 4 + x * 4
                        for _ in x..<xEnd {
                            for channel in 0..<4 { sum[channel] += Int(bytes[at + channel]) }
                            at += 4
                        }
                    }
                    let mean = sum.map { UInt8(($0 + count / 2) / count) }
                    for row in y..<yEnd {
                        var at = row * w * 4 + x * 4
                        for _ in x..<xEnd {
                            for channel in 0..<4 { bytes[at + channel] = mean[channel] }
                            at += 4
                        }
                    }
                }
            }
            guard let image = context.makeImage() else { return nil }
            return Tile(image: image, pixels: part)
        }
        return nil
    }
}
