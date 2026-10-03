import CoreGraphics
import CoreText
import Foundation

/// The text tool's picture: one line of the system font, laid out by CoreText and drawn by the one function the
/// screen and the export both call, so the text stands in the file where the screen showed it.
///
/// **One line.** A text has no break: a newline that reaches `AnnotationEditing.place` becomes a space. The
/// layout (`size(of:)`) is what the annotation's `frame` is, so a step that changes the font moves the frame with it,
/// and a glyph the system font lacks (Japanese, an emoji) comes from the font CoreText falls back to, inside the same
/// line.
///
/// **Where it is drawn.** `draw` takes a context in the display's top-left points, the geometry the export sets
/// up for every layer, and puts the line's top at `start.y`. Smoothing is switched off and subpixel positions are
/// kept, so the pixels do not depend on the context that carries them. The overlay lays `tile` (the same `draw`
/// into a bitmap of whole display pixels) as the contents of a layer.
public enum AnnotationText {
    /// The most graphemes a text keeps; `AnnotationEditing.place` is the one entry that bounds it.
    public static let maxLength = 256

    /// The most scalars one grapheme keeps (a family emoji is seven): a grapheme of thousands of combining marks is
    /// still one grapheme under `maxLength` and a layout the size of the paste. `place` cuts the excess scalars of a
    /// grapheme and keeps one only if the result stays one grapheme of its own; the field refuses a change that
    /// would leave one with more (`fits`).
    public static let maxScalarsPerGrapheme = 16

    /// Whether `text` is within both bounds, `maxLength` graphemes and `maxScalarsPerGrapheme` scalars to each.
    public static func fits(_ text: String) -> Bool {
        text.count <= maxLength && text.allSatisfy { $0.unicodeScalars.count <= maxScalarsPerGrapheme }
    }

    /// Whether a character is of the kinds that draw nothing: white space, a control, a format character (zero-width
    /// space and joiners, direction marks, the soft hyphen, the byte order mark) or a separator, alone or all together.
    /// A cheap first test; a character outside these kinds can still be blank (a filler), and `hasInk` is the judge.
    public static func isInvisible(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .unassigned: return true
            default: return scalar.properties.isWhitespace
            }
        }
    }

    /// Whether drawing `text` leaves a pixel of ink: the line is drawn as the layer draws it, in the Large step, into a
    /// bitmap of alpha only, and any pixel not zero is ink. What a person can see decides, not the character's category,
    /// so a filler or a lone variation selector is blank and a joined emoji is not.
    public static func hasInk(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let probe = Annotation(tool: .text, start: .zero, end: .zero, style: .standard, text: text)
        let box = probe.frame.insetBy(dx: -overhang, dy: -overhang)
        let (width, height) = (Int(box.width.rounded(.up)), Int(box.height.rounded(.up)))
        guard width > 0, height > 0, width * height < 100_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data
        else { return false }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -box.minX, y: -box.minY)
        draw(probe, in: context)
        return UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height).contains { $0 != 0 }
    }

    /// The text as one line: a tab or a line break becomes a space. The field and `AnnotationEditing.place` both use it.
    public static func oneLine(_ text: String) -> String {
        String(text.map { $0 == "\t" || $0.isNewline ? " " : $0 })
    }

    /// The room round the line a tile keeps for what a glyph draws past its advance, in points.
    static let overhang: CGFloat = 4

    /// The system font, semibold, at the step's size (`AnnotationThickness.points(for:)`).
    public static func font(for thickness: AnnotationThickness) -> CTFont {
        let size = thickness.points(for: .text)
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let semibold = [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), semibold)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func line(of annotation: Annotation, color: CGColor? = nil) -> CTLine? {
        guard let text = annotation.text, !text.isEmpty else { return nil }
        var attributes: [CFString: Any] = [kCTFontAttributeName: font(for: annotation.style.thickness)]
        if let color { attributes[kCTForegroundColorAttributeName] = color }
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    }

    /// The line's room in points: its advance and its ascent and descent, rounded up; zero for no text.
    public static func size(of annotation: Annotation) -> CGSize {
        guard let line = line(of: annotation) else { return .zero }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return CGSize(width: width.rounded(.up), height: (ascent + descent).rounded(.up))
    }

    /// The text in `context`, whose user space is the display's top-left points; the ink is the annotation's own
    /// (`Annotation.fillColor`, the opacity in it). Nothing is drawn for no text.
    public static func draw(_ annotation: Annotation, in context: CGContext) {
        guard annotation.tool == .text, let line = line(of: annotation, color: annotation.fillColor) else { return }
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)
        context.saveGState()
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: annotation.start.x, y: annotation.start.y + ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The text as a picture of whole display pixels (top-left origin, `pixels`), transparent where there is no ink,
    /// at `scale` pixels to a point; nil when there is no text, the origin is not a number, or the picture would
    /// be absurdly large.
    public static func tile(of annotation: Annotation, scale: CGFloat) -> Pixelate.Tile? {
        guard annotation.isUsable, scale.isFinite, scale > 0 else { return nil }
        let box = annotation.frame.insetBy(dx: -overhang, dy: -overhang)
        let x0 = (box.minX * scale).rounded(.down), y0 = (box.minY * scale).rounded(.down)
        let x1 = (box.maxX * scale).rounded(.up), y1 = (box.maxY * scale).rounded(.up)
        guard x1 > x0, y1 > y0, (x1 - x0) * (y1 - y0) < 1e8 else { return nil }
        let (width, height) = (Int(x1 - x0), Int(y1 - y0))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The export's own transform, display-local points to a bitmap's pixels, bottom-left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -x0 / scale, y: -y0 / scale)
        draw(annotation, in: context)
        guard let image = context.makeImage() else { return nil }
        return Pixelate.Tile(image: image, pixels: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }
}
