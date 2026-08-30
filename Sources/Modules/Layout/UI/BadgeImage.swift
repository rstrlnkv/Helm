import AppKit
import Module_Layout_Engine

/// Draws the badge the menu bar shows.
///
/// Every style is one image at the requested point size — the same sizes the
/// app's own icon offers, so the two indicators sit at a matching weight rather
/// than one of them shouting.
///
/// Flags are artwork now (`FlagAsset`), not geometry. Helm drew them itself
/// for a while and the drawings were honest, but a table of bands and crosses
/// cannot hold an eagle, an armillary sphere or a set of trigrams, and half a
/// dozen flags were approximations because of it.
enum BadgeImage {
    static func make(label: String, flag: String?, region: String?,
                     style: BadgeStyle, points: CGFloat) -> NSImage {
        switch style {
        case .plain: return text(label, points: points, inverted: false, box: nil)
        case .filled: return text(label, points: points, inverted: true, box: .filled)
        case .outlined: return text(label, points: points, inverted: false, box: .outlined)
        // Never asked for: `LanguageIndicator` draws the name as the button's
        // title, with no image at all. Answered rather than defaulted, because
        // this switch has no `default` — an unhandled style is a build error
        // here, which is how the case above was found the moment it landed.
        case .sourceName: return text(label, points: points, inverted: false, box: nil)
        case .flagEmoji:
            // No country, no flag: falling back to letters is better than a gap
            // where an indicator should be — **framed**, the same fallback
            // `.flagDrawn` makes eight lines below and for the reason written
            // there. It fell back bare until 2026-08-30, and the page's note
            // under both flag styles promises «letters in a frame the same size
            // as a flag»: measured 24.0 × 15.0 pt against `.flagDrawn`'s
            // 32.4 × 17.0, so under «Flag, system» the page said frame and the
            // menu bar drew none, in all eight languages.
            guard let flag else {
                return text(label, points: points, inverted: false, box: .outlined)
            }
            return emoji(flag, points: points)
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
        // **Exactly `points` tall, whatever the style.** A framed badge used to
        // add 2 for the stroke — but the path is already `insetBy(0.5)`, which
        // is what keeps a 1 pt stroke inside its own rectangle, so the 2 bought
        // nothing and cost the one thing «Size» is for: at 15 pt requested,
        // filled and outlined drew 17 while plain drew 15, and the whole Size
        // range is 11 → 15. A style that moves the badge as far as the size
        // picker does makes the size picker a suggestion.
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

    /// The system's own flag glyph, at the height that was asked for.
    ///
    /// **A glyph's line height is not its point size**, and taking the measured
    /// height as the canvas is what made this the tallest style in the app:
    /// 19 pt for a 15 pt badge, taller than «Letters» at any size the size
    /// picker offers. The font is scaled so the drawn glyph *is* `points` tall,
    /// and the canvas says so.
    private static func emoji(_ flag: String, points: CGFloat) -> NSImage {
        let measured = (flag as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: points)])
        let ratio = measured.height > 0 ? points / measured.height : 1
        let font = NSFont.systemFont(ofSize: points * ratio)
        let size = (flag as NSString).size(withAttributes: [.font: font])
        return NSImage(size: NSSize(width: ceil(size.width), height: points),
                       flipped: false) { rect in
            (flag as NSString).draw(in: rect, withAttributes: [.font: font])
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
