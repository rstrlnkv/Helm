import CoreGraphics

/// The ruler: a strip on the picture that the Pen, the Pencil and the Marker run a straight line along. A value like
/// `Annotation`, but **not a layer**: it is not in `Annotation`, in the undo steps, in the export or in what the editor
/// remembers, and a stroke drawn along it is an ordinary layer of its pen, which knows nothing of where it was drawn.
/// The overlay holds one and draws it above the layers.
///
/// **Which strokes it straightens.** A stroke straightens when it **began** no farther than `reach` from one of the two
/// long edges, and then it lies on that edge, however far the pointer strays from it, from where it began to where
/// the pointer is, cut at the strip's ends. One that began farther is free from start to end, and so is one that began
/// near the edge and is begun again: the edge is read once, at the press (`edge(near:)`), never along the way.
///
/// The angle is in degrees, clockwise in the display's top-left points, and the strip is the same turned half a circle, so it is
/// held in (-90, 90]. It sticks to 0°, 45° and 90° (and so to -45°, which is the same strip turned the other way) within `stick`.
public struct Ruler: Sendable, Equatable {
    /// The strip's thickness across, in points.
    public static let width: CGFloat = 34
    /// How far from an edge a stroke may begin and still be straightened along it, in points.
    public static let reach: CGFloat = 12
    /// How near to 0°, 45° or 90° the angle sticks to it, in degrees.
    public static let stick: CGFloat = 2
    /// The length the strip appears with, at most: a smaller area takes four fifths of its width.
    public static let standardLength: CGFloat = 300

    public private(set) var center: CGPoint
    public let length: CGFloat
    /// Degrees, clockwise, in (-90, 90].
    public private(set) var angle: CGFloat

    public init(center: CGPoint, length: CGFloat = standardLength, angle: CGFloat = 0) {
        self.center = center
        self.length = length
        self.angle = 0
        rotate(to: angle)
    }

    /// The strip as it appears in `area`: in its middle, level.
    public static func centred(in area: CGRect) -> Ruler {
        Ruler(center: CGPoint(x: area.midX, y: area.midY), length: min(standardLength, area.width * 0.8))
    }

    /// One long side of the strip.
    public struct Edge: Sendable, Equatable {
        public let from: CGPoint
        public let to: CGPoint

        /// The nearest point of the edge to `point`.
        public func project(_ point: CGPoint) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y
            let along = dx * dx + dy * dy
            guard along > 0 else { return from }
            let t = min(max(((point.x - from.x) * dx + (point.y - from.y) * dy) / along, 0), 1)
            return CGPoint(x: from.x + dx * t, y: from.y + dy * t)
        }

        public func distance(to point: CGPoint) -> CGFloat {
            let near = project(point)
            return hypot(point.x - near.x, point.y - near.y)
        }
    }

    private var radians: CGFloat { angle * .pi / 180 }

    /// The strip's point at `across` the strip and `along` its length from the centre, in display points.
    private func place(along: CGFloat, across: CGFloat) -> CGPoint {
        let cosine = cos(radians), sine = sin(radians)
        return CGPoint(x: center.x + along * cosine - across * sine, y: center.y + along * sine + across * cosine)
    }

    /// The two long edges, the one on the upper side of a level strip first.
    public var edges: [Edge] {
        [-Self.width / 2, Self.width / 2].map { Edge(from: place(along: -length / 2, across: $0), to: place(along: length / 2, across: $0)) }
    }

    /// Whether `point` is on the strip, by the strip's own axes.
    public func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let along = dx * cos(radians) + dy * sin(radians), across = -dx * sin(radians) + dy * cos(radians)
        return abs(along) <= length / 2 && abs(across) <= Self.width / 2
    }

    /// The edge a stroke that begins at `point` runs along: the nearer one, when it is within `reach`.
    public func edge(near point: CGPoint) -> Edge? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return edges.map { (edge: $0, distance: $0.distance(to: point)) }.min { $0.distance < $1.distance }
            .flatMap { $0.distance <= Self.reach ? $0.edge : nil }
    }

    /// Where a stroke that begins at `point` lies: on the nearer edge, or nil when it begins too far from both and is free.
    public func snap(_ point: CGPoint) -> CGPoint? { edge(near: point)?.project(point) }

    /// The strip taken to `point`, held with its centre inside `area`. A point that is not a number moves nothing.
    public mutating func move(to point: CGPoint, within area: CGRect) {
        guard point.x.isFinite, point.y.isFinite else { return }
        center = CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }

    /// The strip's centre held inside `area`, as when the area has shrunk past it.
    public mutating func keep(within area: CGRect) { move(to: center, within: area) }

    /// The strip turned to `degrees`, wrapped into (-90, 90] and stuck to 0°, 45° and 90° within `stick`. A value that is
    /// not a number turns nothing.
    public mutating func rotate(to degrees: CGFloat) {
        guard degrees.isFinite else { return }
        var wrapped = degrees.truncatingRemainder(dividingBy: 180)
        if wrapped > 90 { wrapped -= 180 } else if wrapped <= -90 { wrapped += 180 }
        if let sticky = [-90, -45, 0, 45, 90].first(where: { abs(wrapped - CGFloat($0)) <= Self.stick }) { wrapped = CGFloat(sticky) }
        angle = wrapped == -90 ? 90 : wrapped
    }

    /// The direction from the centre to `point`, in degrees clockwise like `angle`, unwrapped and unstuck: what an ⌥-drag turns by.
    public func degrees(toward point: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }
}
