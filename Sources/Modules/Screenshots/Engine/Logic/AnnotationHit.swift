import CoreGraphics

/// What a press lands on: a pure function of the layers and a point, so the rule is a
/// case that can be asked without a window.
///
/// **A stroked shape is hit by its outline and a filled one by its area**, both with a few
/// points of tolerance: a line two points wide is not a target a pointer can be asked to
/// hit. An unfilled rectangle is its edge and not its inside — a click in the middle of
/// one is a click on the picture under it — and the arrow, which is always a solid, is its
/// whole body. A blur has no outline to hit: it is a box of picture and is taken by its area; so is a text, whose line is a box of ink with gaps in it.
enum AnnotationHit {
    /// How far from a stroke's edge a press still lands on it, in points.
    static let tolerance: CGFloat = 4
    /// How far from a handle's centre a press still takes it, in points.
    static let handleRadius: CGFloat = 7

    /// Whether a press inside the shape lands on it, and not only on its edge: a solid, the blur, which draws a whole box, and the text, whose click between two letters is on the text.
    static func takesByArea(_ annotation: Annotation) -> Bool { annotation.isFilled || annotation.tool == .blur || annotation.tool == .text }

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

    /// What a press with no tool takes: `topmost`, and where it finds nothing, the last spotlight whose box the point is inside. A spotlight is taken by its
    /// edge like a rectangle and, here only, by its inside as well, **below** every other layer: a mark drawn over the bright part is taken first.
    /// The eraser and a tool's press read `hits` alone.
    static func selectable(in layers: [Annotation], at point: CGPoint) -> Annotation.ID? {
        topmost(in: layers, at: point) ?? layers.last { $0.tool == .spotlight && $0.isUsable && $0.outline.contains(point) }?.id
    }

    /// The ids of the layers an eraser's circle of `radius` meets along `path`, in the list's order: the rule is that of `hits`,
    /// the one a click selects by, with the radius as its tolerance, written again in `reached` so as to be built once per
    /// layer and not per sample; a test sweeps the two against each other, for layers wholly inside the area only, and a layer
    /// across the area's edge is read by the rule of `reached` alone. The path is walked in steps of a quarter of the radius, at least half a point and at most
    /// `maxSteps` to a segment, and a point that is not a number is skipped. With `area`, a point farther from it than the
    /// radius is skipped too: the circle is not over the picture there. A radius that is not a positive number meets nothing.
    static func touched(by path: [CGPoint], radius: CGFloat, in layers: [Annotation], within area: CGRect? = nil) -> [Annotation.ID] {
        guard radius.isFinite, radius > 0 else { return [] }
        let step = max(radius / 4, 0.5)
        let reach = area?.insetBy(dx: -radius, dy: -radius)
        var samples: [CGPoint] = []
        for (index, point) in path.enumerated() where point.x.isFinite && point.y.isFinite {
            samples.append(point)
            guard index > 0, path[index - 1].x.isFinite, path[index - 1].y.isFinite else { continue }
            let from = path[index - 1]
            let count = Int(min((hypot(point.x - from.x, point.y - from.y) / step).rounded(.up), maxSteps))
            for part in stride(from: 1, to: count, by: 1) {
                let along = CGFloat(part) / CGFloat(count)
                samples.append(CGPoint(x: from.x + (point.x - from.x) * along, y: from.y + (point.y - from.y) * along))
            }
        }
        samples = samples.filter { reach?.contains($0) ?? true }
        guard let first = samples.first else { return [] }
        // The box of the samples: a layer whose reach, once, misses it is not asked about any one of them.
        let box = samples.reduce((minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) {
            (min($0.minX, $1.x), min($0.minY, $1.y), max($0.maxX, $1.x), max($0.maxY, $1.y))
        }
        return layers.filter { layer in
            guard layer.isUsable else { return false }
            let frame = layer.frame, reach = (layer.stroke?.width ?? 0) / 2 + radius
            guard frame.minX - reach <= box.maxX, box.minX <= frame.maxX + reach,
                  frame.minY - reach <= box.maxY, box.minY <= frame.maxY + reach else { return false }
            // The same box `hits` asks first, whose far edges are outside it, so the two never differ on an edge.
            let grown = frame.insetBy(dx: -reach, dy: -reach)
            return reached(by: layer, frame: frame, radius: radius, within: area).contains { region in
                samples.contains { grown.contains($0) && region.contains($0) }
            }
        }.map(\.id)
    }

    /// The regions a circle of `radius` has its centre in when it meets `layer`: the area of a solid and the outline's
    /// band, as `hits` reads them, built once for all the samples. With `area`, where the layer crosses its edge, the
    /// layer is first cut to the area, and the regions are what is within `radius` of the part that is left: a circle
    /// that reaches only the part the area does not show meets nothing.
    private static func reached(by layer: Annotation, frame: CGRect, radius: CGFloat, within area: CGRect?) -> [CGPath] {
        let outline = layer.outline
        let stroke = layer.stroke
        let reach = (stroke?.width ?? 0) / 2 + radius
        let cap = stroke?.cap ?? .round
        let inside = area.map { $0.insetBy(dx: reach, dy: reach).contains(frame) } ?? true
        if inside {
            let band = outline.copy(strokingWithWidth: reach * 2, lineCap: cap, lineJoin: .round, miterLimit: 10)
            return takesByArea(layer) ? [outline, band] : [band]
        }
        guard let area, !frame.intersection(area).isNull else { return [] }
        let body = stroke.map { outline.copy(strokingWithWidth: $0.width, lineCap: cap, lineJoin: $0.join, miterLimit: 10) } ?? outline
        let shown = body.intersection(CGPath(rect: area, transform: nil))
        guard !shown.isEmpty else { return [] }
        return [shown, shown.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)]
    }

    /// How many steps one segment of an eraser's path is cut into at most: a drag longer than that is a jump of
    /// thousands of points, and the steps it has are then longer than a quarter of the radius.
    static let maxSteps: CGFloat = 20_000

    /// The handle of `annotation` nearest to `point`, within `handleRadius`.
    static func handle(of annotation: Annotation, at point: CGPoint) -> AnnotationHandle? {
        annotation.handles
            .map { (handle: $0.handle, distance: hypot($0.point.x - point.x, $0.point.y - point.y)) }
            .filter { $0.distance <= handleRadius }
            .min { $0.distance < $1.distance }?.handle
    }
}
