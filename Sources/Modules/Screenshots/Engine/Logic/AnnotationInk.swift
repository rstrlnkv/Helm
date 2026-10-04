import CoreGraphics
import HelmRuntime

/// An ink: three sRGB numbers, 0…1, and no alpha (the opacity is the style's). The eight swatches are eight of
/// these (`AnnotationColor` names them), and any other colour — one of the system's colour panel, one read off
/// a pixel — is one more, so the style, the screen and the export carry one type for both.
///
/// **Every way in ends at the three numbers clamped to 0…1, and a number that is not a number is no ink**
/// (`init?(red:green:blue:)`), so a stored or a panel's NaN never reaches a layer.
public struct AnnotationInk: Sendable, Hashable {
    public let red: Double, green: Double, blue: Double

    public init?(red: Double, green: Double, blue: Double) {
        guard let red = red.clampedIfFinite(to: 0...1), let green = green.clampedIfFinite(to: 0...1),
              let blue = blue.clampedIfFinite(to: 0...1) else { return nil }
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(_ swatch: AnnotationColor) {
        let parts = swatch.cgColor.components ?? [0, 0, 0, 1]
        red = Double(parts[0])
        green = Double(parts[1])
        blue = Double(parts[2])
    }

    /// The middle pixel of the loupe; it is sRGB already (`PixelLoupe`).
    public init(_ loupe: PixelLoupe) {
        red = Double(loupe.centre.red) / 255
        green = Double(loupe.centre.green) / 255
        blue = Double(loupe.centre.blue) / 255
    }

    /// Any colour, converted to sRGB with its alpha dropped; nil where the conversion has no answer or a number is not one.
    public init?(_ color: CGColor) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return nil }
        self.init(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]))
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// The swatch that has exactly these numbers, which is how the screen tells a picked ink from a swatch's.
    public var swatch: AnnotationColor? { AnnotationColor.allCases.first { AnnotationInk($0) == self } }

    public static let red = AnnotationInk(AnnotationColor.red)
    public static let orange = AnnotationInk(AnnotationColor.orange)
    public static let yellow = AnnotationInk(AnnotationColor.yellow)
    public static let green = AnnotationInk(AnnotationColor.green)
    public static let blue = AnnotationInk(AnnotationColor.blue)
    public static let purple = AnnotationInk(AnnotationColor.purple)
    public static let black = AnnotationInk(AnnotationColor.black)
    public static let white = AnnotationInk(AnnotationColor.white)
}
