import AppKit
import Module_Layout_Engine

/// Draws the badge the menu bar shows.
///
/// Every style is one image at the requested point size — the same sizes the
/// app's own icon offers, so the two indicators sit at a matching weight rather
/// than one of them shouting.
///
/// Flags are artwork (`FlagAsset`), not geometry: a table of bands and
/// crosses cannot hold an eagle, an armillary sphere or a set of trigrams.
enum BadgeImage {
    static func make(label: String, region: String?,
                     style: BadgeStyle, points: CGFloat) -> NSImage {
        switch style {
        case .plain: return text(label, points: points, inverted: false, box: nil)
        case .filled: return text(label, points: points, inverted: true, box: .filled)
        case .outlined: return text(label, points: points, inverted: false, box: .outlined)
        // Never asked for: `LanguageIndicator` draws the name as the button's
        // title, with no image at all. Answered rather than defaulted, because
        // this switch has no `default`: an unhandled style is a build error.
        case .sourceName: return text(label, points: points, inverted: false, box: nil)
        case .flagDrawn:
            // Letters in the same rounded rectangle the flag would have
            // occupied. Bare letters beside a flag read as a failure to draw
            // one; the framed pair read as one family — and as the box macOS
            // itself puts around "A".
            guard let art = FlagAsset.image(region: region) else {
                return text(label, points: points, inverted: false, box: .outlined)
            }
            return drawn(art, points: points)
        }
    }

    private enum Box { case filled, outlined }

    private static func text(_ label: String, points: CGFloat,
                             inverted: Bool, box: Box?) -> NSImage {
        let font = NSFont.systemFont(ofSize: points * 0.72, weight: .semibold)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let padding: CGFloat = box == nil ? 0 : points * 0.28
        // Exactly `points` tall, whatever the style: the path is already
        // `insetBy(0.5)`, which keeps a 1 pt stroke inside its own rectangle,
        // so a framed badge needs no extra height. A style that moved the badge
        // as far as a size step would make the size a suggestion.
        let canvas = NSSize(width: ceil(size.width) + padding * 2, height: points)

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

    // MARK: - Flag artwork

    /// The artwork at the badge's size, 4:3 — the ratio the source set is
    /// drawn in. Scaling a flag to some other ratio is redrawing it.
    ///
    /// Drawn through a fresh image rather than handed over as-is so the badge
    /// carries the size the caller asked for; `NSStatusItem` scales what it is
    /// given, and a 128 pt image in a 15 pt slot is not the same picture.
    private static func drawn(_ art: NSImage, points: CGFloat) -> NSImage {
        let side = NSSize(width: (points * 4 / 3).rounded(), height: points)
        return NSImage(size: side, flipped: false) { rect in
            art.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            return true
        }
    }
}
