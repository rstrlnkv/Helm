import CoreGraphics

/// A tool of the inline editor. Part 3 adds more; each is a case here, and each says
/// how it is drawn in `Annotation.stroke`, `isFilled`, `isUsable` and `outline` —
/// the four switches that the screen and the export both read.
public enum AnnotationTool: Sendable, Equatable {
    /// Thick, tapered, filled: a tail that starts at a point and widens into the head.
    case arrow
    /// An outline.
    case rectangle
    /// An outline of the box the drag spans.
    case ellipse
    /// A straight stroke from the press to the pointer.
    case line
    /// A freehand stroke through the drag's points, smoothed.
    case pencil
    /// A wide translucent freehand stroke like the pencil's, straight at 45° steps with ⇧,
    /// multiplied into the picture.
    case highlighter
}

/// How a stroked annotation is inked: one description that the screen's shape layer and
/// the export's context both read, so the two cannot disagree about width, colour or blend.
public struct AnnotationStroke: Sendable, Equatable {
    public let width: CGFloat
    public let color: CGColor
    /// Multiplied into what is under it: a dark pixel stays dark, a white one takes the tint.
    public let multiplies: Bool
    /// Round caps and joins for a freehand or marker stroke, butt and miter for a shape.
    public let rounded: Bool
}

/// One layer over the frozen picture, in display-local points like a selection.
///
/// Stored in **points** and nowhere in pixels: the screen draws it in points and the
/// export multiplies by the display's scale, so one geometry serves both and a
/// stroke is as thick in the file as it was on the screen.
public struct Annotation: Sendable, Equatable {
    public let tool: AnnotationTool
    public let start: CGPoint
    public let end: CGPoint
    /// The freehand path of the pencil and the highlighter, first point to last; empty for the other tools.
    public let points: [CGPoint]

    public init(tool: AnnotationTool, start: CGPoint, end: CGPoint, points: [CGPoint] = []) {
        self.tool = tool
        self.start = start
        self.end = end
        self.points = points
    }

    /// The pilot's one ink, sRGB red; presets are a later task.
    public static let ink = CGColor(srgbRed: 0.92, green: 0.16, blue: 0.14, alpha: 1)
    /// The outline's stroke, in points.
    public static let lineWidth: CGFloat = 3
    /// The arrow's shaft at its thickest, in points.
    static let shaft: CGFloat = 6
    /// The marker's width, in points; wide enough to cover a line of text.
    public static let markerWidth: CGFloat = 16
    /// The marker's tint, sRGB yellow at 60 %; the multiply is what keeps text readable.
    public static let markerInk = CGColor(srgbRed: 1, green: 0.9, blue: 0.1, alpha: 0.6)
    /// The most points a pencil stroke keeps; a longer drag is thinned, never grown.
    public static let maxPoints = 1024
    /// The nearest a new freehand point may come to the last kept one, in points; a
    /// nearer pointer is only the tip of the stroke until it is this far.
    static let pencilGap: CGFloat = 2

    public var isFilled: Bool { tool == .arrow }

    /// The ink of a stroked annotation; nil for the filled arrow.
    public var stroke: AnnotationStroke? {
        switch tool {
        case .arrow: return nil
        case .rectangle, .ellipse, .line:
            return AnnotationStroke(width: Self.lineWidth, color: Self.ink, multiplies: false, rounded: tool == .line)
        case .pencil:
            return AnnotationStroke(width: Self.lineWidth, color: Self.ink, multiplies: false, rounded: true)
        case .highlighter:
            return AnnotationStroke(width: Self.markerWidth, color: Self.markerInk, multiplies: true, rounded: false)
        }
    }

    /// Where the pointer wants the far corner or end to be once ⇧ is read: a square or
    /// a circle for the box tools (the longer side wins, each axis keeps its sign) and
    /// the nearest multiple of 45° for the straight ones, length kept. The pencil
    /// ignores it. The caller passes the **live** flag of the event in hand. With `bounds`
    /// a box with no travel on an axis grows to the side that has more room there.
    public static func constrained(_ tool: AnnotationTool, from start: CGPoint, to end: CGPoint,
                                   shift: Bool, within bounds: CGRect? = nil) -> CGPoint {
        guard shift else { return end }
        let dx = end.x - start.x, dy = end.y - start.y
        switch tool {
        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            let left = dx == 0 ? bounds.map { start.x - $0.minX > $0.maxX - start.x } ?? false : dx < 0
            let up = dy == 0 ? bounds.map { start.y - $0.minY > $0.maxY - start.y } ?? false : dy < 0
            return CGPoint(x: start.x + (left ? -side : side), y: start.y + (up ? -side : side))
        case .line, .highlighter:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        case .arrow, .pencil:
            return end
        }
    }

    /// Whether there is anything to draw: a click that never moved is not an
    /// arrow, and a rectangle with no width or no height is a line the person did
    /// not ask for. Not finite is not usable either.
    public var isUsable: Bool {
        guard ([start.x, start.y, end.x, end.y] + points.flatMap { [$0.x, $0.y] }).allSatisfy(\.isFinite)
        else { return false }
        switch tool {
        case .arrow, .line: return hypot(end.x - start.x, end.y - start.y) >= 1
        case .highlighter where points.isEmpty: return hypot(end.x - start.x, end.y - start.y) >= 1
        case .rectangle, .ellipse: return abs(end.x - start.x) >= 1 && abs(end.y - start.y) >= 1
        case .pencil, .highlighter: return points.contains { hypot($0.x - start.x, $0.y - start.y) >= 1 }
        }
    }

    /// The shape, in the same top-left points: filled for an arrow, otherwise stroked
    /// as `stroke` says. The one geometry the screen and the export both draw.
    /// The pencil and the highlighter are smoothed as a quadratic curve through the midpoints of its
    /// points, each point the control of the bend it makes, ending on the last.
    public var outline: CGPath {
        switch tool {
        case .line, .highlighter where points.isEmpty:
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: end)
            return path
        case .ellipse:
            return CGPath(ellipseIn: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                            width: abs(end.x - start.x), height: abs(end.y - start.y)),
                          transform: nil)
        case .pencil, .highlighter:
            let path = CGMutablePath()
            guard let first = points.first, let last = points.last, points.count > 1 else { return path }
            path.move(to: first)
            for index in 1..<(points.count - 1) {
                let here = points[index], next = points[index + 1]
                path.addQuadCurve(to: CGPoint(x: (here.x + next.x) / 2, y: (here.y + next.y) / 2), control: here)
            }
            path.addLine(to: last)
            return path
        case .rectangle:
            return CGPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)),
                          transform: nil)
        case .arrow:
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { return CGMutablePath() }
            let along = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
            let across = CGVector(dx: -along.dy, dy: along.dx)
            // The head is at most as long as half the arrow, so a short one is still
            // an arrow and not a head with no shaft.
            let head = min(length * 0.5, Self.shaft * 3)
            let base = CGPoint(x: end.x - along.dx * head, y: end.y - along.dy * head)
            func point(_ origin: CGPoint, _ side: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + across.dx * side, y: origin.y + across.dy * side)
            }
            let path = CGMutablePath()
            path.addLines(between: [
                point(start, Self.shaft * 0.1), point(base, Self.shaft * 0.5), point(base, Self.shaft * 1.5),
                end,
                point(base, -Self.shaft * 1.5), point(base, -Self.shaft * 0.5), point(start, -Self.shaft * 0.1),
            ])
            path.closeSubpath()
            return path
        }
    }
}
