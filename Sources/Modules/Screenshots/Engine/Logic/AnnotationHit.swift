import CoreGraphics

/// What a press lands on: a pure function of the layers and a point, so the rule is a
/// case that can be asked without a window.
///
/// **A stroked shape is hit by its outline and a filled one by its area**, both with a few
/// points of tolerance: a line two points wide is not a target a pointer can be asked to
/// hit. An unfilled rectangle is its edge and not its inside — a click in the middle of
/// one is a click on the picture under it — and the arrow, which is always a solid, is its
/// whole body. A blur has no outline to hit: it is a box of picture and is taken by its area.
enum AnnotationHit {
    /// How far from a stroke's edge a press still lands on it, in points.
    static let tolerance: CGFloat = 4
    /// How far from a handle's centre a press still takes it, in points.
    static let handleRadius: CGFloat = 7

    /// Whether a press inside the shape lands on it, and not only on its edge: a solid, and the blur, which draws a whole box.
    static func takesByArea(_ annotation: Annotation) -> Bool { annotation.isFilled || annotation.tool == .blur }

    /// Whether `point` is on `annotation`.
    static func hits(_ annotation: Annotation, at point: CGPoint, tolerance: CGFloat = tolerance) -> Bool {
        guard point.x.isFinite, point.y.isFinite, annotation.isUsable else { return false }
        let stroke = annotation.stroke
        // The band the tolerance adds is on both sides of the line, so half of it each.
        let reach = (stroke?.width ?? 0) / 2 + tolerance
        guard annotation.frame.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        let outline = annotation.outline
        if takesByArea(annotation), outline.contains(point) { return true }
        return outline.copy(strokingWithWidth: reach * 2, lineCap: stroke?.cap ?? .round, lineJoin: .round,
                            miterLimit: 10).contains(point)
    }

    /// The id of the topmost layer under `point`: the list is in drawing order, so the last one wins.
    static func topmost(in layers: [Annotation], at point: CGPoint) -> Annotation.ID? {
        layers.last { hits($0, at: point) }?.id
    }

    /// The handle of `annotation` nearest to `point`, within `handleRadius`.
    static func handle(of annotation: Annotation, at point: CGPoint) -> AnnotationHandle? {
        annotation.handles
            .map { (handle: $0.handle, distance: hypot($0.point.x - point.x, $0.point.y - point.y)) }
            .filter { $0.distance <= handleRadius }
            .min { $0.distance < $1.distance }?.handle
    }
}
