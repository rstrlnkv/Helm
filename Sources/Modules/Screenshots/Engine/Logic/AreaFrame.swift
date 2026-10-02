import CoreGraphics
import HelmRuntime

/// The eight places an edited area is held: the four corners and the middle of each edge.
public enum AreaHandle: CaseIterable, Sendable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// The finished area as something to take hold of: where its handles stand, which one a press
/// reaches, and what the area becomes when one is dragged or a key moves it. Pure functions of
/// the rectangle and the display's bounds, in display-local top-left points, so every edge of
/// the screen and a selection too small to hold eight handles are cases that can be asked
/// without a window.
///
/// **The area is not a layer.** Nothing here touches the layers: they keep their display-local
/// coordinates while the area changes under them, and what falls outside is clipped by the
/// geometry the screen and the export already clip with.
public enum AreaFrame {
    /// How far from a handle's centre a press still takes it, in points.
    public static let reach: CGFloat = 7

    /// The reach on `rect`: the full reach, or a third of its shorter side when that is less, so the
    /// middle of a small area is still the area's and a press there is a drawing and not a grab. A
    /// very small one is moved with the arrow keys, or begun again where there is no tool and no layer.
    public static func reach(on rect: CGRect) -> CGFloat {
        min(reach, max(0, min(rect.width, rect.height) / 3))
    }

    /// The radius of the dot drawn at a handle, in points: the same number the overlay draws with.
    public static let dotRadius: CGFloat = 4.5

    /// Whether `rect` is wide and tall enough, three dot diameters each way, to offer the middle of
    /// its edges as well as its corners. A smaller one is held by its four corners only, under the press; the screen draws no dot on one under three points (`dotRadius` against `reach(on:)`), though the press still takes it within the reach.
    public static func offersMidpoints(on rect: CGRect) -> Bool {
        min(rect.width, rect.height) >= 6 * dotRadius
    }

    /// The handles taken on `rect` (the screen draws them when the reach is at least a point): all eight, or the four corners of a tiny area.
    public static func offered(on rect: CGRect) -> [(handle: AreaHandle, point: CGPoint)] {
        let corners: Set<AreaHandle> = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        return handles(of: rect).filter { offersMidpoints(on: rect) || corners.contains($0.handle) }
    }

    public static func handles(of rect: CGRect) -> [(handle: AreaHandle, point: CGPoint)] {
        [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)), (.top, CGPoint(x: rect.midX, y: rect.minY)),
         (.topRight, CGPoint(x: rect.maxX, y: rect.minY)), (.right, CGPoint(x: rect.maxX, y: rect.midY)),
         (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)), (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
         (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.left, CGPoint(x: rect.minX, y: rect.midY))]
    }

    /// The handle of `rect` nearest to `point` within the reach; nil for none. **An object's handle
    /// wins an overlap**: when `object` has a handle within its own reach of `point`, the area has
    /// none there, because the press belongs to the thing the person has just selected.
    public static func handle(of rect: CGRect, at point: CGPoint, yieldingTo object: Annotation? = nil) -> AreaHandle? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        if let object, AnnotationHit.handle(of: object, at: point) != nil { return nil }
        let within = reach(on: rect)
        return offered(on: rect)
            .map { (handle: $0.handle, distance: hypot($0.point.x - point.x, $0.point.y - point.y)) }
            .filter { $0.distance <= within }
            .min { $0.distance < $1.distance }?.handle
    }

    /// `base` with `handle` taken along with the pointer, which pressed at `press` and is now at
    /// `pointer`: the edge or the corner follows by the pointer's own travel, so the area does not
    /// jump by the few points between the press and the handle's centre. The result stays inside
    /// `bounds`, a drag past the opposite side mirrors the area, and a result under one point in
    /// either direction is nil, for the caller to keep the last one it had.
    public static func resized(_ base: CGRect, _ handle: AreaHandle, from press: CGPoint, to pointer: CGPoint,
                               within bounds: CGRect) -> CGRect? {
        guard press.x.isFinite, press.y.isFinite, pointer.x.isFinite, pointer.y.isFinite,
              let held = handles(of: base).first(where: { $0.handle == handle })?.point else { return nil }
        let x = (held.x + pointer.x - press.x).clamped(to: bounds.minX...bounds.maxX, whenNotANumber: bounds.minX)
        let y = (held.y + pointer.y - press.y).clamped(to: bounds.minY...bounds.maxY, whenNotANumber: bounds.minY)
        var (left, right, top, bottom) = (base.minX, base.maxX, base.minY, base.maxY)
        switch handle {
        case .topLeft: (left, top) = (x, y)
        case .top: top = y
        case .topRight: (right, top) = (x, y)
        case .right: right = x
        case .bottomRight: (right, bottom) = (x, y)
        case .bottom: bottom = y
        case .bottomLeft: (left, bottom) = (x, y)
        case .left: left = x
        }
        let result = CGRect(x: min(left, right), y: min(top, bottom), width: abs(right - left), height: abs(bottom - top))
        return result.width >= 1 && result.height >= 1 ? result : nil
    }

    /// `rect` carried by `delta`, the step shortened per axis where it meets an edge of `bounds`,
    /// so an area against a wall keeps the size it had.
    public static func nudged(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        let dx = delta.x.clamped(to: (bounds.minX - rect.minX)...max(bounds.minX - rect.minX, bounds.maxX - rect.maxX),
                                 whenNotANumber: 0)
        let dy = delta.y.clamped(to: (bounds.minY - rect.minY)...max(bounds.minY - rect.minY, bounds.maxY - rect.maxY),
                                 whenNotANumber: 0)
        return rect.offsetBy(dx: dx, dy: dy)
    }

    /// One arrow press in points: `pixels` of the display's own pixels along `direction` (each of
    /// its components -1, 0 or 1), at `scale` pixels to the point. A scale that is not a positive
    /// number moves nothing.
    public static func step(_ direction: CGPoint, pixels: Int, scale: CGFloat) -> CGPoint {
        guard scale.isFinite, scale > 0 else { return .zero }
        return CGPoint(x: direction.x * CGFloat(pixels) / scale, y: direction.y * CGFloat(pixels) / scale)
    }
}
