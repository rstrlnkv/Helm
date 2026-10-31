import AppKit
import QuartzCore
import HelmUI
import Module_Screenshots_Engine

/// A small text plate: white digits on a dark rounded ground, sized to its text.
///
/// **A plate and a text layer inside it, not one text layer.** A `CATextLayer`
/// draws its line from the top of its frame, and a digit has no descender: a
/// plate as tall as the line plus a margin left the digits three points from the
/// top edge and seven and a half from the bottom. The plate is sized to the
/// digits' own height and the line is placed so that they sit in the middle.
final class LabelLayer: CALayer {
    private let text = CATextLayer()

    /// The type ladder's own small size, with digits that keep their width so the
    /// plate does not shimmer while a number changes under the pointer.
    private static var plateFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: HelmText.rowDetailNSFont.pointSize, weight: .medium)
    }

    override init() {
        super.init()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        backgroundColor = OverlayInk.plate
        cornerRadius = 4
        contentsScale = scale
        text.font = Self.plateFont
        text.fontSize = Self.plateFont.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = scale
        addSublayer(text)
    }
    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    var string: String? { text.string as? String }

    /// The plate's size for a string: what `show` lays out, for a caller that places it by its height.
    static func size(of string: String) -> CGSize {
        let font = plateFont
        let measured = (string as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(measured.width) + 14, height: ceil(font.capHeight + 10))
    }

    /// Where the area's size plate stands, as a top-left origin in display points: 14 right of the area's top-left
    /// corner and 12 above it. Where that is not clear of every handle target of `area` once the display's edge has
    /// pushed it in (an area against the top wall, or too narrow to leave the top handle alone), or overlaps one of
    /// `clearOf` (the palette, in the same points), the first of under the area, inside its corner, right of it and
    /// left of it that is clear. With none clear the first place is kept: a plate is never left out.
    static func cornerPlace(of size: CGSize, over area: CGRect, within bounds: CGRect,
                            clearOf others: [CGRect] = []) -> CGPoint {
        let margin: CGFloat = 4
        let candidates = [CGPoint(x: area.minX + 14, y: area.minY - 12 - size.height),
                          CGPoint(x: area.minX + 14, y: area.maxY + 12),
                          CGPoint(x: area.minX + 14, y: area.minY + 14),
                          CGPoint(x: area.maxX + 14, y: area.minY),
                          CGPoint(x: area.minX - 14 - size.width, y: area.minY)].map { origin in
            CGPoint(x: min(max(origin.x, bounds.minX + margin), bounds.maxX - size.width - margin),
                    y: min(max(origin.y, bounds.minY + margin), bounds.maxY - size.height - margin))
        }
        let reach = AreaFrame.reach(on: area)
        return candidates.first { origin in
            let plate = CGRect(origin: origin, size: size)
            return !others.contains { $0.intersects(plate) } && AreaFrame.offered(on: area).allSatisfy { handle in
                hypot(handle.point.x - min(max(handle.point.x, plate.minX), plate.maxX),
                      handle.point.y - min(max(handle.point.y, plate.minY), plate.maxY)) > reach
            }
        } ?? candidates[0]
    }

    func show(_ string: String, near point: CGPoint, within bounds: CGRect) {
        text.string = string
        let font = Self.plateFont
        let line = ceil((string as NSString).size(withAttributes: [.font: font]).height)
        let size = Self.size(of: string)
        // The digits' top edge is `ascender - capHeight` under the line's top
        // and their foot is the baseline, `ascender` under it; the gap above
        // them and below them is the same `(height - capHeight) / 2`.
        let margin = (size.height - font.capHeight) / 2
        text.frame = CGRect(x: 7, y: size.height - margin + (font.ascender - font.capHeight) - line,
                            width: size.width - 14, height: line)
        var origin = point
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)
        frame = CGRect(origin: origin, size: size)
        isHidden = false
    }
}
