import CoreGraphics
import Foundation

/// The magnifier tool's picture: a circle that shows the frozen picture under it twice as large, with a ring in the layer's ink,
/// drawn by the one function the screen and the export both call, so the lens in the file is the lens the screen showed.
///
/// **It magnifies the frame and not the layers above it**, as the blur's mosaic is made of the display's pixels and of nothing
/// else (`Pixelate`): a mark or a blur under the lens is not seen through it, and a layer over the lens is drawn over it. The
/// magnification is one for every lens (`factor`); the circle's square is the layer's `frame` and the picture is magnified about its
/// centre, so what is in the middle of the lens stays there.
///
/// **A picture of whole display pixels.** `tile` draws the lens into a bitmap of the display's own pixels (in the colour space of the
/// display's picture, as the mosaic is made); the overlay lays it as a layer's contents and the export draws it on the pixels of the cut,
/// the two the same bytes. The ring lies inside the circle, its outer edge the circle's.
public enum Magnifier {
    /// How many times larger the picture under the lens is shown.
    public static let factor: CGFloat = 2
    /// The smallest circle a drag or a resize keeps, in points: under it the lens shows a few pixels and the ring is all there is.
    public static let minimumDiameter: CGFloat = 8

    /// The lens in `context`, whose user space is the display's top-left points: the part of `display` (the frozen picture, `scale`
    /// pixels to a point) round the circle's centre, magnified, clipped to the circle, and the ring over it. Nothing is drawn for another tool.
    public static func draw(_ annotation: Annotation, over display: CGImage, scale: CGFloat, in context: CGContext) {
        guard annotation.tool == .magnifier, scale.isFinite, scale > 0 else { return }
        let circle = annotation.frame
        let centre = CGPoint(x: circle.midX, y: circle.midY)
        // The part of the picture the lens shows, and where its pixels land once magnified about the centre.
        let shown = circle.insetBy(dx: circle.width * (1 - 1 / factor) / 2, dy: circle.height * (1 - 1 / factor) / 2)
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        if let part = Pixelate.pixels(of: shown, scale: scale, width: display.width, height: display.height),
           let cut = display.cropping(to: part) {
            let from = CGRect(x: part.minX / scale, y: part.minY / scale, width: part.width / scale, height: part.height / scale)
            let into = CGRect(x: centre.x + (from.minX - centre.x) * factor, y: centre.y + (from.minY - centre.y) * factor,
                              width: from.width * factor, height: from.height * factor)
            context.interpolationQuality = .high
            // A picture drawn in a top-left space is upside down: stand it on its bottom edge.
            context.translateBy(x: into.minX, y: into.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cut, in: CGRect(origin: .zero, size: into.size))
        }
        context.restoreGState()
        let width = annotation.style.thickness.points(for: .magnifier)
        context.saveGState()
        context.setShouldAntialias(true)
        context.setStrokeColor(annotation.fillColor)
        context.setLineWidth(width)
        context.strokeEllipse(in: circle.insetBy(dx: width / 2, dy: width / 2))
        context.restoreGState()
    }

    /// The lens as a picture of whole display pixels, as `AnnotationText.tile(of:scale:)` makes the text's; nil for another tool, a layer
    /// with nothing to draw, or a picture that would be absurdly large.
    public static func tile(of annotation: Annotation, over display: CGImage, scale: CGFloat) -> Pixelate.Tile? {
        guard annotation.tool == .magnifier, annotation.isUsable else { return nil }
        for space in Pixelate.spaces(for: display) {
            if let tile = AnnotationText.tile(covering: annotation.frame, scale: scale, space: space,
                                              drawing: { draw(annotation, over: display, scale: scale, in: $0) }) { return tile }
        }
        return nil
    }
}
