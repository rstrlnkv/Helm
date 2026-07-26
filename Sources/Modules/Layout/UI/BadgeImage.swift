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
/// through the middle of the flag. The same mistake once made an outline two
/// physical pixels instead of one; the outline is gone entirely now — the
/// corner rounding is the only frame.
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
            // No outline: the flags stand on their colours, with the corner
            // rounding as the only frame. The heavy theme-aware stroke tried
            // before read as a border around a control rather than as a flag.
            let radius = canvas.radius / canvas.scale
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).setClip()
            paint(art, in: canvas)
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
        case let .bandsEmblem(colors, weights, vertical, emblem):
            bands(colors, weights, vertical: vertical, in: canvas)
            draw(emblem, in: canvas)
        case let .centeredCross(field, cross):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            let arm = max((canvas.height * 0.20).rounded(), 2)
            let midX = (canvas.width / 2).rounded(), midY = (canvas.height / 2).rounded()
            fill(cross, canvas.rect(0, midY - (arm / 2).rounded(), canvas.width, arm))
            fill(cross, canvas.rect(midX - (arm / 2).rounded(), 0, arm, canvas.height))
        case let .stripesCanton(stripes, canton, emblem):
            bands(stripes, Array(repeating: 1, count: stripes.count),
                  vertical: false, in: canvas)
            // The canton: upper hoist corner, two fifths of the width, and in
            // height a whole number of stripes so its bottom edge lands on a
            // stripe boundary instead of cutting one in half.
            let stripe = canvas.height / CGFloat(stripes.count)
            // A single "stripe" is a plain field (Taiwan): the canton takes
            // the usual upper quarter rather than the whole height.
            let cantonH = stripes.count > 1
                ? (stripe * CGFloat((stripes.count + 1) / 2)).rounded()
                : (canvas.height / 2).rounded()
            let cantonW = (canvas.width * 0.4).rounded()
            let cantonRect = canvas.rect(0, canvas.height - cantonH, cantonW, cantonH)
            fill(canton, cantonRect)
            if let emblem {
                draw(emblem, in: canvas,
                     cx: cantonW / 2, cy: canvas.height - cantonH / 2)
            }
        case let .unionJack(field):
            unionJack(field: field, in: canvas.rect(0, 0, canvas.width, canvas.height),
                      canvas: canvas)
        case let .jackCanton(field):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            unionJack(field: field,
                      in: canvas.rect(0, (canvas.height / 2).rounded(),
                                      (canvas.width / 2).rounded(),
                                      canvas.height - (canvas.height / 2).rounded()),
                      canvas: canvas)
        case let .crescentStar(field, mark):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            // The crescent is two discs: the mark's, then the field's laid
            // over it, offset towards the fly.
            let r = canvas.height * 0.30
            let cx = canvas.width * 0.38, cy = canvas.height / 2
            NSColor(hex: mark).setFill()
            NSBezierPath(ovalIn: canvas.rect(cx - r, cy - r, r * 2, r * 2)).fill()
            NSColor(hex: field).setFill()
            let inset = r * 0.28
            NSBezierPath(ovalIn: canvas.rect(cx - r + inset * 1.6, cy - r + inset * 0.8,
                                             (r - inset) * 2, (r - inset) * 2)).fill()
            star5(hex: mark, cx: canvas.width * 0.66, cy: cy,
                  radius: canvas.height * 0.14, canvas: canvas)
        case let .star(field, star, atHoist):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            if atHoist {
                star5(hex: star, cx: canvas.width * 0.22, cy: canvas.height * 0.68,
                      radius: canvas.height * 0.22, canvas: canvas)
            } else {
                star5(hex: star, cx: canvas.width / 2, cy: canvas.height / 2,
                      radius: canvas.height * 0.30, canvas: canvas)
            }
        case let .taegeuk(field):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            let r = canvas.height * 0.32
            let box = canvas.rect(canvas.width / 2 - r, canvas.height / 2 - r, r * 2, r * 2)
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(ovalIn: box).setClip()
            // Red above, blue below — the S-curve is below badge size.
            fill("CD2E3A", canvas.rect(0, (canvas.height / 2).rounded(),
                                       canvas.width, canvas.height))
            fill("0047A0", canvas.rect(0, 0, canvas.width, (canvas.height / 2).rounded()))
            NSGraphicsContext.current?.restoreGraphicsState()
        case let .rhombusDisc(field, rhombus, disc):
            fill(field, canvas.rect(0, 0, canvas.width, canvas.height))
            let path = NSBezierPath()
            let inX = canvas.width * 0.10, inY = canvas.height * 0.10
            path.move(to: canvas.point(canvas.width / 2, canvas.height - inY))
            path.line(to: canvas.point(canvas.width - inX, canvas.height / 2))
            path.line(to: canvas.point(canvas.width / 2, inY))
            path.line(to: canvas.point(inX, canvas.height / 2))
            path.close()
            NSColor(hex: rhombus).setFill()
            path.fill()
            let r = canvas.height * 0.22
            NSColor(hex: disc).setFill()
            NSBezierPath(ovalIn: canvas.rect(canvas.width / 2 - r, canvas.height / 2 - r,
                                             r * 2, r * 2)).fill()
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

    /// The crest, star or leaf reduced to a shape. Coordinates arrive as
    /// fractions of the canvas; `cx`/`cy` override them when a caller places
    /// the emblem itself (the canton does).
    private static func draw(_ emblem: FlagArt.Emblem, in canvas: Canvas,
                             cx: CGFloat? = nil, cy: CGFloat? = nil) {
        let x = cx ?? canvas.width * CGFloat(emblem.x)
        // Emblem y counts from the top, the canvas from the bottom.
        let y = cy ?? canvas.height * (1 - CGFloat(emblem.y))
        let d = canvas.height * CGFloat(emblem.size)
        let colour = NSColor(hex: emblem.hex)
        switch emblem.shape {
        case .disc:
            colour.setFill()
            NSBezierPath(ovalIn: canvas.rect(x - d / 2, y - d / 2, d, d)).fill()
        case .star5:
            star5(hex: emblem.hex, cx: x, cy: y, radius: d / 2, canvas: canvas)
        case .star6:
            // A hexagram is two triangles; at badge size that is exactly what
            // is drawn.
            colour.setFill()
            for flip in [CGFloat(1), -1] {
                let path = NSBezierPath()
                path.move(to: canvas.point(x, y + flip * d / 2))
                path.line(to: canvas.point(x + d * 0.43, y - flip * d * 0.25))
                path.line(to: canvas.point(x - d * 0.43, y - flip * d * 0.25))
                path.close()
                path.fill()
            }
        case .cross:
            let arm = max((d * 0.4).rounded(), 2)
            fill(emblem.hex, canvas.rect(x - d / 2, y - (arm / 2).rounded(), d, arm))
            fill(emblem.hex, canvas.rect(x - (arm / 2).rounded(), y - d / 2, arm, d))
        case .shield:
            // A rectangle coming to a point: the silhouette every crest in the
            // table shares once the detail is gone.
            let w = d * 0.72
            let path = NSBezierPath()
            path.move(to: canvas.point(x - w / 2, y + d / 2))
            path.line(to: canvas.point(x + w / 2, y + d / 2))
            path.line(to: canvas.point(x + w / 2, y - d * 0.15))
            path.line(to: canvas.point(x, y - d / 2))
            path.line(to: canvas.point(x - w / 2, y - d * 0.15))
            path.close()
            colour.setFill()
            path.fill()
        case .vstripe:
            let w = max((canvas.width * CGFloat(emblem.size)).rounded(), 2)
            fill(emblem.hex, canvas.rect((x - w / 2).rounded(), 0, w, canvas.height))
        }
    }

    private static func star5(hex: String, cx: CGFloat, cy: CGFloat,
                              radius: CGFloat, canvas: Canvas) {
        let path = NSBezierPath()
        let inner = radius * 0.42
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 + .pi / 2   // a point straight up
            let r = i.isMultiple(of: 2) ? radius : inner
            let point = canvas.point(cx + cos(angle) * r, cy + sin(angle) * r)
            i == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.close()
        NSColor(hex: hex).setFill()
        path.fill()
    }

    /// The Jack, into whatever rectangle it is asked for — the whole badge for
    /// GB, the canton for Australia. Drawn without the counterchange of the
    /// saltire, which is half a pixel at badge size.
    private static func unionJack(field: String, in rect: NSRect, canvas: Canvas) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).setClip()
        NSColor(hex: field).setFill()
        rect.fill()
        let h = rect.height
        // Diagonals as stroked lines, white under red.
        for (hex, width) in [("FFFFFF", h * 0.24), ("C8102E", h * 0.10)] {
            NSColor(hex: hex).setStroke()
            for (from, to) in [((rect.minX, rect.minY), (rect.maxX, rect.maxY)),
                               ((rect.minX, rect.maxY), (rect.maxX, rect.minY))] {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: from.0, y: from.1))
                path.line(to: NSPoint(x: to.0, y: to.1))
                path.lineWidth = width
                path.stroke()
            }
        }
        // The cross, white under red, over the saltire.
        for (hex, width) in [("FFFFFF", h * 0.33), ("C8102E", h * 0.20)] {
            NSColor(hex: hex).setFill()
            NSRect(x: rect.midX - width / 2, y: rect.minY,
                   width: width, height: rect.height).fill()
            NSRect(x: rect.minX, y: rect.midY - width / 2,
                   width: rect.width, height: width).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func fill(_ hex: String, _ rect: NSRect) {
        NSColor(hex: hex).setFill()
        rect.fill()
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
