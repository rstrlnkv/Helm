import CoreGraphics

/// A tool of the inline editor. Part 3 adds more; each is a case here.
public enum AnnotationTool: Sendable, Equatable {
    /// Thick, tapered, filled: a tail that starts at a point and widens into the head.
    case arrow
    /// An outline.
    case rectangle
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

    public init(tool: AnnotationTool, start: CGPoint, end: CGPoint) {
        self.tool = tool
        self.start = start
        self.end = end
    }

    /// The pilot's one ink, sRGB red; presets are a later task.
    public static let ink = CGColor(srgbRed: 0.92, green: 0.16, blue: 0.14, alpha: 1)
    /// The outline's stroke, in points.
    public static let lineWidth: CGFloat = 3
    /// The arrow's shaft at its thickest, in points.
    static let shaft: CGFloat = 6

    public var isFilled: Bool { tool == .arrow }

    /// Whether there is anything to draw: a click that never moved is not an
    /// arrow, and a rectangle with no width or no height is a line the person did
    /// not ask for. Not finite is not usable either.
    public var isUsable: Bool {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else { return false }
        switch tool {
        case .arrow: return hypot(end.x - start.x, end.y - start.y) >= 1
        case .rectangle: return abs(end.x - start.x) >= 1 && abs(end.y - start.y) >= 1
        }
    }

    /// The shape, in the same top-left points: filled for an arrow, stroked at
    /// `lineWidth` for a rectangle.
    public var outline: CGPath {
        switch tool {
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
