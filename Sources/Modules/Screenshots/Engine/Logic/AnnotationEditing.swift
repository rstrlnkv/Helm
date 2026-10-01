import CoreGraphics

/// What Esc or a right click means while there is something to lose.
public enum EscapeOutcome: Sendable, Equatable {
    case close
    /// The first press with layers on the picture: ask again before closing.
    case armed
}

/// The layers on one selection, and the one being drawn.
///
/// A value like `SelectionDrag`: every rule is a function of what was done, and
/// none of it reads a keyboard or a clock.
public struct AnnotationEditing: Sendable {
    /// Where a layer may be: the selection, in display-local points.
    public let bounds: CGRect
    public private(set) var layers: [Annotation] = []
    /// The layer under the pointer; not a layer until `end`.
    public private(set) var draft: Annotation?
    /// Taken back and not yet forgotten; the next new layer forgets them.
    private var undone: [Annotation] = []
    /// Whether the first Esc has been pressed and nothing else has happened since.
    /// The question has no time limit: only another input withdraws it.
    private var armed = false
    /// The pointer as last read, inside the selection and before ⇧ shaped it, so a
    /// change of ⇧ with the pointer still can re-shape the draft.
    private var pointer: CGPoint?
    /// The freehand points kept so far, the press first; the pointer is the tip after them.
    private var trail: [CGPoint] = []
    /// The spacing a point must keep from the last kept one; it doubles each time the trail is thinned.
    private var gap = Annotation.pencilGap

    public init(bounds: CGRect) { self.bounds = bounds }

    public var canUndo: Bool { !layers.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    /// Whether the plate should be up.
    public var isArmed: Bool { armed }

    /// Any input that is not Esc: the question is withdrawn.
    public mutating func disarm() { armed = false }

    /// A point that is not a number is dropped, and one outside the selection is
    /// taken to its edge. Nil for the first kind.
    private func clamp(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    public mutating func begin(_ tool: AnnotationTool, at point: CGPoint) {
        disarm()
        guard let point = clamp(point) else { return }
        pointer = point
        gap = Annotation.pencilGap
        let freehand = tool == .pencil || tool == .highlighter
        trail = freehand ? [point] : []
        draft = Annotation(tool: tool, start: point, end: point, points: trail)
    }

    /// `shift` is the flag of **this** event, never one kept from the press: no release
    /// is guaranteed, so a kept flag could square every later shape.
    public mutating func drag(to point: CGPoint, shift: Bool) {
        guard let current = draft, let point = clamp(point) else { return }
        pointer = point
        reshape(current, shift: shift)
    }

    /// ⇧ went down or up with the pointer where it was.
    public mutating func modifiersChanged(shift: Bool) {
        guard let current = draft, let pointer else { return }
        reshape(current, shift: shift)
    }

    private mutating func reshape(_ current: Annotation, shift: Bool) {
        guard let pointer else { return }
        if current.tool == .pencil || current.tool == .highlighter {
            commit(pointer)
            // The tip is the pointer and is never kept as a point of the trail until it is
            // a full spacing from the last kept one, so a slow drag still adds points.
            var points = trail
            if points.last != pointer { points.append(pointer) }
            if shift, current.tool == .highlighter {
                let end = fit(Annotation.constrained(.highlighter, from: current.start, to: pointer, shift: true), from: current.start)
                draft = Annotation(tool: .highlighter, start: current.start, end: end, points: [current.start, end])
            } else {
                draft = Annotation(tool: current.tool, start: current.start, end: pointer, points: points)
            }
            return
        }
        let wanted = Annotation.constrained(current.tool, from: current.start, to: pointer, shift: shift, within: bounds)
        draft = Annotation(tool: current.tool, start: current.start, end: fit(wanted, from: current.start))
    }

    /// Keeps `point` in the trail when it is a full spacing from the last kept one. At
    /// the cap every other point goes, the first and the last stay, and the spacing
    /// doubles, so a long drag keeps its shape in a bounded list.
    private mutating func commit(_ point: CGPoint) {
        guard let last = trail.last, hypot(point.x - last.x, point.y - last.y) >= gap else { return }
        trail.append(point)
        if trail.count >= Annotation.maxPoints {
            trail = trail.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trail.count - 1 }.map(\.element)
            gap *= 2
        }
    }

    /// The end shortened along its own direction until it is inside the selection,
    /// so a square or a snapped line keeps its shape at the edge. The scaling is
    /// inexact on the last bit, so the result is then clamped to the selection.
    private func fit(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        var scale: CGFloat = 1
        for (from, to, low, high) in [(start.x, end.x, bounds.minX, bounds.maxX), (start.y, end.y, bounds.minY, bounds.maxY)] {
            if to > high, to > from { scale = min(scale, (high - from) / (to - from)) }
            if to < low, to < from { scale = min(scale, (low - from) / (to - from)) }
        }
        let x = start.x + (end.x - start.x) * scale, y = start.y + (end.y - start.y) * scale
        return CGPoint(x: min(max(x, bounds.minX), bounds.maxX), y: min(max(y, bounds.minY), bounds.maxY))
    }

    /// Release: the draft becomes a layer if there is anything in it, and a new
    /// layer clears what could have been redone.
    public mutating func end() {
        defer { draft = nil }
        guard let draft, draft.isUsable else { return }
        layers.append(draft)
        undone.removeAll()
    }

    public mutating func undo() {
        disarm()
        if let last = layers.popLast() { undone.append(last) }
    }

    public mutating func redo() {
        disarm()
        if let next = undone.popLast() { layers.append(next) }
    }

    /// Esc and a right click, one door. With nothing on the picture it closes at
    /// once; with layers the first press arms and a second closes, however
    /// late; any other input in between withdraws the question. Undoing back to empty is the first case again.
    public mutating func escape() -> EscapeOutcome {
        if layers.isEmpty || armed { return .close }
        armed = true
        return .armed
    }
}
