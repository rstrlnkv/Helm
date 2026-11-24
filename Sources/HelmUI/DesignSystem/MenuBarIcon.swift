import AppKit
import HelmRuntime

/// The shape Helm wears in the menu bar.
///
/// A countdown is a fraction of whatever the outline is, walked from the top,
/// so any closed path can carry the timer. A shape with no outer outline would
/// have nothing for the countdown and the spinner to consume.
public enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case ring, doubleRing, ringDot, squircle, hexagon, capsule

    public var label: String {
        switch self {
        case .ring: return L(.ring)
        case .doubleRing: return L(.doubleRing)
        case .ringDot: return L(.ringDot)
        case .squircle: return L(.square)
        case .hexagon: return L(.hexagon)
        case .capsule: return L(.capsule)
        }
    }

    /// A value read back from disk, including `disc` and `dot`, which this
    /// build does not offer: they had no outer ring for the countdown and the
    /// spinner. Whoever had one gets the ring rather than the default, because a
    /// shape silently becoming the factory setting looks like the app forgetting.
    public init(stored: String) {
        switch stored {
        case "disc", "dot": self = .ring
        default: self = MenuBarIconStyle(rawValue: stored) ?? .ring
        }
    }
}

/// Menu-bar icon size (canvas point size).
public enum MenuBarIconSize: String, CaseIterable, Sendable {
    // Raw values are stored, so they stay as they are whatever the labels say.
    // Smaller or larger than these sits wrong beside the menu bar's own glyphs.
    case xxSmall, extraSmall, small

    public var points: CGFloat {
        switch self {
        case .xxSmall: return 11
        case .extraSmall: return 13
        case .small: return 15
        }
    }

    /// A value read back from disk, including two stored values this build does
    /// not offer, and **the one place the shipped default is written**.
    ///
    /// Those map to the nearest size rather than to the default: somebody who
    /// chose the smallest icon wanted a small icon. `xxxSmall` (9) becomes 11,
    /// `medium` (18) becomes 15. The fallback is `.small`, 15 pt, «L».
    public init(stored: String) {
        switch stored {
        case "xxxSmall": self = .xxSmall
        case "medium": self = .small
        default: self = MenuBarIconSize(rawValue: stored) ?? .small
        }
    }

    /// S, M, L, and not translated, because they are not words: three letters
    /// compare at a glance and mean the same in eight languages, where names
    /// like «Medium» have to be read and make claims about absolute size.
    public var label: String {
        switch self {
        case .xxSmall: return "S"
        case .extraSmall: return "M"
        case .small: return "L"
        }
    }
}

public enum MenuBarIcon {

    /// The glyph. `tintToken` nil → template (system-recoloured, white while
    /// inactive). Non-nil → drawn in that palette colour, which is what an
    /// active module asks for. `progress` (0…1) draws the outline as a
    /// countdown: full at 1, empty at 0, consumed clockwise from the top.
    public static func make(style: MenuBarIconStyle, size: MenuBarIconSize,
                            tintToken: String?, progress: Double? = nil) -> NSImage {
        draw(size: size, tintToken: tintToken) { s, colour in
            let path = outline(style: style, size: s)
            let width = lineWidth(s)
            guard let progress else {
                strokeWhole(path, width: width, colour: colour)
                interior(style: style, size: s, colour: colour)
                return
            }
            strokeWhole(path, width: width, colour: colour.withAlphaComponent(0.25))
            // `clamped` keeps a NaN, and the arc below is the only reader, where
            // `NaN > 0` is false: the track is drawn and nothing over it.
            // Anything here that is not a comparison has to decide that case
            // first (`clamped(to:whenNotANumber:)`).
            let remaining = progress.clamped(to: 0...1)
            if remaining > 0 {
                stroke(perimeter(of: path), from: 0, to: remaining,
                       width: width, colour: colour)
            }
            interior(style: style, size: s, colour: colour)
        }
    }

    /// The outline as a quarter travelling along itself, over the countdown's
    /// faint track so the icon keeps its footprint while it moves.
    ///
    /// `phase` runs 0…1 across the whole spin and the segment goes round
    /// *twice* in it, so half way is one whole revolution and the two ends
    /// meet.
    private static func makeSpinner(style: MenuBarIconStyle, size: MenuBarIconSize,
                                   tintToken: String?, phase: Double) -> NSImage {
        draw(size: size, tintToken: tintToken) { s, colour in
            let path = outline(style: style, size: s)
            let width = lineWidth(s)
            strokeWhole(path, width: width, colour: colour.withAlphaComponent(0.25))
            let head = (phase * 2).truncatingRemainder(dividingBy: 1)
            stroke(perimeter(of: path), from: head, to: head + 0.25,
                   width: width, colour: colour)
            interior(style: style, size: s, colour: colour)
        }
    }

    public static func spinnerFrames(style: MenuBarIconStyle, size: MenuBarIconSize,
                                     tintToken: String?) -> [NSImage] {
        let key = SpinnerKey(style: style, size: size, tint: tintToken,
                             appearance: currentAppearanceName)
        return spinnerCache.value(for: key) {
            (0..<frameCount).map {
                makeSpinner(style: style, size: size, tintToken: tintToken,
                            phase: Double($0) / Double(frameCount))
            }
        }
    }

    /// Frames in one spin: two revolutions over `StatusPlan.spinDuration` at
    /// the thirty frames a second the menu bar redraws at.
    public static let frameCount = 36

    // MARK: - The shapes

    static func lineWidth(_ s: CGFloat) -> CGFloat { max(1.5, s * 0.12) }

    /// The closed outline, inset by half its own stroke so the shape ends at
    /// the canvas edge rather than half a line beyond it.
    ///
    /// This is what the countdown and the spin travel along. Anything a shape
    /// draws *inside* it is `interior`, redrawn on top of every arc, or a
    /// double ring would collapse to a plain ring while a timer runs.
    static func outline(style: MenuBarIconStyle, size s: CGFloat) -> NSBezierPath {
        let w = lineWidth(s)
        let rect = NSRect(x: w / 2, y: w / 2, width: s - w, height: s - w)
        switch style {
        case .ring, .doubleRing, .ringDot:
            return NSBezierPath(ovalIn: rect)
        case .squircle:
            return NSBezierPath(roundedRect: rect, xRadius: s * 0.28, yRadius: s * 0.28)
        case .hexagon:
            let r = (s - w) / 2
            let path = NSBezierPath()
            for corner in 0..<6 {
                let angle = .pi / 2 + Double(corner) * .pi / 3
                let point = CGPoint(x: s / 2 + cos(angle) * r, y: s / 2 + sin(angle) * r)
                corner == 0 ? path.move(to: point) : path.line(to: point)
            }
            path.close()
            return path
        case .capsule:
            let h = s * 0.62
            let capsule = NSRect(x: w / 2, y: (s - h) / 2, width: s - w, height: h)
            return NSBezierPath(roundedRect: capsule, xRadius: h / 2, yRadius: h / 2)
        }
    }

    /// What a shape puts inside its outline, drawn over whatever the arc left.
    static func interior(style: MenuBarIconStyle, size s: CGFloat, colour: NSColor) {
        let w = lineWidth(s)
        colour.setStroke()
        colour.setFill()
        switch style {
        case .ring, .squircle, .hexagon, .capsule:
            break
        case .doubleRing:
            let inset = s * 0.2 + w
            let inner = NSBezierPath(ovalIn: NSRect(x: inset, y: inset,
                                                    width: s - 2 * inset, height: s - 2 * inset))
            inner.lineWidth = max(1, w * 0.7)
            inner.stroke()
        case .ringDot:
            let d = s * 0.24
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
        }
    }

    // MARK: - Walking a perimeter

    /// The outline flattened to points, starting at the top and running
    /// clockwise.
    ///
    /// Neither is a property of the path as built: `NSBezierPath(roundedRect:)`
    /// and a hand-built polygon start and wind wherever their construction did,
    /// and a countdown running anti-clockwise from the bottom left is a clock
    /// going backwards. So the orientation is established here, not trusted.
    static func perimeter(of path: NSBezierPath) -> [CGPoint] {
        // Finer than the default 0.6, which turns a 15 pt circle into an
        // octagon: the walk is only ever a *part* of the outline, so it has to
        // agree with the whole one drawn under it.
        //
        // Set on the class, not on the path: `flattened` ignores the instance's
        // own `flatness` and reads `NSBezierPath.defaultFlatness`. It is global
        // state, so it is restored right after the one flatten.
        // `copy()` comes from `NSCopying` typed `Any`; `NSBezierPath.copy()`
        // returns an `NSBezierPath` by contract, so this cannot fail.
        // swiftlint:disable:next force_cast
        let copy = path.copy() as! NSBezierPath
        let previousFlatness = NSBezierPath.defaultFlatness
        NSBezierPath.defaultFlatness = 0.02
        defer { NSBezierPath.defaultFlatness = previousFlatness }
        let flat = copy.flattened
        var points: [CGPoint] = []
        var buffer = [CGPoint](repeating: .zero, count: 3)
        for index in 0..<flat.elementCount {
            switch flat.element(at: index, associatedPoints: &buffer) {
            case .moveTo, .lineTo: points.append(buffer[0])
            default: break
            }
        }
        // A flattened closed path repeats its first point at the end on some
        // shapes and not on others; the walk closes it itself, so drop it.
        if points.count > 1, let first = points.first, let last = points.last,
           hypot(last.x - first.x, last.y - first.y) < 0.001 {
            points.removeLast()
        }
        guard points.count > 2 else { return points }

        // Signed area: positive is counter-clockwise in AppKit's coordinates.
        var area: CGFloat = 0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            area += point.x * next.y - next.x * point.y
        }
        if area > 0 { points.reverse() }

        // Start at twelve o'clock, which usually is not one of the points:
        // flattening a rounded rectangle turns its top edge into one segment
        // whose ends are the corners, so the top edge is split rather than
        // chosen from.
        let top = points.map(\.y).max() ?? 0
        let centreX = (points.map(\.x).min()! + points.map(\.x).max()!) / 2
        let atTop = { (point: CGPoint) in point.y > top - 0.001 }

        if let edge = points.indices.first(where: { index in
            let a = points[index], b = points[(index + 1) % points.count]
            return atTop(a) && atTop(b) && min(a.x, b.x) <= centreX && centreX <= max(a.x, b.x)
        }) {
            var rotated = Array(points[(edge + 1)...] + points[...edge])
            rotated.append(CGPoint(x: centreX, y: top))
            return Array(rotated[(rotated.count - 1)...] + rotated[..<(rotated.count - 1)])
        }

        let start = points.indices
            .filter { atTop(points[$0]) }
            .min { abs(points[$0].x - centreX) < abs(points[$1].x - centreX) } ?? 0
        return Array(points[start...] + points[..<start])
    }

    /// The whole outline, drawn as the curve it is, not as the flattened walk,
    /// which would turn a small circle into a faceted polygon. The walk is for
    /// parts of the outline; this is for all of it.
    static func strokeWhole(_ path: NSBezierPath, width: CGFloat, colour: NSColor) {
        path.lineWidth = width
        path.lineJoinStyle = .round
        colour.setStroke()
        path.stroke()
    }

    /// Stroke the fraction of the perimeter between `from` and `to`, both 0…1,
    /// wrapping past 1.
    static func stroke(_ points: [CGPoint], from: Double, to: Double,
                       width: CGFloat, colour: NSColor) {
        guard points.count > 1 else { return }
        let lengths = points.indices.map { index -> CGFloat in
            let next = points[(index + 1) % points.count]
            return hypot(next.x - points[index].x, next.y - points[index].y)
        }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return }

        let path = NSBezierPath()
        var walked: CGFloat = 0
        var started = false
        let begin = CGFloat(from) * total
        let end = CGFloat(to) * total
        // Twice round, so a segment that wraps past the start is one stroke
        // rather than two that meet at a seam.
        for _ in 0..<2 {
            for (index, segment) in lengths.enumerated() {
                let a = points[index], b = points[(index + 1) % points.count]
                let segmentStart = walked, segmentEnd = walked + segment
                walked = segmentEnd
                guard segmentEnd > begin, segmentStart < end, segment > 0 else { continue }
                let t0 = max(0, (begin - segmentStart) / segment)
                let t1 = min(1, (end - segmentStart) / segment)
                let p0 = CGPoint(x: a.x + (b.x - a.x) * t0, y: a.y + (b.y - a.y) * t0)
                let p1 = CGPoint(x: a.x + (b.x - a.x) * t1, y: a.y + (b.y - a.y) * t1)
                if !started { path.move(to: p0); started = true }
                path.line(to: p1)
            }
        }
        guard started else { return }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        colour.setStroke()
        path.stroke()
    }

    // MARK: - Canvas

    private static func draw(size: MenuBarIconSize, tintToken: String?,
                             body: (CGFloat, NSColor) -> Void) -> NSImage {
        let s = size.points
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        body(s, nsColor(forTintToken: tintToken))
        image.unlockFocus()
        image.isTemplate = (tintToken == nil)
        return image
    }

    /// Every palette colour here is dynamic and `lockFocus` bakes the one that
    /// was current, so the appearance is part of the cache key, or the cache
    /// would keep drawing the old appearance after the user switched.
    private static var currentAppearanceName: String {
        NSAppearance.currentDrawing().name.rawValue
    }

    private struct SpinnerKey: Hashable {
        let style: MenuBarIconStyle
        let size: MenuBarIconSize
        let tint: String?
        let appearance: String
    }

    /// One set of frames per key, built once under the lock, so two redraws
    /// arriving together do not each render the whole spin.
    private static let spinnerCache = LockedMemo<SpinnerKey, [NSImage]>()

    /// Palette lookup, also used for menu-bar text drawn beside the glyph.
    public static func nsColor(forTintToken token: String?) -> NSColor {
        switch token {
        case nil: return .white
        // Theme-adaptive, and a trap in a baked bitmap: `lockFocus` resolves it
        // once against whatever appearance was current, not the one the image is
        // shown in. In-app previews ask for `nil` (a template) and tint with
        // `foregroundStyle`, or go through `HelmAppearance`.
        case "primary": return .labelColor
        // Every palette name, the retired ones too, answers from `PaletteColor`,
        // then a colour the person chose, stored as `#RRGGBB`. Anything else (a
        // token from another build, a hand-edited plist) is white, the untinted
        // glyph, the same answer `nil` gives.
        case let token?: return PaletteColor(rawValue: token)?.nsColor ?? PaletteTint.custom(token) ?? .white
        }
    }
}
