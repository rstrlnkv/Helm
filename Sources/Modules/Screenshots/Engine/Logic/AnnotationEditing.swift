import CoreGraphics

/// What Esc or a right click means while there is something to lose.
public enum EscapeOutcome: Sendable, Equatable {
    case close
    /// The first press with layers on the picture: ask again before closing.
    case armed
    /// An object was selected: the press let go of it and asked nothing.
    case deselected
    /// A drawing under the pointer was dropped: the press did only that and asked nothing.
    case dropped
}

/// The layers on one selection, the one being drawn, and the one selected.
///
/// A value like `SelectionDrag`: every rule is a function of what was done, and
/// none of it reads a keyboard or a clock.
///
/// **Undo is a list of snapshots of the layer list**, so an edit in place — a move, a
/// resize, a recolour, a delete — is a step like a new layer is, and every layer keeps its
/// `id` through all of them. A drag is one step: the list before it is what is kept, and
/// only when it differs from the list after.
public struct AnnotationEditing: Sendable {
    /// The travel, in points, under which a press that ends is a click and not a drawing.
    public static let clickTravel: CGFloat = 3
    /// How many steps undo (and redo) keep. A step is a whole list of layers, and a move of a
    /// full pencil copies its points: at about 16 KB a pencil, 200 steps over a dozen of them stay
    /// in the low megabytes, and nobody walks back further than that in one picture. The oldest goes.
    public static let historyLimit = 200

    /// Where a layer may be: the selection, in display-local points.
    public let bounds: CGRect
    public private(set) var layers: [Annotation] = []
    /// The layer under the pointer; not a layer until `end`.
    public private(set) var draft: Annotation?
    /// The object the edits are for, by id; nil is none.
    public private(set) var selectedID: Annotation.ID?
    /// The lists undo walks back to, oldest first, and the ones redo walks forward to, nearest last.
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []
    private var nextID: Annotation.ID = 1
    /// A move or a resize in progress: the object as it was when the press took it and the list
    /// the step will go back to.
    private var gesture: (kind: Gesture, base: Annotation, before: [Annotation])?
    private enum Gesture { case move(from: CGPoint), resize(AnnotationHandle) }
    /// Where the press that began the draft landed, as read, and how far the pointer has been from it.
    private var pressed: (point: CGPoint, travel: CGFloat)?
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

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public var selected: Annotation? { layers.first { $0.id == selectedID } }

    /// A draft or a move or a resize is under the pointer.
    public var isBusy: Bool { draft != nil || gesture != nil }

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

    /// `style` is what the object is drawn with from now to the end of it: a colour picked
    /// during the drag belongs to the next object.
    public mutating func begin(_ tool: AnnotationTool, at point: CGPoint, style: AnnotationStyle = .standard) {
        disarm()
        guard let clamped = clamp(point) else { return }
        pointer = clamped
        pressed = (point, 0)
        gap = Annotation.pencilGap
        let freehand = tool == .pencil || tool == .highlighter
        trail = freehand ? [clamped] : []
        draft = Annotation(tool: tool, start: clamped, end: clamped, points: trail, style: style, id: nextID)
        nextID += 1
    }

    /// The press of the editor, whatever the tool: what it lands on decides what it begins.
    /// A handle of the selected object takes it first, tool or none; with a tool the press
    /// begins a drawing, and if it never travels `clickTravel` it is a click on whatever is
    /// under it (`end`); with none it takes the object under it, the selected one first, to
    /// move it, and a press on nothing lets go of the selection. False is a press that is
    /// none of these — no tool and nothing on the picture — for the caller to make its own.
    /// A press outside the selection takes nothing and, with a tool, draws from the edge.
    public mutating func press(at point: CGPoint, tool: AnnotationTool?, style: AnnotationStyle = .standard) -> Bool {
        disarm()
        guard point.x.isFinite, point.y.isFinite else { return true }
        // No release is guaranteed: a press that finds an edit still open ends it as released at
        // its last point, and only then starts its own.
        if isBusy { end() }
        if let current = selected, let handle = AnnotationHit.handle(of: current, at: point) {
            gesture = (.resize(handle), current, layers)
            return true
        }
        if let tool {
            begin(tool, at: point, style: style)
            return true
        }
        guard !layers.isEmpty else { return false }
        let own = selected.flatMap { AnnotationHit.hits($0, at: point) ? $0.id : nil }
        selectedID = own ?? AnnotationHit.topmost(in: layers, at: point)
        if let current = selected { gesture = (.move(from: point), current, layers) }
        return true
    }

    /// `shift` is the flag of **this** event, never one kept from the press: no release
    /// is guaranteed, so a kept flag could square every later shape.
    public mutating func drag(to point: CGPoint, shift: Bool) {
        guard let point = clamp(point) else { return }
        if let gesture {
            pointer = point
            let changed: Annotation?
            switch gesture.kind {
            case .move(let from):
                changed = gesture.base.translated(by: CGPoint(x: point.x - from.x, y: point.y - from.y), within: bounds)
            case .resize(let handle):
                // A result with nothing to draw is not taken: the object keeps the last one that had.
                changed = gesture.base.resized(handle, to: point).flatMap { $0.isUsable ? $0 : nil }
            }
            if let changed, let index = layers.firstIndex(where: { $0.id == changed.id }) { layers[index] = changed }
            return
        }
        guard let current = draft else { return }
        pointer = point
        if let first = pressed { pressed = (first.point, max(first.travel, hypot(point.x - first.point.x, point.y - first.point.y))) }
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
                draft = Annotation(tool: .highlighter, start: current.start, end: end, points: [current.start, end],
                                   style: current.style, id: current.id)
            } else {
                draft = Annotation(tool: current.tool, start: current.start, end: pointer, points: points,
                                   style: current.style, id: current.id)
            }
            return
        }
        let wanted = Annotation.constrained(current.tool, from: current.start, to: pointer, shift: shift, within: bounds)
        draft = Annotation(tool: current.tool, start: current.start, end: fit(wanted, from: current.start),
                           style: current.style, id: current.id)
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

    /// One step on the way back: the list as it was, and no future.
    private mutating func record(_ before: [Annotation]) {
        Self.keep(before, in: &past)
        future.removeAll()
    }

    /// `list` on top of `stack`, which never holds more than `historyLimit`: the oldest goes.
    private static func keep(_ list: [Annotation], in stack: inout [[Annotation]]) {
        stack.append(list)
        if stack.count > historyLimit { stack.removeFirst(stack.count - historyLimit) }
    }

    /// Release. A move or a resize ends as one step if it changed anything. A draft that
    /// travelled `clickTravel` becomes a layer if there is anything in it, and a new layer
    /// clears what could have been redone; one that did not is a click, which takes the
    /// layer under it or lets go of the selection and draws nothing.
    public mutating func end() {
        if let gesture {
            self.gesture = nil
            if layers != gesture.before { record(gesture.before) }
            return
        }
        defer { draft = nil; pressed = nil }
        guard let draft else { return }
        guard let first = pressed, first.travel >= Self.clickTravel else {
            selectedID = pressed.flatMap { AnnotationHit.topmost(in: layers, at: $0.point) }
            return
        }
        guard draft.isUsable else { return }
        record(layers)
        layers.append(draft)
        selectedID = nil
    }

    /// `undo` and `redo` move a step between the stacks through `keep` as belt and braces:
    /// only `record` adds to past and future together, so the ceiling holds without it here.
    public mutating func undo() {
        disarm()
        guard gesture == nil, let previous = past.popLast() else { return }
        Self.keep(layers, in: &future)
        layers = previous
        keepSelection()
    }

    public mutating func redo() {
        disarm()
        guard gesture == nil, let next = future.popLast() else { return }
        Self.keep(layers, in: &past)
        layers = next
        keepSelection()
    }

    /// A selected object that the list no longer has is no longer selected.
    private mutating func keepSelection() {
        if selected == nil { selectedID = nil }
    }

    /// Edits of the selected object, each one step; one that changes nothing is none.
    private mutating func editSelected(_ change: (Annotation) -> Annotation) {
        disarm()
        guard gesture == nil, let current = selected, let index = layers.firstIndex(of: current) else { return }
        let changed = change(current)
        guard !changed.looksLike(current) else { return }
        record(layers)
        layers[index] = changed
    }

    public mutating func recolor(_ color: AnnotationColor) {
        editSelected { var style = $0.style; style.color = color; return $0.restyled(style) }
    }

    public mutating func setThickness(_ step: AnnotationThickness) {
        editSelected { var style = $0.style; style.thickness = step; return $0.restyled(style) }
    }

    /// Only the boxes are filled or not; the other tools have no such choice.
    public mutating func setFilled(_ filled: Bool) {
        editSelected {
            guard $0.tool == .rectangle || $0.tool == .ellipse else { return $0 }
            var style = $0.style; style.filled = filled; return $0.restyled(style)
        }
    }

    public mutating func deleteSelected() {
        disarm()
        guard gesture == nil, let current = selected else { return }
        record(layers)
        layers.removeAll { $0.id == current.id }
        selectedID = nil
    }

    /// Esc and a right click, one door. A selected object is let go of first and nothing is
    /// asked. Then, with nothing on the picture it closes at once; with layers the first
    /// press arms and a second closes, however late; any other input in between withdraws
    /// the question. Undoing back to empty is the first case again.
    ///
    /// A move or a resize still open is **cancelled** first, the object back as the press took it
    /// and no step recorded: Esc is the way out of what is being done, and nothing the person
    /// has not let go of is kept. A drawing still under the pointer is dropped the same way,
    /// and that press does only that: it neither asks nor closes.
    public mutating func escape() -> EscapeOutcome {
        if draft != nil { draft = nil; pressed = nil; return .dropped }
        if let gesture { layers = gesture.before; self.gesture = nil }
        if selectedID != nil { selectedID = nil; return .deselected }
        if layers.isEmpty || armed { return .close }
        armed = true
        return .armed
    }
}
