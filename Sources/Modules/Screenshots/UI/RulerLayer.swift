import AppKit
import HelmUI
import Module_Screenshots_Engine

/// The ruler as the overlay draws it: a translucent strip with ticks along its lower edge and, on it, the angle as a number
/// in a dark pill. One layer for the view, above the annotations and under the palette; it clips to the area, since the
/// ruler is a guide on the picture and not a thing the picture has, and it is **drawn here and nowhere else**: the export
/// (`CaptureSession.draw`) is never given a ruler.
///
/// The strip is built once per length and then only moved and turned: the overlay applies a scene on every pointer event.
final class RulerLayer: CALayer {
    /// The strip, its ticks and its pill, in the strip's own points with the origin at its lower left.
    private let strip = CALayer()
    private let body = CAShapeLayer()
    private let ticks = CAShapeLayer()
    private let pill = CAShapeLayer()
    private let label = CATextLayer()
    private let clip = CAShapeLayer()
    private var builtLength: CGFloat?
    private var shownText: String?

    private static var font: NSFont { NSFont.systemFont(ofSize: 10, weight: .semibold) }

    override init() {
        super.init()
        mask = clip
        // The strip: white at half, a hairline of black at 28 %, ticks every 10 pt, every fifth one longer.
        body.fillColor = NSColor.white.withAlphaComponent(0.5).cgColor
        body.strokeColor = NSColor.black.withAlphaComponent(0.28).cgColor
        body.lineWidth = 0.8
        ticks.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        ticks.lineWidth = 0.8
        pill.fillColor = NSColor.black.withAlphaComponent(0.6).cgColor
        label.font = Self.font
        label.fontSize = Self.font.pointSize
        label.foregroundColor = NSColor.white.cgColor
        label.alignmentMode = .center
        for sublayer in [body, ticks, pill, label] as [CALayer] { strip.addSublayer(sublayer) }
        addSublayer(strip)
    }

    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The angle as a number with its degree sign, whole degrees, spelt as the app's language spells a number.
    /// A format style holds no cache, so a language changed between two captures is read at once; and a rounding that
    /// lands on nothing is zero, never a minus zero.
    static func text(degrees: CGFloat) -> String {
        let locale = Locale(identifier: AppLanguage.current.rawValue)
        let whole = Double(degrees.rounded()) + 0
        return Measurement(value: whole, unit: UnitAngle.degrees)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// Draws `ruler` in `area`, both in the display's top-left points on a view `height` points tall (this layer's own
    /// coordinates have the origin below), or nothing.
    func show(_ ruler: Ruler?, in area: CGRect, height: CGFloat, scale: CGFloat) {
        guard let ruler else { isHidden = true; return }
        isHidden = false
        clip.path = CGPath(rect: CGRect(x: area.minX, y: height - area.maxY, width: area.width, height: area.height), transform: nil)
        let width = Ruler.width
        if builtLength != ruler.length {
            builtLength = ruler.length
            // The pill sits in the middle of the strip, so a new length moves it even at the same angle.
            shownText = nil
            strip.bounds = CGRect(x: 0, y: 0, width: ruler.length, height: width)
            body.path = CGPath(roundedRect: strip.bounds, cornerWidth: 3, cornerHeight: 3, transform: nil)
            let marks = CGMutablePath()
            for step in 0...Int(ruler.length / 10) {
                marks.move(to: CGPoint(x: CGFloat(step) * 10, y: 0))
                marks.addLine(to: CGPoint(x: CGFloat(step) * 10, y: step % 5 == 0 ? 9 : 5))
            }
            ticks.path = marks
        }
        let text = Self.text(degrees: ruler.angle)
        if shownText != text {
            shownText = text
            label.string = text
            let wide = max(28, ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 14)
            pill.path = CGPath(roundedRect: CGRect(x: (ruler.length - wide) / 2, y: (width - 14) / 2, width: wide, height: 14),
                               cornerWidth: 7, cornerHeight: 7, transform: nil)
            label.frame = CGRect(x: (ruler.length - wide) / 2, y: (width - 14) / 2 + 0.5, width: wide, height: 13)
        }
        for sublayer in [body, ticks, pill, label] as [CALayer] { sublayer.contentsScale = scale }
        label.contentsScale = scale
        // The angle is clockwise on the screen, which in these coordinates, origin below, is the other way round.
        strip.position = CGPoint(x: ruler.center.x, y: height - ruler.center.y)
        strip.transform = CATransform3DMakeRotation(-ruler.angle * .pi / 180, 0, 0, 1)
    }
}
