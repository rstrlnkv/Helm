import CoreGraphics

/// A mask's corner as the pointer correction needs it: the visible region, and the boundary of it.
struct CornerGeometry {
    let size: CGFloat
    let corner: CornerPosition
    let visible: CGPath
    /// Nil for a mask that never holds the pointer.
    let boundary: CursorBoundary?

    init(size: CGFloat, radius: CGFloat, corner: CornerPosition, constrainsCursor: Bool) {
        self.size = size
        self.corner = corner
        visible = CornerPath.visible(size: size, radius: radius, corner: corner)
        boundary = constrainsCursor ? CursorBoundary(visible) : nil
    }

    /// Where the mask layer scales around: the physical corner of the display.
    var anchor: CGPoint { CGPoint(x: corner.isRight ? size : 0, y: corner.isTop ? size : 0) }
}

/// The pointer on a mask, pushed back to the visible curve. Ported from the standalone app's
/// `cursorCorrection`; the mask's presentation is passed in, so this reads no layer.
enum CursorCorrection {
    struct Result: Equatable {
        let position: CGPoint
        let remainder: CGPoint
    }

    /// `local` is the pointer in the mask view's coordinates (y up). Nil when the pointer is not on the
    /// mask, the mask is not at rest or not shielded yet, or no whole-point position is visible.
    static func correct(local point: CGPoint, remainder: CGPoint, geometry: CornerGeometry,
                        presentation: MaskPresentation) -> Result? {
        guard let boundary = geometry.boundary, presentation.ready else { return nil }
        let scale = presentation.scale
        guard presentation.opacity > 0, scale.isFinite, scale > 0.001,
              point.x.isFinite, point.y.isFinite, remainder.x.isFinite, remainder.y.isFinite else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: geometry.size, height: geometry.size)
        let anchor = geometry.anchor
        func unscale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: anchor.x + (p.x - anchor.x) / scale, y: anchor.y + (p.y - anchor.y) / scale)
        }
        let local = unscale(point)
        // Quartz's bounds are top-inclusive and bottom-exclusive.
        let hitPoint = CGPoint(x: local.x, y: bounds.maxY - local.y)
        guard bounds.contains(hitPoint), !geometry.visible.contains(local) else { return nil }

        let attempted = unscale(CGPoint(x: point.x + remainder.x, y: point.y + remainder.y))
        let onBoundary = geometry.visible.contains(attempted) ? attempted : boundary.closestPoint(to: attempted)
        let projected = CGPoint(x: anchor.x + (onBoundary.x - anchor.x) * scale,
                                y: anchor.y + (onBoundary.y - anchor.y) * scale)
        guard projected.x.isFinite, projected.y.isFinite else { return nil }

        // Quartz warps to whole points: the closest visible grid point, the fraction kept so slow
        // movement along the curve adds up.
        let gridX = projected.x.rounded()
        let gridY = projected.y.rounded()
        var nearest: CGPoint?
        var distance = CGFloat.infinity
        for x in -1...1 {
            for y in -1...1 {
                let candidate = CGPoint(x: gridX + CGFloat(x), y: gridY + CGFloat(y))
                let insideVerticalEdge = anchor.y == 0 ? candidate.y > 0 : candidate.y <= bounds.maxY
                let insideDisplay = insideVerticalEdge && candidate.x >= 0 &&
                    (anchor.x == 0 || candidate.x < bounds.maxX)
                guard insideDisplay, geometry.visible.contains(unscale(candidate)) else { continue }
                let deltaX = candidate.x - projected.x
                let deltaY = candidate.y - projected.y
                let squared = deltaX * deltaX + deltaY * deltaY
                if squared < distance {
                    distance = squared
                    nearest = candidate
                }
            }
        }
        guard let nearest else { return nil }
        return Result(position: nearest, remainder: CGPoint(x: projected.x - nearest.x, y: projected.y - nearest.y))
    }
}

/// Where the pointer was last put, and which window put it there.
struct CursorContact: Equatable {
    let window: Int
    let position: CGPoint
    let remainder: CGPoint

    func isNear(_ point: CGPoint) -> Bool {
        // Between corrections, real motion can cross the gap from the rounded warp position to the
        // curve in several small steps.
        abs(point.x - position.x) <= 2 && abs(point.y - position.y) <= 2
    }
}
