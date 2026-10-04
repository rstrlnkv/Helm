import CoreGraphics
import CoreText
import Foundation

/// The steps tool's picture: a circle in the layer's ink with its number in it, drawn by the one function the screen and the
/// export both call, so a step stands in the file where the screen showed it.
///
/// **The number is stored nowhere.** It is the layer's place among the step layers of the list (`numbers`), so removing the
/// second of three leaves one and two, and undo brings back one, two and three, with no code that renumbers: whoever draws
/// asks the list it is drawing. A drawn layer that holds a number is stale as soon as another step goes before it, so a cache of
/// them keeps the number it was built with beside the layer.
///
/// **The digit.** The system font, bold, set by CoreText at 0.6 of the circle's diameter (12 pt in a 20 pt circle), centred on the
/// circle by the ink of its glyphs and not by the line's room. The count goes on past 99 and the font shrinks instead: a number
/// wider than 0.8 of the diameter is set smaller until it is, so three digits and more stay inside the circle and the count is
/// never cut. Two digits are set at the full size from 10 on in every circle but for 99 in the 16 and 20 pt ones, which is a little smaller
/// (`digitSize(of:diameter:)`, measured by `TheStepsAreNumberedByTheirOrderTests`); the 20 pt circle shows 10 at 12 pt. Its colour is the one of the two, white or black, that reads on the ink (`digitColor(on:)`).
public enum AnnotationStep {
    /// The digit's size as a share of the circle's diameter, and the widest share of the diameter the number may take.
    static let digitShare: CGFloat = 0.6
    static let widestShare: CGFloat = 0.8
    /// The weight trait of the digit's bold.
    static let bold: CGFloat = 0.4

    /// The square the circle is in: centred on where the step was placed, as wide as the thickness step says.
    static func frame(of annotation: Annotation) -> CGRect {
        let diameter = annotation.style.thickness.points(for: .step)
        return CGRect(x: annotation.start.x - diameter / 2, y: annotation.start.y - diameter / 2, width: diameter, height: diameter)
    }

    /// The number of each layer in `layers`, in the list's order: 1, 2, 3 for the step layers as they stand, nil for any other
    /// layer. The one place a number is decided.
    public static func numbers(in layers: [Annotation]) -> [Int?] {
        var count = 0
        return layers.map { layer in
            guard layer.tool == .step else { return nil }
            count += 1
            return count
        }
    }

    /// White on an ink whose luma (the Rec. 709 weights on the sRGB values) is under 0.55, black on a lighter one: white on the
    /// red, blue, purple and black, black on the orange, yellow, green and white.
    public static func digitColor(on ink: AnnotationInk) -> CGColor {
        let parts = ink.cgColor.components ?? [0, 0, 0, 1]
        let luma = 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]
        return luma < 0.55 ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    }

    /// The digits of `number` in the font at `size`.
    private static func line(of number: Int, size: CGFloat, color: CGColor) -> CTLine {
        let attributes: [CFString: Any] = [kCTFontAttributeName: AnnotationText.font(size: size, weight: bold),
                                           kCTForegroundColorAttributeName: color]
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, String(number) as CFString, attributes as CFDictionary))
    }

    /// The font size the number is set at in a circle of `diameter`: `digitShare` of it, or smaller where the number set so would be wider than
    /// `widestShare`. The one place the size is decided, which the drawing and a test both ask.
    static func digitSize(of number: Int, diameter: CGFloat) -> CGFloat {
        let size = diameter * digitShare
        let width = CTLineGetTypographicBounds(line(of: number, size: size, color: CGColor(gray: 0, alpha: 1)), nil, nil, nil)
        return width > diameter * widestShare ? size * diameter * widestShare / width : size
    }

    /// The step in `context`, whose user space is the display's top-left points, as number `number`: the circle in the ink,
    /// the opacity in it, and the digit over it. Nothing is drawn for another tool.
    public static func draw(_ annotation: Annotation, number: Int, in context: CGContext) {
        guard annotation.tool == .step else { return }
        let box = frame(of: annotation)
        let ink = digitColor(on: annotation.style.ink(for: .step))
        let digit = ink.copy(alpha: CGFloat(annotation.style.opacity)) ?? ink
        let line = line(of: number, size: digitSize(of: number, diameter: box.width), color: digit)
        // The glyphs' own box, not the line's room: a digit has no descender, so the room's middle sits low.
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.setShouldAntialias(true)
        context.setFillColor(annotation.fillColor)
        context.fillEllipse(in: box)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: box.midX - glyphs.midX, y: box.midY + glyphs.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The step as a picture of whole display pixels, as `AnnotationText.tile(of:scale:)` makes the text's.
    public static func tile(of annotation: Annotation, number: Int, scale: CGFloat) -> Pixelate.Tile? {
        guard annotation.tool == .step, annotation.isUsable else { return nil }
        return AnnotationText.tile(covering: frame(of: annotation), scale: scale) { draw(annotation, number: number, in: $0) }
    }
}
