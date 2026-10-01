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
        draft = Annotation(tool: tool, start: point, end: point)
    }

    public mutating func drag(to point: CGPoint) {
        guard let current = draft, let point = clamp(point) else { return }
        draft = Annotation(tool: current.tool, start: current.start, end: point)
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
