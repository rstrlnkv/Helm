import AppKit
import Module_Layout_Engine

/// Draws the badge the menu bar shows.
///
/// Every style is one image at the requested point size — the same sizes the
/// app's own icon offers, so the two indicators sit at a matching weight rather
/// than one of them shouting.
///
/// **Flags are laid out in device pixels, not points.** The first version did
/// its arithmetic in points and let the compositor land the edges wherever they
/// fell. At eleven points the Dutch flag is 22 pixels tall and divides into
/// three bands of 7.33, so two rows came out as blends — a pink line through
/// the white band, both of them 78% opaque, which meant the menu bar showed
/// through the middle of the flag. The same mistake made the outline two
/// physical pixels instead of one, and that outline ate a third of Russia's
/// white band at the smallest size.
enum BadgeImage {
    static func make(label: String, flag: String?, art: FlagArt?,
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
            // Letters in the same rounded rectangle the flag would have
            // occupied. Bare letters beside a flag read as a failure to draw
            // one; the framed pair read as one family — and as the box macOS
            // itself puts around "A".
            guard let art else { return text(label, points: points, inverted: false, box: .outlined) }
            return drawn(art, points: points, scale: NSScreen.main?.backingScaleFactor ?? 2)
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

    // MARK: - Drawn flags

    /// Whole device pixels, converted to points only at the moment of drawing.
    ///
    /// Every dimension below is an integer number of pixels, so no edge lands
    /// mid-pixel and nothing comes out translucent.
    private struct Canvas {
        let width: CGFloat      // px
        let height: CGFloat     // px
        let scale: CGFloat

        init(points: CGFloat, scale: CGFloat) {
            self.scale = scale
            self.height = max((points * scale).rounded(), 8)
            // 3:2, one ratio for every flag — including Switzerland, whose
            // rectangular civil flag this is. A badge that changed width when
            // the layout changed would shove the menu bar sideways on a switch.
            self.width = (points * 1.5 * scale).rounded()
        }

        var size: NSSize { NSSize(width: width / scale, height: height / scale) }
        var radius: CGFloat { max((height * 0.12).rounded(), 2) }

        /// A rectangle given in pixels, from the bottom-left, returned in points.
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x / scale, y: y / scale, width: w / scale, height: h / scale)
        }

        /// A point in pixels, returned in points.
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: x / scale, y: y / scale)
        }
    }

    /// The scale is passed in rather than read here so the pixel-grid rules
    /// this file exists to keep can be measured at a known one.
    static func drawn(_ art: FlagArt, points: CGFloat, scale: CGFloat) -> NSImage {
        let canvas = Canvas(points: points, scale: scale)
        return NSImage(size: canvas.size, flipped: false) { rect in
            let radius = canvas.radius / canvas.scale
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).setClip()
            paint(art, in: canvas)
            NSGraphicsContext.current?.restoreGraphicsState()
            outline(rect, radius: radius, scale: canvas.scale)
            return true
        }
    }

    private static func paint(_ art: FlagArt, in canvas: Canvas) {
        switch art {
        case let .bands(colors, weights, vertical):
            bands(colors, weights, vertical: vertical, in: canvas)
        case let .nordic(field, cross, border):
            nordic(field: field, cross: cross, border: border, in: canvas)
        case let .swissCross(field, cross):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            // Arms that stop short of the edge — the detail that makes this
            // Switzerland and not a Scandinavian flag drawn centred.
            let thickness = max((canvas.height * 0.1875).rounded(), 2)
            let length = (canvas.height * 0.625).rounded()
            let midX = (canvas.width / 2).rounded(), midY = (canvas.height / 2).rounded()
            fill(cross, canvas.rect(midX - (length / 2).rounded(),
                                    midY - (thickness / 2).rounded(), length, thickness))
            fill(cross, canvas.rect(midX - (thickness / 2).rounded(),
                                    midY - (length / 2).rounded(), thickness, length))
        case let .disc(field, disc):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            let diameter = (canvas.height * 0.60).rounded()
            NSColor(hex: disc).setFill()
            NSBezierPath(ovalIn: canvas.rect(((canvas.width - diameter) / 2).rounded(),
                                             ((canvas.height - diameter) / 2).rounded(),
                                             diameter, diameter)).fill()
        case let .hoistTriangle(top, bottom, triangle):
            let half = (canvas.height / 2).rounded()
            fill(bottom, canvas.rect(0, 0, canvas.width, half))
            fill(top, canvas.rect(0, half, canvas.width, canvas.height - half))
            let path = NSBezierPath()
            path.move(to: canvas.point(0, 0))
            path.line(to: canvas.point(0, canvas.height))
            path.line(to: canvas.point((canvas.width / 2).rounded(), half))
            path.close()
            NSColor(hex: triangle).setFill()
            path.fill()
        }
    }

    private static func bands(_ colors: [String], _ weights: [Int],
                              vertical: Bool, in canvas: Canvas) {
        let total = CGFloat(weights.reduce(0, +))
        guard total > 0 else { return }
        let extent = vertical ? canvas.width : canvas.height
        var accumulated = 0
        for (index, hex) in colors.enumerated() {
            // Both sides of a boundary are rounded the same way, so bands meet
            // exactly: no overlap, no seam, no blended row between them.
            let start = (CGFloat(accumulated) / total * extent).rounded()
            accumulated += weights[index]
            let end = (CGFloat(accumulated) / total * extent).rounded()
            // Bands are listed top-to-bottom; the canvas counts from the
            // bottom, so a horizontal band is measured back from the top edge.
            fill(hex, vertical
                 ? canvas.rect(start, 0, end - start, canvas.height)
                 : canvas.rect(0, canvas.height - end, canvas.width, end - start))
        }
    }

    private static func nordic(field: String, cross: String, border: String?, in canvas: Canvas) {
        fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
        // The vertical arm sits towards the hoist, at 6/16 of the width. The
        // off-centre cross is what makes this a Nordic flag rather than a
        // Swiss one, and it is why Sweden is not two bands.
        let axisX = (canvas.width * 6 / 16).rounded()
        let axisY = (canvas.height / 2).rounded()

        func arms(_ width: CGFloat, _ hex: String) {
            fill(hex, canvas.rect(0, axisY - (width / 2).rounded(), canvas.width, width))
            fill(hex, canvas.rect(axisX - (width / 2).rounded(), 0, width, canvas.height))
        }

        if let border {
            // Norway and Iceland: a wide outline with a narrow cross inside it.
            // The true inner width is 1/16 of the height — under a pixel at the
            // smallest size, so it is snapped up to one rather than lost. That
            // is an approximated proportion, not a dropped element.
            let outer = max((canvas.height * 0.25).rounded(), 2)
            arms(outer, border)
            arms(max((outer / 2).rounded(), 1), cross)
        } else {
            arms(max((canvas.height * 0.20).rounded(), 2), cross)
        }
    }

    private static func fill(_ hex: String, _ rect: NSRect) {
        NSColor(hex: hex).setFill()
        rect.fill()
    }

    /// One device pixel, drawn inside the shape.
    ///
    /// It goes on every flag, not only the ones with a pale edge: it gives the
    /// set one silhouette, and matches the frame macOS draws around its own
    /// indicator. The alpha is high because the menu bar is translucent — its
    /// luminance measured ten to one across a single dark-mode screenshot,
    /// depending on the wallpaper behind it — so the previous 25% outline came
    /// to 1.8:1 against a white band and was, in effect, not there. Being
    /// resolved inside the drawing block means it follows the current theme.
    private static func outline(_ rect: NSRect, radius: CGFloat, scale: CGFloat) {
        let dark = NSAppearance.currentDrawing()
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let colour = dark ? NSColor.white.withAlphaComponent(0.55)
                          : NSColor.black.withAlphaComponent(0.50)
        colour.setStroke()
        let hairline = 1 / scale
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: hairline / 2, dy: hairline / 2),
                                xRadius: radius, yRadius: radius)
        path.lineWidth = hairline
        path.stroke()
    }
}

private extension NSColor {
    /// Six hex digits, as the flag table stores them.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
