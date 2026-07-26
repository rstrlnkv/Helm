import AppKit
import Module_Layout_Engine

/// Draws the badge the menu bar shows.
///
/// Every style is one image at the requested point size — the same sizes the
/// app's own icon offers, so the two indicators sit at a matching weight rather
/// than one of them shouting.
enum BadgeImage {
    static func make(label: String, flag: String?, stripes: (colors: [String], vertical: Bool)?,
                     style: BadgeStyle, points: CGFloat) -> NSImage {
        switch style {
        case .plain: return text(label, points: points, inverted: false, box: nil)
        case .filled: return text(label, points: points, inverted: true, box: .filled)
        case .outlined: return text(label, points: points, inverted: false, box: .outlined)
        case .flagEmoji:
            // No country, no flag: falling back to letters is better than a
            // gap where an indicator should be.
            guard let flag else { return text(label, points: points, inverted: false, box: nil) }
            return emoji(flag, points: points)
        case .flagDrawn:
            guard let stripes else { return text(label, points: points, inverted: false, box: nil) }
            return drawn(stripes, points: points)
        }
    }

    private enum Box { case filled, outlined }

    private static func text(_ label: String, points: CGFloat,
                             inverted: Bool, box: Box?) -> NSImage {
        let font = NSFont.systemFont(ofSize: points * 0.72, weight: .semibold)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let padding: CGFloat = box == nil ? 0 : points * 0.28
        let canvas = NSSize(width: ceil(size.width) + padding * 2,
                            height: max(points, ceil(size.height)) + (box == nil ? 0 : 2))

        return NSImage(size: canvas, flipped: false) { rect in
            let radius = rect.height * 0.28
            if let box {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: radius, yRadius: radius)
                NSColor.labelColor.setStroke()
                NSColor.labelColor.setFill()
                if box == .filled { path.fill() } else { path.lineWidth = 1; path.stroke() }
            }
            let colour: NSColor = inverted ? .textBackgroundColor : .labelColor
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let where_ = NSPoint(x: (rect.width - size.width) / 2,
                                 y: (rect.height - size.height) / 2)
            (label as NSString).draw(at: where_, withAttributes: attributes)
            return true
        }
    }

    private static func emoji(_ flag: String, points: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: points)
        let size = (flag as NSString).size(withAttributes: [.font: font])
        return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)),
                       flipped: false) { rect in
            (flag as NSString).draw(in: rect, withAttributes: [.font: font])
            return true
        }
    }

    /// Plain bands, which is what most of the flags in the table are. A flag
    /// with a crest or a canton is not in the table at all — better letters
    /// than a wrong flag.
    private static func drawn(_ stripes: (colors: [String], vertical: Bool),
                              points: CGFloat) -> NSImage {
        let height = points
        let width = (height * 1.45).rounded()
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.setClip()
            let count = CGFloat(stripes.colors.count)
            for (index, hex) in stripes.colors.enumerated() {
                let band: NSRect = stripes.vertical
                    ? NSRect(x: rect.width / count * CGFloat(index), y: 0,
                             width: rect.width / count, height: rect.height)
                    : NSRect(x: 0, y: rect.height - rect.height / count * CGFloat(index + 1),
                             width: rect.width, height: rect.height / count)
                NSColor(hex: hex).setFill()
                band.fill()
            }
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
            return true
        }
    }
}

private extension NSColor {
    /// Six hex digits, as the stripe table stores them.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
