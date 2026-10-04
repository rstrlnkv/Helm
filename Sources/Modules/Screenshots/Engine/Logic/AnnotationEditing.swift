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
    static let clickTravel: CGFloat = 3
    /// How many steps undo (and redo) keep. A step is a whole list of layers, and a move of a
    /// full pencil copies its points: a pencil of `Annotation.maxPoints` points is 16 KB of `CGPoint`s
    /// by arithmetic, so 200 steps over a dozen of them come to a few tens of megabytes at the very
    /// most (an estimate, not a measurement), and nobody walks back further than that in one
    /// picture. The oldest goes.
    static let historyLimit = 200

    /// Where a layer may be: the selection, in display-local points. It changes only through
    /// `reshape(bounds:)`; the layers do not move with it.
    public private(set) var bounds: CGRect
    public private(set) var layers: [Annotation] = []
    /// The layer under the pointer; not a layer until `end`.
    public private(set) var draft: Annotation?
    /// The object the edits are for, by id; nil is none.
    private(set) var selectedID: Annotation.ID?
    /// The lists undo walks back to, oldest first, and the ones redo walks forward to, nearest last.
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []
    private var nextID: Annotation.ID = 1
    /// A move or a resize in progress: the object as it was when the press took it and the list
    /// the step will go back to.
    private var gesture: (kind: Gesture, base: Annotation, before: [Annotation])?
    private enum Gesture { case move(from: CGPoint), resize(AnnotationHandle) }
    /// An eraser's drag in progress: where the pointer was last, the radius of its circle, and the layers the circle has
    /// met so far, by id. The layers are not touched until the release; the path is not kept, only what it met.
    private var eraser: (last: CGPoint, radius: CGFloat, met: Set<Annotation.ID>)?
    /// Where the press that began the draft landed, as read, and how far the pointer has been from it.
    private var pressed: (point: CGPoint, travel: CGFloat)?
    /// An arrow press has moved the selected object and no other input has come since: the next
    /// press is the same step and not a new one, so a held key is one undo and not two hundred.
    private var nudging = false
    /// Whether the first Esc has been pressed and nothing else has happened since.
    /// The question has no time limit: only another input withdraws it.
    private var armed = false
    /// The pointer as last read, inside the selection and before ⇧ shaped it, so a
    /// change of ⇧ with the pointer still can re-shape the draft.
    private var pointer: CGPoint?
    /// The edge of the ruler that the freehand stroke under the pointer runs along; nil is a free stroke.
    private var guide: Ruler.Edge?
    /// The freehand points kept so far, the press first; the pointer is the tip after them.
    private var trail: [CGPoint] = []
    /// The spacing a point must keep from the last kept one; it doubles each time the trail is thinned.
    private var gap = Annotation.freehandGap

    public init(bounds: CGRect) { self.bounds = bounds }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public var selected: Annotation? { layers.first { $0.id == selectedID } }

    /// A draft or a move or a resize or an eraser's drag is under the pointer.
    public var isBusy: Bool { draft != nil || gesture != nil || eraser != nil }

    /// A move, a resize or an eraser's drag is open: the list is the one its step goes back to, so no other edit, undo or
    /// redo touches it until the release or the Esc.
    private var held: Bool { gesture != nil || eraser != nil }

    /// Whether the plate should be up.
    public var isArmed: Bool { armed }

    /// Any input that is not Esc: the question is withdrawn, and so is the open nudge, which only
    /// another arrow press continues.
    public mutating func disarm() { armed = false; nudging = false }

    /// A point that is not a number is dropped, and one outside the selection is
    /// taken to its edge. Nil for the first kind.
    private func clamp(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// `style` is what the object is drawn with from now to the end of it: a colour picked
    /// during the drag belongs to the next object.
    /// With a `ruler`, a stroke of the pen, the pencil or the marker that begins inside the selection and within
    /// `Ruler.reach` of its edge runs along it; the arrow and the shapes do not read it.
    mutating func begin(_ tool: AnnotationTool, at point: CGPoint, style: AnnotationStyle = .standard, ruler: Ruler? = nil) {
        disarm()
        guard let clamped = clamp(point) else { return }
        pointer = clamped
        pressed = (point, 0)
        gap = Annotation.freehandGap
        let freehand = tool.isFreehand
        // An edge counts where the area shows it: a press outside the area is read as the free stroke it is clamped to.
        let guided = freehand && bounds.contains(point) ? ruler : nil
        guide = guided?.edge(near: point)
        let start = guided?.snap(point).flatMap(clamp) ?? clamped
        trail = freehand ? [start] : []
        draft = Annotation(tool: tool, start: start, end: start, points: trail, style: style, id: nextID)
        nextID += 1
    }

    /// The press of the editor, whatever the tool: what it lands on decides what it begins.
    /// A handle of the selected object takes it first, tool or none; with a tool the press
    /// begins a drawing, and if it never travels `clickTravel` it is a click on whatever is
    /// under it (`end`); with none it takes the object under it, the selected one first, to
    /// move it, and a press on nothing lets go of the selection. False is a press that is
    /// none of these — no tool and nothing on the picture — for the caller to make its own.
    /// A press outside the selection takes nothing but an object's handle or edge that reaches
    /// out to it and, with a tool, draws from the edge.
    public mutating func press(at point: CGPoint, tool: AnnotationTool?, style: AnnotationStyle = .standard, ruler: Ruler? = nil) -> Bool {
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
            // A step is placed by the click and a click outside the area is none: begun there it would land on the area's edge.
            if tool == .step, !bounds.contains(point) { return true }
            begin(tool, at: point, style: style, ruler: ruler)
            return true
        }
        guard !layers.isEmpty else { return false }
        let own = selected.flatMap { AnnotationHit.hits($0, at: point) ? $0.id : nil }
        selectedID = own ?? AnnotationHit.selectable(in: layers, at: point)
        if let current = selected { gesture = (.move(from: point), current, layers) }
        return true
    }

    /// Whether a press at `point` lands on something already there: a handle of the selected object, or a layer. The
    /// text and Emoji tools ask it, since a press on one of those is the editor's own and only a press on bare picture starts a text.
    public func takes(at point: CGPoint) -> Bool {
        if let current = selected, AnnotationHit.handle(of: current, at: point) != nil { return true }
        return AnnotationHit.topmost(in: layers, at: point) != nil
    }

    /// The selected object is let go of, as a click on bare picture does; the text tool starts a field there and no
    /// press reaches `press`. Not a step.
    public mutating func deselect() {
        disarm()
        selectedID = nil
    }

    /// A text the person typed, put on the picture with its top-left at `point`: one undo step, and the one entry
    /// that cleans and bounds it: a tab or a break becomes a space, control characters go, blanks and invisible
    /// characters at either end are trimmed, a grapheme keeps `AnnotationText.maxScalarsPerGrapheme` scalars (the rest
    /// of them go, and a joiner the cut leaves at the end goes too), the first `AnnotationText.maxLength` graphemes stay
    /// (the rest are cut), and a cut grapheme that would fuse with the one before it is dropped, so the text kept
    /// always passes `AnnotationText.fits`. A text that draws no ink (`AnnotationText.hasInk`), a point that is not a number and an edit still under the pointer leave no layer and no step.
    /// True when a layer was added.
    @discardableResult
    public mutating func place(text: String, at point: CGPoint, style: AnnotationStyle = .standard) -> Bool {
        disarm()
        guard !held, draft == nil, let clamped = clamp(point) else { return false }
        let scalars = AnnotationText.oneLine(text).unicodeScalars.filter { $0.properties.generalCategory != .control }
        let leading = String(String.UnicodeScalarView(scalars)).drop { AnnotationText.isInvisible($0) }.prefix(AnnotationText.maxLength)
        let trimmed = leading.reversed().drop { AnnotationText.isInvisible($0) }.reversed()
        var kept = ""
        var count = 0
        for grapheme in trimmed {
            var scalars = grapheme.unicodeScalars.prefix(AnnotationText.maxScalarsPerGrapheme)
            while scalars.last?.value == 0x200D { scalars = scalars.dropLast() }
            let candidate = kept + String(String.UnicodeScalarView(scalars))
            // A piece that fuses with its neighbour is no grapheme of its own: it is dropped, not cut again.
            if !scalars.isEmpty, candidate.count == count + 1 { kept = candidate; count += 1 }
        }
        guard AnnotationText.fits(kept), AnnotationText.hasInk(kept) else { return false }
        let placed = Annotation(tool: .text, start: clamped, end: clamped, style: style, text: kept, id: nextID)
        guard placed.isUsable else { return false }
        nextID += 1
        record(layers)
        layers.append(placed)
        selectedID = nil
        return true
    }

    /// An emoji put on the picture with its middle at `point`, the frame held inside the selection: one undo step. Only one grapheme
    /// that leaves ink (`EmojiSet.isOne`) makes a layer; anything else, a point that is not a number and an edit still under the pointer leave none and no step.
    /// True when a layer was added.
    @discardableResult
    public mutating func place(emoji: String, at point: CGPoint, style: AnnotationStyle = .standard) -> Bool {
        disarm()
        guard !held, draft == nil, point.x.isFinite, point.y.isFinite, EmojiSet.isOne(emoji) else { return false }
        let size = AnnotationText.size(of: Annotation(tool: .emoji, start: .zero, end: .zero, style: style, text: emoji))
        let origin = CGPoint(x: min(max(point.x - size.width / 2, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                             y: min(max(point.y - size.height / 2, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
        let placed = Annotation(tool: .emoji, start: origin, end: origin, style: style, text: emoji, id: nextID)
        guard placed.isUsable else { return false }
        nextID += 1
        record(layers)
        layers.append(placed)
        selectedID = nil
        return true
    }

    /// The boxes `PersonalFinds` made, put on the picture as ordinary blur layers — each the person's to move or
    /// delete — **in one undo step** however many: the list is recorded once and a single undo takes them all. A box
    /// is kept to the area and one that is no longer a box there (nothing of it in the area, or under a point wide) is
    /// left out; each layer has its own step. Nothing else changes: no layer is touched and the selection is let
    /// go of. Returns how many layers went in; none is no step, and so is an edit under the pointer or a move
    /// still open, which the list belongs to.
    @discardableResult
    public mutating func insert(blurs placed: [RecognizedBoxes.Placed]) -> Int {
        disarm()
        guard !held, draft == nil else { return 0 }
        var added: [Annotation] = []
        for box in placed {
            guard [box.rect.minX, box.rect.minY, box.rect.width, box.rect.height].allSatisfy(\.isFinite) else { continue }
            let rect = box.rect.intersection(bounds)
            guard !rect.isNull else { continue }
            let layer = Annotation(tool: .blur, start: CGPoint(x: rect.minX, y: rect.minY),
                                   end: CGPoint(x: rect.maxX, y: rect.maxY),
                                   style: AnnotationStyle(thickness: box.step), id: nextID + added.count)
            if layer.isUsable { added.append(layer) }
        }
        guard !added.isEmpty else { return 0 }
        nextID += added.count
        record(layers)
        layers.append(contentsOf: added)
        selectedID = nil
        return added.count
    }

    /// `shift` is the flag of **this** event, never one kept from the press: no release
    /// is guaranteed, so a kept flag could square every later shape.
    public mutating func drag(to raw: CGPoint, shift: Bool) {
        if eraser != nil { eraseDrag(to: raw); return }
        guard let point = clamp(raw) else { return }
        if let gesture {
            pointer = point
            let changed: Annotation?
            switch gesture.kind {
            case .move(let from):
                // The delta is the pointer as the person moved it, not as the area clamps it: a
                // clamp may shorten a move, never reverse it, and an object the area was pulled
                // in past would otherwise jump toward the area while the pointer goes away.
                let moved = CGPoint(x: raw.x - from.x, y: raw.y - from.y)
                changed = gesture.base.translated(by: moved, within: bounds)
            case .resize(let handle):
                // A result with nothing to draw is not taken: the object keeps the last one that had.
                // A lens stays a circle inside the selection: its far corner is shortened along its own direction, as a drag's is.
                changed = gesture.base.resized(handle, to: point).map {
                    $0.tool == .magnifier ? Annotation(tool: .magnifier, start: $0.start, end: fit($0.end, from: $0.start), style: $0.style, id: $0.id) : $0
                }.flatMap { $0.isUsable ? $0 : nil }
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
        guard let current = draft, pointer != nil else { return }
        reshape(current, shift: shift)
    }

    private mutating func reshape(_ current: Annotation, shift: Bool) {
        guard let pointer else { return }
        if current.tool.isFreehand, let guide {
            // Along the ruler: the stroke is the straight run from where it began to the pointer's nearest point of the
            // edge, held in the area along its own direction, as ⇧ holds the marker's.
            let end = fit(guide.project(pointer), from: current.start)
            draft = Annotation(tool: current.tool, start: current.start, end: end, points: [current.start, end],
                               style: current.style, id: current.id)
            return
        }
        if current.tool.isFreehand {
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
        if current.tool == .step {
            // The circle is under the pointer until the release, wherever the press was.
            draft = Annotation(tool: .step, start: pointer, end: pointer, style: current.style, id: current.id)
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
    /// layer under it or lets go of the selection and draws nothing; a step is placed by a click as well.
    public mutating func end() {
        if eraser != nil { endErase(); return }
        if let gesture {
            self.gesture = nil
            if layers != gesture.before { record(gesture.before) }
            return
        }
        defer { draft = nil; pressed = nil; guide = nil }
        guard let draft else { return }
        // A step is the click itself: it is placed wherever the release is, and no travel makes it a drawing or a selection.
        guard let first = pressed, first.travel >= Self.clickTravel || draft.tool == .step else {
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
        guard !held, let previous = past.popLast() else { return }
        Self.keep(layers, in: &future)
        layers = previous
        keepSelection()
    }

    public mutating func redo() {
        disarm()
        guard !held, let next = future.popLast() else { return }
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
        guard !held, let current = selected, let index = layers.firstIndex(of: current) else { return }
        let changed = change(current)
        guard !changed.looksLike(current) else { return }
        record(layers)
        layers[index] = changed
    }

    public mutating func recolor(_ color: AnnotationInk) {
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

    /// The selected object moved by `delta` points, shortened by the walls it is still inside of; a
    /// wall it already lies beyond (the area was pulled in past it) does not hold it, see
    /// `Annotation.translated`. **One undo step for a run of presses**: the first records the list before it, and each press after it
    /// (nothing but another arrow press in between — every other input calls `disarm`) moves the
    /// object further in that same step. A press that moves nothing, against a wall, is none.
    /// A press ends like a drag's release: an object it leaves wholly outside the area is let go of
    /// (`releaseIfOutside`). False when no object is selected, for the caller to move the area instead.
    public mutating func nudgeSelected(by delta: CGPoint) -> Bool {
        armed = false
        guard !held, let current = selected, let index = layers.firstIndex(of: current) else { return false }
        let changed = current.translated(by: delta, within: bounds)
        guard changed != current else { return true }
        if !nudging { record(layers) }
        nudging = true
        layers[index] = changed
        releaseIfOutside()
        return true
    }

    /// The area became `rect`. Not a step: the area is not a layer, and the layers stay where they
    /// are, whatever of them is outside `rect` now being clipped by whoever draws them. It is an
    /// input, so Esc's question and an open nudge end.
    public mutating func reshape(bounds rect: CGRect) {
        disarm()
        bounds = rect
    }

    /// The selected object is let go of when none of it is inside the area any more: a frame and
    /// handles left in the dim, under the palette, are something nobody can see to act on. One that is
    /// partly inside stays selected; nothing is recorded, the object stays where it is.
    public mutating func releaseIfOutside() {
        guard let current = selected, bounds.intersection(current.frame).isNull else { return }
        selectedID = nil
    }

    public mutating func deleteSelected() {
        disarm()
        guard !held, let current = selected else { return }
        record(layers)
        layers.removeAll { $0.id == current.id }
        selectedID = nil
    }

    /// Takes away the layers with these ids: **one undo step** however many go, and none when none of them is on the
    /// picture. A selected one that goes is no longer selected; the area, the others and the selection of any other stay.
    public mutating func remove(_ ids: Set<Annotation.ID>) {
        disarm()
        guard !held, layers.contains(where: { ids.contains($0.id) }) else { return }
        record(layers)
        layers.removeAll { ids.contains($0.id) }
        keepSelection()
    }

    /// The eraser's circle of `radius` is put down at `point`: from here to `endErase` every layer it meets is `erased`
    /// and goes in one step at the release. A point that is not a number, or a radius that is none, begins nothing.
    /// A press that finds another edit open ends it first, as `press` does.
    public mutating func beginErase(at point: CGPoint, radius: CGFloat) {
        disarm()
        guard point.x.isFinite, point.y.isFinite, radius.isFinite, radius > 0 else { return }
        if isBusy { end() }
        eraser = (point, radius, Set(meeting([point], radius: radius)))
    }

    /// The circle moves to `raw`; what it meets on the way is added to `erased`, wherever the segment crosses.
    private mutating func eraseDrag(to raw: CGPoint) {
        guard let current = eraser, raw.x.isFinite, raw.y.isFinite else { return }
        eraser = (raw, current.radius, current.met.union(meeting([current.last, raw], radius: current.radius, besides: current.met)))
    }

    /// The layers the eraser's drag has met so far, for the screen to show them fading; empty while none is open.
    public var erased: Set<Annotation.ID> { eraser?.met ?? [] }

    /// The release: what was met goes, in one step.
    private mutating func endErase() {
        guard let current = eraser else { return }
        eraser = nil
        remove(current.met)
    }

    /// What the circle meets along `path`, by the rule a click selects by, and only the part of the picture the area shows: a
    /// layer wholly outside the area is not on the screen, a point farther from the area than the radius reaches into it, and a
    /// layer across the area's edge is met only where the area shows it.
    /// The ids in `met` are not asked again.
    private func meeting(_ path: [CGPoint], radius: CGFloat, besides met: Set<Annotation.ID> = []) -> [Annotation.ID] {
        AnnotationHit.touched(by: path, radius: radius, in: layers.filter { !met.contains($0.id) }, within: bounds)
    }

    /// Esc and a right click, one door. A selected object is let go of first and nothing is
    /// asked. Then, with nothing on the picture it closes at once; with layers the first
    /// press arms and a second closes, however late; any other input in between withdraws
    /// the question. Undoing back to empty is the first case again.
    ///
    /// A move or a resize still open is **cancelled** first, the object back as the press took it
    /// and no step recorded: Esc is the way out of what is being done, and nothing the person
    /// has not let go of is kept. A drawing still under the pointer is dropped the same way,
    /// and that press does only that: it neither asks nor closes. So is an eraser's drag still open: nothing it has met
    /// goes, and no step is recorded.
    public mutating func escape() -> EscapeOutcome {
        if eraser != nil { eraser = nil; return .dropped }
        if draft != nil { draft = nil; pressed = nil; guide = nil; return .dropped }
        if let gesture { layers = gesture.before; self.gesture = nil }
        if selectedID != nil { selectedID = nil; return .deselected }
        if layers.isEmpty || armed { return .close }
        armed = true
        return .armed
    }
}
