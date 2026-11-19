import CoreGraphics

/// The polyline a path flattens to, and the closest point on it: where the pointer is put when it
/// strays into a mask. Ported unchanged from the standalone app.
struct CursorBoundary {
    private struct Segment {
        let start: CGPoint
        let dx: CGFloat
        let dy: CGFloat
        let lengthSquared: CGFloat

        init?(from start: CGPoint, to end: CGPoint) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return nil }
            self.start = start
            self.dx = dx
            self.dy = dy
            self.lengthSquared = lengthSquared
        }

        func closestPoint(to point: CGPoint) -> CGPoint {
            let dot = (point.x - start.x) * dx + (point.y - start.y) * dy
            let fraction = min(1, max(0, dot / lengthSquared))
            return CGPoint(x: start.x + fraction * dx, y: start.y + fraction * dy)
        }
    }

    private let segments: [Segment]

    init(_ path: CGPath) {
        var segments: [Segment] = []
        var start = CGPoint.zero
        var previous = CGPoint.zero
        path.flattened(threshold: 0.025).applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                start = element.pointee.points[0]
                previous = start
                return
            case .addLineToPoint, .closeSubpath:
                let end = element.pointee.type == .closeSubpath ? start : element.pointee.points[0]
                if let segment = Segment(from: previous, to: end) { segments.append(segment) }
                previous = end
            default:
                return
            }
        }
        self.segments = segments
    }

    func closestPoint(to point: CGPoint) -> CGPoint {
        var closest = point
        var distance = CGFloat.infinity
        for segment in segments {
            let candidate = segment.closestPoint(to: point)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let squared = dx * dx + dy * dy
            if squared < distance {
                distance = squared
                closest = candidate
            }
        }
        return closest
    }
}
