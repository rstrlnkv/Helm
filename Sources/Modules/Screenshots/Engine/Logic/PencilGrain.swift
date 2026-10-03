import CoreGraphics
import Foundation

/// The pencil's grain: which pixels of its stroke take ink and which stay bare.
///
/// **What the grain is derived from.** One integer hash of a pixel's offset from the stroke's anchor, the pixel
/// its first point lands on (`round(point × scale)`). It reads no chance and no clock, and not the stroke's
/// width, the cut's origin or the display: the screen (a whole display at its scale) and the file (a cut of it,
/// in the picture's own pixels) are asked the same question about the same image pixel and give one answer, two
/// exports of a stroke are byte-identical, and a stroke moved by whole pixels carries its grain with it. Moved
/// by a fraction of a pixel it is a different stroke, which nobody sees.
///
/// **How much.** A pixel takes all the ink when the top byte of its hash is under `solid` of 256 (140, about 55 %
/// of pixels); above that its ink falls evenly to a minimum of 3 of 255, so about 45 % of a stroke's body is grey or nearly bare and the
/// mean is about 78 % (arithmetic from the hash being uniform, checked by the tests' bounds). The pen is the other end.
///
/// **How big.** The mask covers only the stroke's bounding box, widened by half the stroke's width and one pixel,
/// and only where it meets `pixels`; one byte a pixel, on screen too (`Mask.alpha` is alpha-only). A stroke still being
/// drawn is the exception: every draft, however short, holds a display-sized mask, built once, since the grain does not follow the path,
/// and it holds it as two rasters (`grey` and `alpha`; `draftGrain` keeps both): 2 × 14.7 MB at 5120 × 2880. The worst case
/// of a finished stroke is one across a whole display: 14.7 MB for a 5120 × 2880 one (arithmetic, not a measurement).
public enum PencilGrain {
    /// Of 256: the top bytes of the hash under this take all the ink.
    static let solid: UInt32 = 140

    /// The grain over part of an image: `grey` is 8-bit, 255 where there is ink and 0 where there is none, its
    /// pixel (x, y) the image's pixel (`pixels.minX + x`, `pixels.minY + y`), top-left origin.
    public struct Mask {
        public let grey: CGImage
        /// Where `grey` sits in the image, in whole pixels.
        public let pixels: CGRect

        /// The same grain over `part` of it, in the image's pixels, with no new hashing: a draft's mask cut to the
        /// stroke it became. nil when `part` is not inside.
        public func cut(to part: CGRect) -> Mask? {
            guard pixels.contains(part),
                  let grey = grey.cropping(to: part.offsetBy(dx: -pixels.minX, dy: -pixels.minY)) else { return nil }
            return Mask(grey: grey, pixels: part)
        }

        /// The same grain as an alpha-only picture, for what takes its mask from alpha (a layer's): 8-bit, one
        /// byte a pixel like `grey`.
        public var alpha: CGImage? {
            guard let context = CGContext(data: nil, width: grey.width, height: grey.height, bitsPerComponent: 8,
                                          bytesPerRow: grey.width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return nil }
            let whole = CGRect(x: 0, y: 0, width: grey.width, height: grey.height)
            context.clip(to: whole, mask: grey)
            context.fill(whole)
            return context.makeImage()
        }
    }

    /// How much ink the pixel at an offset from the anchor takes, 0…255: all of it under `solid`, and above it
    /// less and less, down to 3 of 255, so the grain has grey in it as a pencil's has.
    ///
    /// It takes the offset's two shares, `spread` of the column's and of the row's, so a loop over a mask works
    /// each out once and not once a pixel.
    static func coverage(column: UInt32, row: UInt32) -> UInt8 {
        var h = column ^ row
        h ^= h >> 15
        h = h &* 0x2C1B_3C6D
        h ^= h >> 12
        h = h &* 0x297A_2D39
        h ^= h >> 15
        return ramp[Int(h >> 24)]
    }

    /// One axis's offset from the anchor as its share of the hash.
    static func spread(_ offset: Int, by prime: UInt32) -> UInt32 { UInt32(truncatingIfNeeded: offset) &* prime }

    /// `coverage` by the top byte of the hash: 255 under `solid`, then falling evenly to 3.
    private static let ramp: [UInt8] = (0..<256).map { top in
        UInt32(top) < solid ? 255 : UInt8(255 - (UInt32(top) - solid) * 255 / (256 - solid))
    }

    /// The grain of a stroke through `points` (display-local, top-left, in points) `width` points wide, at
    /// `scale` pixels to a point, over the part of the image `pixels` names; nil when there is nothing to draw
    /// there or a point is not finite.
    public static func mask(for points: [CGPoint], width: CGFloat, scale: CGFloat, pixels: CGRect) -> Mask? {
        guard let first = points.first, let part = box(for: points, width: width, scale: scale, pixels: pixels) else { return nil }
        return build(anchor: first, scale: scale, part: part)
    }

    /// The part of `pixels` a stroke's mask covers: its bounding box widened by half its width and a pixel, in whole
    /// pixels; nil when that is nothing, too big, or a point is not finite.
    public static func box(for points: [CGPoint], width: CGFloat, scale: CGFloat, pixels: CGRect) -> CGRect? {
        guard !points.isEmpty, scale > 0, scale.isFinite, width.isFinite,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let reach = width / 2 + 1 / scale
        let wanted = CGRect(x: ((xs.min()! - reach) * scale).rounded(.down), y: ((ys.min()! - reach) * scale).rounded(.down),
                            width: ((xs.max()! - xs.min()! + 2 * reach) * scale).rounded(.up) + 1,
                            height: ((ys.max()! - ys.min()! + 2 * reach) * scale).rounded(.up) + 1)
        let part = wanted.intersection(pixels)
        guard !part.isNull, part.width >= 1, part.height >= 1, part.width * part.height < 1e9 else { return nil }
        return part
    }

    /// The grain over the whole of `pixels` for a stroke anchored at `anchor`, whatever its path: the grain depends on
    /// the offset from the anchor alone, so a stroke still being drawn takes this once and its shape's path clips it.
    public static func mask(anchoredAt anchor: CGPoint, scale: CGFloat, pixels: CGRect) -> Mask? {
        guard scale > 0, scale.isFinite, anchor.x.isFinite, anchor.y.isFinite,
              pixels.width >= 1, pixels.height >= 1, pixels.width * pixels.height < 1e9 else { return nil }
        return build(anchor: anchor, scale: scale, part: pixels)
    }

    private static func build(anchor: CGPoint, scale: CGFloat, part: CGRect) -> Mask? {
        let ax = Int((anchor.x * scale).rounded()), ay = Int((anchor.y * scale).rounded())
        let left = Int(part.minX), top = Int(part.minY), w = Int(part.width), h = Int(part.height)
        let columns = (0..<w).map { spread(left + $0 - ax, by: 0x9E37_79B1) }
        let bytes = [UInt8](unsafeUninitializedCapacity: w * h) { buffer, count in
            for y in 0..<h {
                let row = spread(top + y - ay, by: 0x85EB_CA6B)
                for x in 0..<w { buffer[y * w + x] = coverage(column: columns[x], row: row) }
            }
            count = w * h
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let grey = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                 space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Mask(grey: grey, pixels: CGRect(x: left, y: top, width: w, height: h))
    }
}
