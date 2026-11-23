import CoreGraphics
import Foundation

/// The blur tool's picture: a mosaic of the pixels under a box, computed from the bytes.
///
/// **A mosaic and not a blur.** Every pixel of a block is replaced by the mean of that block's two or more pixels;
/// no block is of one pixel. The mean is rounded, so it can equal one of the block's pixels. It is taken
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
/// pixel, which would be that pixel verbatim. A box narrower than half a block in an axis is one block in it. A box
/// that clips to a single pixel **grows by one neighbouring pixel inside the display** (`grown`), the right one, else
/// the left, else below, else above, so its block is the mean of two and is not that pixel alone; on a display of one
/// pixel there is no neighbour and the tile is nil, which the export refuses and does not draw the pixel verbatim.
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

    /// An 8-bit RGBA bitmap `width` × `height` in `space`; `alpha` is the site's own, `bytesPerRow` 0 when the system may choose.
    static func bitmap(width: Int, height: Int, bytesPerRow: Int = 0, space: CGColorSpace,
                       alpha: CGImageAlphaInfo = .premultipliedLast) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: space, bitmapInfo: alpha.rawValue)
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
        guard let pixels = ScreenSpace.outward(minX: rect.minX * scale, minY: rect.minY * scale,
                                               maxX: rect.maxX * scale, maxY: rect.maxY * scale, width: width, height: height),
              pixels.width * pixels.height < 1e9 else { return nil }
        return pixels
    }

    /// `part` as it is, or, when it is a single pixel, with one neighbouring pixel inside a `width` × `height` display
    /// added; nil for a single pixel on a display of one pixel, which has no neighbour.
    static func grown(_ part: CGRect, width: Int, height: Int) -> CGRect? {
        guard part.width == 1, part.height == 1 else { return part }
        if width >= 2 { return CGRect(x: part.maxX < CGFloat(width) ? part.minX : part.minX - 1, y: part.minY, width: 2, height: 1) }
        if height >= 2 { return CGRect(x: part.minX, y: part.maxY < CGFloat(height) ? part.minY : part.minY - 1, width: 1, height: 2) }
        return nil
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
    /// the box has no pixel on the display, the display has only one pixel under a box of one, or the bitmap cannot be made.
    /// A box of a single pixel is grown first (`grown`), here and so for the screen and the file alike.
    public static func tile(of display: CGImage, rect: CGRect, blockPoints: CGFloat, scale: CGFloat) -> Tile? {
        guard let clipped = pixels(of: rect, scale: scale, width: display.width, height: display.height),
              let part = grown(clipped, width: display.width, height: display.height),
              let cut = display.cropping(to: part) else { return nil }
        let side = block(points: blockPoints, scale: scale)
        let w = cut.width, h = cut.height, left = Int(part.minX), top = Int(part.minY)
        for space in spaces(for: display) {
            guard let context = bitmap(width: w, height: h, bytesPerRow: w * 4, space: space),
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
                    guard count > 1 else { return nil }  // never reached: `grown` leaves no block of one
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

extension CGContext {
    /// Display-local points (top-left) to the pixels of a bitmap `height` high (bottom-left) that starts at `origin` in the
    /// display's pixels, `scale` pixels to a point: the export's own transform.
    func mapDisplayPoints(toBitmapOfHeight height: Int, scale: CGFloat, origin: CGPoint) {
        translateBy(x: 0, y: CGFloat(height))
        scaleBy(x: scale, y: -scale)
        translateBy(x: -origin.x / scale, y: -origin.y / scale)
    }
}
