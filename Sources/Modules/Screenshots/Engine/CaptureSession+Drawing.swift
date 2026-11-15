import CoreGraphics
import Foundation
import ImageIO

extension CaptureSession {
    /// The pool is inside the call, as in `encode`: a 5K cut is one iteration of the caller's work.
    /// `display` is the whole picture the cut is part of, the cut at `origin` in it: a blur's blocks sit on the
    /// display's pixels and a box that reaches past the cut still averages what is there, so the file holds the
    /// blocks the screen drew.
    static func draw(_ layers: [Annotation], over cut: CGImage, at origin: CGPoint, scale: CGFloat,
                     display: CGImage) -> CGImage? {
        autoreleasepool {
            for space in Pixelate.spaces(for: cut) {
                guard let context = CGContext(data: nil, width: cut.width, height: cut.height,
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                context.draw(cut, in: CGRect(x: 0, y: 0, width: cut.width, height: cut.height))
                context.setAllowsAntialiasing(true)
                // The spotlights' one dim, under every other layer: a spotlight is no layer of its own here and draws nothing below.
                context.saveGState()
                context.translateBy(x: 0, y: CGFloat(cut.height))
                context.scaleBy(x: scale, y: -scale)
                context.translateBy(x: -origin.x / scale, y: -origin.y / scale)
                Spotlights.draw(layers, within: CGRect(x: origin.x / scale, y: origin.y / scale,
                                                       width: CGFloat(cut.width) / scale, height: CGFloat(cut.height) / scale),
                                in: context)
                context.restoreGState()
                for (layer, number) in zip(layers, AnnotationStep.numbers(in: layers)) {
                    if layer.tool == .spotlight { continue }
                    if layer.tool == .blur {
                        // Opaque whole pixels on the bitmap's own grid: nothing of the picture shows at an edge.
                        // A box with no pixel on the display is skipped; a box that has pixels and
                        // got no tile (the bitmap could not be made) makes `draw` return nil, so no file is written with that box undrawn.
                        guard Pixelate.pixels(of: layer.frame, scale: scale, width: display.width, height: display.height) != nil
                        else { continue }
                        guard let tile = Pixelate.tile(of: display, rect: layer.frame, blockPoints: layer.blockPoints, scale: scale)
                        else { return nil }
                        place(tile, in: context, cutHeight: cut.height, origin: origin)
                        continue
                    }
                    if layer.tool == .magnifier {
                        // The lens is a picture of the display's pixels like the mosaic; one with nothing to show is drawn as the screen draws it: not at all.
                        if let tile = Magnifier.tile(of: layer, over: display, scale: scale) {
                            place(tile, in: context, cutHeight: cut.height, origin: origin)
                        }
                        continue
                    }
                    context.saveGState()
                    // The pencil's grain is a clip in the bitmap's own pixels, so it goes in before the points' transform.
                    if layer.tool.isGrainy, let stroke = layer.stroke {
                        let cutPixels = CGRect(origin: origin, size: CGSize(width: cut.width, height: cut.height))
                        guard let grain = PencilGrain.mask(for: layer.points, width: stroke.width, scale: scale, pixels: cutPixels)
                        else { context.restoreGState(); continue }
                        context.clip(to: CGRect(x: grain.pixels.minX - origin.x,
                                                y: CGFloat(cut.height) - (grain.pixels.maxY - origin.y),
                                                width: grain.pixels.width, height: grain.pixels.height), mask: grain.grey)
                    }
                    // Display-local points, top-left, to this bitmap's pixels, bottom-left.
                    context.translateBy(x: 0, y: CGFloat(cut.height))
                    context.scaleBy(x: scale, y: -scale)
                    context.translateBy(x: -origin.x / scale, y: -origin.y / scale)
                    if layer.tool == .text || layer.tool == .emoji {
                        AnnotationText.draw(layer, in: context)
                        context.restoreGState()
                        continue
                    }
                    if let number {
                        AnnotationStep.draw(layer, number: number, in: context)
                        context.restoreGState()
                        continue
                    }
                    context.addPath(layer.outline)
                    if let stroke = layer.stroke {
                        context.setLineWidth(stroke.width)
                        context.setLineCap(stroke.cap)
                        context.setLineJoin(stroke.join)
                        context.setStrokeColor(stroke.color)
                        if stroke.multiplies { context.setBlendMode(.multiply) }
                        context.strokePath()
                    } else {
                        context.setFillColor(layer.fillColor)
                        context.fillPath()
                    }
                    context.restoreGState()
                }
                return context.makeImage()
            }
            return nil
        }
    }

    /// A picture of whole pixels of the display (`Pixelate.Tile`) drawn into the cut's bitmap, which starts at `origin` in the display's pixels: one pixel
    /// to one, on the bitmap's own grid, so nothing is resampled. A mosaic's tile is opaque; a lens's is transparent outside its circle.
    private static func place(_ tile: Pixelate.Tile, in context: CGContext, cutHeight: Int, origin: CGPoint) {
        context.saveGState()
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.draw(tile.image, in: CGRect(x: tile.pixels.minX - origin.x, y: CGFloat(cutHeight) - (tile.pixels.maxY - origin.y),
                                            width: tile.pixels.width, height: tile.pixels.height))
        context.restoreGState()
    }

    /// The picture as a PNG or a JPEG, or nil when ImageIO would not make one. The
    /// pool is inside the call: encoding a 5K frame leaves autoreleased buffers,
    /// and the work is one iteration of whoever called.
    ///
    /// **A JPEG is drawn onto an opaque ground first,** so the ground is Helm's
    /// choice and not whatever ImageIO makes of an alpha channel it is about to
    /// drop. (On the macOS this was written on, ImageIO alone also lands on
    /// white — a clear picture and a half-transparent one both came out right
    /// with the flattening taken out — so this pins the ground rather than
    /// repairing a defect that was seen.)
    public static func encode(_ image: CGImage, as format: ShotFormat) -> Data? {
        autoreleasepool {
            let source: CGImage
            switch format {
            case .png: source = image
            case .jpeg:
                guard let flat = flattened(image) else { return nil }
                source = flat
            }
            let data = NSMutableData()
            let type = format == .png ? "public.png" : "public.jpeg"
            guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)
            else { return nil }
            let options: CFDictionary? = format == .jpeg
                ? [kCGImageDestinationLossyCompressionQuality: ShotFormat.jpegQuality] as CFDictionary
                : nil
            CGImageDestinationAddImage(destination, source, options)
            guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
            return data as Data
        }
    }

    /// The picture over `jpegGround`, in its own colour space when that is an RGB
    /// one an 8-bit bitmap can be made in, sRGB otherwise — an extended-range
    /// space (a display's HDR or wide-gamut reading) cannot hold one, and a PNG
    /// of the same picture is fine, so the JPEG falls back rather than refuses.
    static func flattened(_ image: CGImage) -> CGImage? {
        for space in Pixelate.spaces(for: image) {
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { continue }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(jpegGround)
            context.fill(rect)
            context.draw(image, in: rect)
            return context.makeImage()
        }
        return nil
    }
}
