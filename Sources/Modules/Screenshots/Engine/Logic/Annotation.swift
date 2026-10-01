import CoreGraphics

/// A tool of the inline editor. Part 3 adds more; each is a case here, and each says
/// how it is drawn in `Annotation.stroke`, `isFilled`, `isUsable`, `outline` and
/// `constrained` — the switches that the screen and the export both read.
///
/// **The raw value is stored data** (the last tool is remembered): a case is retired
/// and never removed or renamed, and a stored value that is none of the cases reads
/// as no tool.
public enum AnnotationTool: String, CaseIterable, Sendable, Equatable {
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
    /// A wide translucent freehand stroke like the pencil's, a single straight run at 45°
    /// steps while ⇧ is held, multiplied into the picture.
    case highlighter
}

/// How a stroked annotation is inked: one description that the screen's shape layer and
/// the export's context both read, so the two cannot disagree about width, colour or blend.
public struct AnnotationStroke: Sendable, Equatable {
    public let width: CGFloat
    public let color: CGColor
    /// Multiplied into what is under it: a dark pixel stays dark, a white one takes the tint.
    public let multiplies: Bool
    public let cap: CGLineCap
    public let join: CGLineJoin
}

/// One of the eight inks, fixed in sRGB: the picture does not change with the
/// appearance the person's Mac is in. **The raw value is stored data** — retire a
/// case, never remove or rename one.
public enum AnnotationColor: String, CaseIterable, Sendable, Equatable {
    case red, orange, yellow, green, blue, purple, black, white

    private var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red: (0.92, 0.16, 0.14)
        case .orange: (1, 0.58, 0.1)
        case .yellow: (1, 0.9, 0.1)
        case .green: (0.2, 0.78, 0.35)
        case .blue: (0.1, 0.45, 0.95)
        case .purple: (0.62, 0.3, 0.85)
        case .black: (0, 0, 0)
        case .white: (1, 1, 1)
        }
    }

    public var cgColor: CGColor { CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
}

/// The three steps of thickness. One step sets the outline, the arrow's shaft and the
/// marker's width together, so a person picks a weight and not three numbers.
/// **The raw value is stored data**, and a stored number outside 0…2 is clamped to the
/// nearest step by the reader (`EditorMemory`).
public enum AnnotationThickness: Int, CaseIterable, Sendable, Equatable {
    case thin = 0, medium, thick

    /// The outline's stroke, in points.
    public var line: CGFloat { [3, 5, 8][rawValue] }
    /// The arrow's shaft at its thickest, in points.
    public var shaft: CGFloat { [6, 10, 16][rawValue] }
    /// The marker's width, in points; the thinnest is wide enough to cover a line of text.
    public var marker: CGFloat { [16, 24, 32][rawValue] }
}

/// What the **next** object is drawn with: the colour, the thickness and, for the
/// boxes, whether they are filled. An object keeps the style it was begun with.
public struct AnnotationStyle: Sendable, Equatable {
    /// Nil until a colour is picked: each tool then has its own — red, and yellow for
    /// the marker. Once one is picked it is every tool's, the marker's included.
    public var color: AnnotationColor?
    public var thickness: AnnotationThickness
    public var filled: Bool

    public init(color: AnnotationColor? = nil, thickness: AnnotationThickness = .thin, filled: Bool = false) {
        self.color = color
        self.thickness = thickness
        self.filled = filled
    }

    public static let standard = AnnotationStyle()

    /// The ink a tool is drawn in under this style.
    public func ink(for tool: AnnotationTool) -> AnnotationColor {
        color ?? (tool == .highlighter ? .yellow : .red)
    }
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
    public let style: AnnotationStyle

    public init(tool: AnnotationTool, start: CGPoint, end: CGPoint, points: [CGPoint] = [],
                style: AnnotationStyle = .standard) {
        self.tool = tool
        self.start = start
        self.end = end
        self.points = points
        self.style = style
    }

    /// The default ink, sRGB red: what a tool is drawn in until a colour is picked.
    public static let ink = AnnotationColor.red.cgColor
    /// The thinnest step's outline, in points: what an object has until a thickness is picked.
    public static let lineWidth = AnnotationThickness.thin.line
    /// The thinnest step's arrow shaft, in points.
    static let shaft = AnnotationThickness.thin.shaft
    /// The thinnest step's marker width, in points.
    public static let markerWidth = AnnotationThickness.thin.marker
    /// How much of the ink the marker lets through: 60 %. The multiply is what keeps text readable.
    static let markerAlpha: CGFloat = 0.6
    /// The marker's own tint, yellow at that alpha.
    public static let markerInk = AnnotationColor.yellow.cgColor.copy(alpha: markerAlpha)!
    /// The most points a pencil stroke keeps; a longer drag is thinned, never grown.
    public static let maxPoints = 1024
    /// The nearest a new freehand point may come to the last kept one, in points; a
    /// nearer pointer is only the tip of the stroke until it is this far.
    static let pencilGap: CGFloat = 2

    /// Painted as a solid shape rather than stroked: the arrow always, and a rectangle or
    /// an ellipse when the style says filled.
    public var isFilled: Bool {
        tool == .arrow || (style.filled && (tool == .rectangle || tool == .ellipse))
    }

    /// The colour a filled shape is painted in; for a stroked one see `stroke`.
    public var fillColor: CGColor { style.ink(for: tool).cgColor }

    /// The ink of a stroked annotation; nil for a filled shape.
    ///
    /// **Caps and joins.** A shape has butt caps and mitred corners, the line and the
    /// pencil round both. The marker's caps stay butt, flat like a chisel nib, but its
    /// joins are round: it is a freehand stroke 16 pt and more wide, and a mitre on a
    /// jagged path throws a spike far past the point it turns at.
    public var stroke: AnnotationStroke? {
        guard !isFilled else { return nil }
        let ink = style.ink(for: tool).cgColor
        switch tool {
        case .arrow: return nil
        case .rectangle, .ellipse:
            return AnnotationStroke(width: style.thickness.line, color: ink, multiplies: false, cap: .butt, join: .miter)
        case .line, .pencil:
            return AnnotationStroke(width: style.thickness.line, color: ink, multiplies: false, cap: .round, join: .round)
        case .highlighter:
            return AnnotationStroke(width: style.thickness.marker, color: ink.copy(alpha: Self.markerAlpha) ?? ink,
                                    multiplies: true, cap: .butt, join: .round)
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
        case .rectangle, .ellipse: return abs(end.x - start.x) >= 1 && abs(end.y - start.y) >= 1
        case .pencil, .highlighter: return points.contains { hypot($0.x - start.x, $0.y - start.y) >= 1 }
        }
    }

    /// The shape, in the same top-left points: painted as `isFilled` says, otherwise
    /// stroked as `stroke` says. The one geometry the screen and the export both draw.
    /// The pencil and the highlighter are smoothed as a quadratic curve through the midpoints of
    /// their points, each point the control of the bend it makes, ending on the last; with no
    /// more than one point there is no path.
    public var outline: CGPath {
        switch tool {
        case .line:
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
            let shaft = style.thickness.shaft
            let head = min(length * 0.5, shaft * 3)
            let base = CGPoint(x: end.x - along.dx * head, y: end.y - along.dy * head)
            func point(_ origin: CGPoint, _ side: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + across.dx * side, y: origin.y + across.dy * side)
            }
            let path = CGMutablePath()
            path.addLines(between: [
                point(start, shaft * 0.1), point(base, shaft * 0.5), point(base, shaft * 1.5),
                end,
                point(base, -shaft * 1.5), point(base, -shaft * 0.5), point(start, -shaft * 0.1),
            ])
            path.closeSubpath()
            return path
        }
    }
}
