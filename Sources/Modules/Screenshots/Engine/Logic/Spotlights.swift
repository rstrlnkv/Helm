import CoreGraphics

/// The spotlights' one dim: the area, dimmed everywhere no spotlight is, **once**.
///
/// A spotlight is a box held like a rectangle and has no picture of its own: its part is a hole in the dim. The dim is one path,
/// the area and the **union** of the spotlights' outlines (each cut to the area), filled even-odd, so the area is dimmed
/// exactly where no spotlight is. Two spotlights that overlap or touch leave the same dim between them and everywhere else;
/// were each spotlight to dim what the others do not cover, the dim would add up where they meet. The screen lays this one
/// path as one layer under the other layers, and the export fills it before the other layers: both read `dim(of:within:)`,
/// so neither can draw a spotlight of its own. The dim is under every other layer (a mark stays bright inside it and
/// outside), the blur's mosaic included: that is made from the display's own pixels, which the dim has not touched.
///
/// A spotlight is taken by its edge, as a rectangle is, and with no tool also by its inside, below every other layer
/// (`AnnotationHit.selectable`); with the Spotlight tool a press inside is a press on whatever is there, which is how a
/// second spotlight is begun inside the first, and the eraser takes it by its edge.
public enum Spotlights {
    /// How much of black the dim is: 42 %. The area's own surround is dimmed more (`OverlayView`), so the area reads as lit.
    public static let dimAlpha: CGFloat = 0.42
    /// The corner of a spotlight's box, in points, held to half of the shorter side.
    public static let cornerRadius: CGFloat = 10

    /// The dim's colour.
    public static var color: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: dimAlpha) }

    /// The spotlight's box with round corners: the one geometry the dim and a press both read.
    static func outline(of annotation: Annotation) -> CGPath {
        let box = CGRect(x: min(annotation.start.x, annotation.end.x), y: min(annotation.start.y, annotation.end.y),
                         width: abs(annotation.end.x - annotation.start.x), height: abs(annotation.end.y - annotation.start.y))
        let radius = min(cornerRadius, box.width / 2, box.height / 2)
        return CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The dim over `area`, to be filled even-odd; nil when no layer is a spotlight, or none is usable.
    public static func dim(of layers: [Annotation], within area: CGRect) -> CGPath? {
        let holes = layers.filter { $0.tool == .spotlight && $0.isUsable }.map(outline(of:))
        guard var union = holes.first else { return nil }
        for hole in holes.dropFirst() { union = union.union(hole, using: .winding) }
        let path = CGMutablePath()
        path.addRect(area)
        path.addPath(union.intersection(CGPath(rect: area, transform: nil), using: .winding))
        return path
    }

    /// The dim in `context`, whose user space is the display's top-left points; nothing when no layer is a spotlight.
    public static func draw(_ layers: [Annotation], within area: CGRect, in context: CGContext) {
        guard let path = dim(of: layers, within: area) else { return }
        context.saveGState()
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }
}
