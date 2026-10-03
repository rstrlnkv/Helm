import CoreGraphics
import HelmRuntime

/// A tool of the inline editor. Each is a case here, and each says how it is drawn in
/// `Annotation.stroke`, `isFilled`, `isUsable`, `outline` and `constrained`, and how it
/// is picked up in `handles` — the switches that the screen and the export both read.
///
/// **The raw value is stored data** (the last tool is remembered): a case is retired
/// and never removed or renamed, and a stored value that is none of the cases reads
/// as no tool.
public enum AnnotationTool: String, CaseIterable, Sendable, Equatable {
    /// Thick, tapered, filled: a tail that starts at a point and widens into the head.
    case arrow
    /// An outline.
    case rectangle
    /// An outline of the box the drag spans.
    case ellipse
    /// A straight stroke from the press to the pointer.
    case line
    /// A freehand stroke through the drag's points, smoothed: round cap and join, drawn as it is.
    /// The clean line: one even width (1.5, 3 or 6 pt by the step), nothing added to the path.
    case pen
    /// A freehand stroke through the drag's points, smoothed, like the pen's, with the grain of graphite (`PencilGrain`).
    case pencil
    /// A wide translucent freehand stroke like the pencil's, a single straight run at 45°
    /// steps while ⇧ is held, multiplied into the picture.
    case highlighter
    /// A box of the picture drawn as a mosaic (`Pixelate`), from the pixels under it and from nothing else: the
    /// box is held by its four corners like a rectangle and has no ink, so its colour and opacity are not read.
    /// The step is the mosaic's block, in points.
    case blur
    /// One line of text (`AnnotationText`) whose top-left is where it was placed: no handles, taken by its area. The
    /// step is the font's size in points, the ink the colour and opacity like any other tool's.
    case text
    /// A numbered circle whose centre is where it was placed (`AnnotationStep`): no handles, taken by its area. The
    /// number is stored nowhere: it is the layer's place among the steps (`AnnotationStep.numbers`). The step is the
    /// circle's diameter in points, the ink the colour and opacity like any other tool's.
    case step
    /// A box that stays bright while the rest of the area is dimmed (`Spotlights`): held by its four corners like a rectangle
    /// and taken by its edge, with no ink and no steps, so its colour, thickness and opacity are not read. Every spotlight
    /// of a picture is one dim, drawn under the other layers, and no spotlight draws a layer of its own.
    case spotlight
    /// A circle that shows the picture under it twice as large (`Magnifier`): held by the corners of its square like an ellipse, always a circle,
    /// taken by its area. The ink is its ring's colour and opacity and the step the ring's width; the magnification is one for all.
    case magnifier
    /// One emoji (`AnnotationText`'s layout, one grapheme), whose middle is where it was placed: no handles, taken by its area. The step is
    /// the font's size in points, the opacity how much of it shows; the colour is the emoji's own, so the ink is not read.
    case emoji

    /// Drawn through the points of a drag rather than from its two ends.
    public var isFreehand: Bool { self == .pen || self == .pencil || self == .highlighter }

    /// Takes the pencil's grain (`PencilGrain`): the one predicate the screen and the export both ask, so neither
    /// can give the Pen or the Marker a grain the other does not.
    public var isGrainy: Bool { self == .pencil }
}

/// How a stroked annotation is inked: one description that the screen's shape layer and
/// the export's context both read, so the two cannot disagree about width, colour or blend.
public struct AnnotationStroke: Sendable, Equatable {
    public let width: CGFloat
    public let color: CGColor
    /// Multiplied into what is under it: a dark pixel stays dark, a white one takes the tint.
    public let multiplies: Bool
    public let cap: CGLineCap
    public let join: CGLineJoin
}

/// One of the eight inks, fixed in sRGB: the picture does not change with the
/// appearance the person's Mac is in. **The raw value is stored data** — retire a
/// case, never remove or rename one.
public enum AnnotationColor: String, CaseIterable, Sendable, Equatable {
    case red, orange, yellow, green, blue, purple, black, white

    private var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red: (0.92, 0.16, 0.14)
        case .orange: (1, 0.58, 0.1)
        case .yellow: (1, 0.9, 0.1)
        case .green: (0.2, 0.78, 0.35)
        case .blue: (0.1, 0.45, 0.95)
        case .purple: (0.62, 0.3, 0.85)
        case .black: (0, 0, 0)
        case .white: (1, 1, 1)
        }
    }

    public var cgColor: CGColor { CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
}

/// The three steps of thickness. A person picks a weight and the tool says how many points
/// it is (`points(for:)`): each tool has its own three, since a step that is right for the
/// marker is a lump for the pen. **The raw value is stored data**, and a stored number outside
/// 0…2 is clamped to the nearest step by the reader (`EditorMemory`).
public enum AnnotationThickness: Int, CaseIterable, Sendable, Equatable {
    case thin = 0, medium, thick

    /// The step's width in points under a tool: the stroke's width, and for the arrow the
    /// shaft at its thickest, of which the head is three, and for the blur the block's side, for the text the font's size,
    /// for a step the circle's diameter, for the magnifier the ring's width, for the emoji the font's size. The spotlight has no steps and reads 0 in each. The one table the screen and the export read.
    public func points(for tool: AnnotationTool) -> CGFloat {
        let steps: [CGFloat]
        switch tool {
        case .pen: steps = [1.5, 3, 6]
        case .highlighter: steps = [6, 12, 18]
        case .pencil: steps = [2, 3.5, 5]
        case .arrow: steps = [6, 10, 16]
        case .rectangle, .ellipse, .line: steps = [3, 5, 8]
        case .blur: steps = [10, 16, 24]
        case .text: steps = [12, 15, 22]
        case .step: steps = [16, 20, 28]
        case .spotlight: steps = [0, 0, 0]
        case .magnifier: steps = [2, 3, 5]
        case .emoji: steps = [24, 32, 48]
        }
        return steps[rawValue]
    }
}

/// What the **next** object is drawn with: the colour, the thickness, the opacity and, for the
/// boxes, whether they are filled. An object keeps the style it was begun with.
public struct AnnotationStyle: Sendable, Equatable {
    /// Nil until a colour is picked: each tool then has its own — red, and yellow for
    /// the marker. Once one is picked it is every tool's, the marker's included.
    public var color: AnnotationColor?
    public var thickness: AnnotationThickness
    public var filled: Bool
    /// How much of the ink shows, 0.1…1 once read from the store; the marker's own 0.6 is multiplied by it.
    public var opacity: Double

    /// The default step is the middle one, which is what a tool nobody picked a step for reads
    /// from the store (`EditorMemory`), so `standard` is that tool's style and not a second default.
    public init(color: AnnotationColor? = nil, thickness: AnnotationThickness = .medium, filled: Bool = false,
                opacity: Double = 1) {
        self.color = color
        self.thickness = thickness
        self.filled = filled
        self.opacity = opacity
    }

    public static let standard = AnnotationStyle()

    /// The ink a tool is drawn in under this style.
    public func ink(for tool: AnnotationTool) -> AnnotationColor {
        color ?? (tool == .highlighter ? .yellow : .red)
    }
}

/// Where a selected annotation is held to resize it: the two ends of a straight one, the
/// four corners of the box round any other. Corners are named in the display's top-left points.
public enum AnnotationHandle: Sendable, Equatable {
    case start, end
    case topLeft, topRight, bottomLeft, bottomRight
}

/// One layer over the frozen picture, in display-local points like a selection.
///
/// Stored in **points** and nowhere in pixels: the screen draws it in points and the
/// export multiplies by the display's scale, so one geometry serves both and a
/// stroke is as thick in the file as it was on the screen.
///
/// A value with an **identity**: `id` is given when the layer is begun and kept by every
/// edit, so undo, redo and the screen's cache can tell "the same object, changed" from
/// "another object". Two annotations are equal only when the id is too.
public struct Annotation: Sendable, Equatable {
    public typealias ID = Int

    public let tool: AnnotationTool
    public let start: CGPoint
    public let end: CGPoint
    /// The freehand path of the pen, the pencil and the highlighter, first point to last; empty for the other tools.
    public let points: [CGPoint]
    public let style: AnnotationStyle
    /// What the text tool wrote; nil for every other tool. Never in a log line: it is somebody's words.
    public let text: String?
    /// Nothing outside `AnnotationEditing` gives one; 0 is the id of a value made by hand.
    public let id: ID

    public init(tool: AnnotationTool, start: CGPoint, end: CGPoint, points: [CGPoint] = [],
                style: AnnotationStyle = .standard, text: String? = nil, id: ID = 0) {
        self.tool = tool
        self.start = start
        self.end = end
        self.points = points
        self.style = style
        self.text = text
        self.id = id
    }

    /// Whether the two are drawn the same: the ink as shown (an unset colour is the tool's own; a blur, a spotlight and an emoji have none),
    /// the thickness, the fill and the text, which is what a person can see and so what an edit may be a step for.
    func looksLike(_ other: Annotation) -> Bool {
        let inkless = tool == .blur || tool == .spotlight || tool == .emoji
        return (inkless || style.ink(for: tool) == other.style.ink(for: other.tool))
            && (tool == .spotlight || style.thickness == other.style.thickness) && isFilled == other.isFilled && text == other.text
    }

    /// The same object in another style.
    func restyled(_ style: AnnotationStyle) -> Annotation {
        Annotation(tool: tool, start: start, end: end, points: points, style: style, text: text, id: id)
    }

    /// The box round the geometry's points, not round the stroke's width; a text's or an emoji's is its line's room from where it starts, a step's the square its circle is in.
    public var frame: CGRect {
        if tool == .text || tool == .emoji { return CGRect(origin: start, size: AnnotationText.size(of: self)) }
        if tool == .step { return AnnotationStep.frame(of: self) }
        let all = [start, end] + points
        let xs = all.map(\.x), ys = all.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// A straight stroke is held by its two ends and every other shape by the corners of its
    /// box: the freehand ones are scaled inside it, which is how a drawing is made larger.
    private var isStraight: Bool {
        tool == .line || tool == .arrow || (tool == .highlighter && points.count == 2)
    }

    /// Where the handles stand, in the order `AnnotationHandle` names them.
    public var handles: [(handle: AnnotationHandle, point: CGPoint)] {
        if tool == .text || tool == .step || tool == .emoji { return [] }
        if isStraight { return [(.start, start), (.end, end)] }
        let box = frame
        return [(.topLeft, CGPoint(x: box.minX, y: box.minY)), (.topRight, CGPoint(x: box.maxX, y: box.minY)),
                (.bottomLeft, CGPoint(x: box.minX, y: box.maxY)), (.bottomRight, CGPoint(x: box.maxX, y: box.maxY))]
    }

    /// The farthest one move may carry an object on a side with no wall to stop it: far past any
    /// display, and small enough that a run of moves stays among the finite numbers.
    private static let freeReach: CGFloat = 1e6

    /// The object moved by `delta`, the movement shortened per axis until the geometry's box
    /// is inside `bounds`: a wall the box is inside of is never crossed. A clamp only ever
    /// shortens a move, never reverses it or makes it longer: on a side where the box already
    /// lies beyond the wall (the area was pulled in past it) that wall has nothing to push
    /// against, so the move passes as asked and the opposite wall alone limits it, itself held
    /// to `freeReach` so no run of moves reaches the end of the finite numbers. A delta that
    /// is not finite moves nothing.
    func translated(by delta: CGPoint, within bounds: CGRect) -> Annotation {
        guard delta.x.isFinite, delta.y.isFinite else { return self }
        let box = frame
        func allowed(_ move: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            let floor = low <= 0 ? low : -Self.freeReach, ceiling = high >= 0 ? high : Self.freeReach
            return move.clamped(to: floor...ceiling, whenNotANumber: 0) // not a number: no move
        }
        let dx = allowed(delta.x, low: bounds.minX - box.minX, high: bounds.maxX - box.maxX)
        let dy = allowed(delta.y, low: bounds.minY - box.minY, high: bounds.maxY - box.maxY)
        func move(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + dx, y: point.y + dy) }
        return Annotation(tool: tool, start: move(start), end: move(end), points: points.map(move), style: style, text: text, id: id)
    }

    /// The same object with every point of its geometry taken through `transform`.
    func mapped(_ transform: (CGPoint) -> CGPoint) -> Annotation {
        Annotation(tool: tool, start: transform(start), end: transform(end), points: points.map(transform), style: style, text: text, id: id)
    }

    /// The object with `handle` taken to `pointer`; nil when the object has no such handle.
    /// A straight one moves that end. A box, and a freehand stroke inside its box, keeps the
    /// opposite corner where it is and scales every point of the geometry by the same factor
    /// per axis, so a drag past the opposite corner mirrors it. The caller holds the pointer
    /// in the selection and drops a result that is not `isUsable`.
    func resized(_ handle: AnnotationHandle, to pointer: CGPoint) -> Annotation? {
        if isStraight {
            switch handle {
            case .start:
                return Annotation(tool: tool, start: pointer, end: end, points: points.isEmpty ? [] : [pointer, end],
                                  style: style, text: text, id: id)
            case .end:
                return Annotation(tool: tool, start: start, end: pointer, points: points.isEmpty ? [] : [start, pointer],
                                  style: style, text: text, id: id)
            default: return nil
            }
        }
        guard let moving = handles.first(where: { $0.handle == handle })?.point else { return nil }
        let box = frame
        // The corner across the box from the one held.
        let fixed = CGPoint(x: moving.x == box.minX ? box.maxX : box.minX, y: moving.y == box.minY ? box.maxY : box.minY)
        // A box with no width has nothing to scale: its points all fall on the held edge.
        func scale(_ value: CGFloat, _ held: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
            from == held ? held : held + (value - held) / (from - held) * (to - held)
        }
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: scale(point.x, fixed.x, moving.x, pointer.x), y: scale(point.y, fixed.y, moving.y, pointer.y))
        }
        // A circle stays one: the square from the corner across from the dragged handle to the pointer, the longer side winning.
        if tool == .magnifier {
            return Annotation(tool: tool, start: fixed, end: Self.constrained(.magnifier, from: fixed, to: pointer, shift: true),
                              style: style, id: id)
        }
        return Annotation(tool: tool, start: map(start), end: map(end), points: points.map(map), style: style, text: text, id: id)
    }

    /// How much of the ink the marker lets through: 60 %. The multiply is what keeps text readable.
    static let markerAlpha: CGFloat = 0.6
    /// The most points any freehand trail (pen, pencil or marker) keeps; a longer drag is thinned, never grown.
    public static let maxPoints = 1024
    /// The nearest a new freehand point may come to the last kept one, in points; a
    /// nearer pointer is only the tip of the stroke until it is this far.
    static let freehandGap: CGFloat = 2

    /// Painted as a solid shape rather than stroked: the arrow and the step always, and a rectangle or
    /// an ellipse when the style says filled.
    public var isFilled: Bool {
        tool == .arrow || tool == .step || (style.filled && (tool == .rectangle || tool == .ellipse))
    }

    /// The mosaic's block, in points: the thickness step read for the blur.
    public var blockPoints: CGFloat { style.thickness.points(for: .blur) }

    /// The colour a filled shape is painted in; for a stroked one see `stroke`.
    public var fillColor: CGColor { inked(style.opacity) }

    /// The tool's ink at `alpha`.
    private func inked(_ alpha: Double) -> CGColor {
        let ink = style.ink(for: tool).cgColor
        return ink.copy(alpha: CGFloat(alpha)) ?? ink
    }

    /// The ink of a stroked annotation; nil for a filled shape, for the blur, which is no ink but a picture (`Pixelate`), for a text and an emoji (`AnnotationText`), for the lens (`Magnifier`), and for the spotlight, which is a hole in the dim (`Spotlights`).
    ///
    /// **Caps and joins.** A shape has butt caps and mitred corners, the line and the
    /// pen and the pencil round both. The marker's caps stay butt, flat like a chisel nib, but its
    /// joins are round: it is a freehand stroke 6 pt and more wide, and a mitre on a
    /// jagged path throws a spike far past the point it turns at.
    public var stroke: AnnotationStroke? {
        guard !isFilled else { return nil }
        let width = style.thickness.points(for: tool)
        switch tool {
        case .arrow, .blur, .text, .step, .spotlight, .magnifier, .emoji: return nil
        case .rectangle, .ellipse:
            return AnnotationStroke(width: width, color: inked(style.opacity), multiplies: false, cap: .butt, join: .miter)
        case .line, .pen, .pencil:
            return AnnotationStroke(width: width, color: inked(style.opacity), multiplies: false, cap: .round, join: .round)
        case .highlighter:
            return AnnotationStroke(width: width, color: inked(Double(Self.markerAlpha) * style.opacity),
                                    multiplies: true, cap: .butt, join: .round)
        }
    }

    /// Where the pointer wants the far corner or end to be once ⇧ is read: a square or
    /// a circle for the box tools (the longer side wins, each axis keeps its sign) and
    /// the nearest multiple of 45° for the straight ones, length kept. The pen and the pencil
    /// ignores it, and the magnifier is always the circle's square, ⇧ or not. The caller passes the **live** flag of the event in hand. With `bounds`
    /// a box with no travel on an axis grows to the side that has more room there.
    public static func constrained(_ tool: AnnotationTool, from start: CGPoint, to end: CGPoint,
                                   shift: Bool, within bounds: CGRect? = nil) -> CGPoint {
        guard shift || tool == .magnifier else { return end }
        let dx = end.x - start.x, dy = end.y - start.y
        switch tool {
        case .rectangle, .ellipse, .blur, .spotlight, .magnifier:
            let side = max(abs(dx), abs(dy))
            let left = dx == 0 ? bounds.map { start.x - $0.minX > $0.maxX - start.x } ?? false : dx < 0
            let up = dy == 0 ? bounds.map { start.y - $0.minY > $0.maxY - start.y } ?? false : dy < 0
            return CGPoint(x: start.x + (left ? -side : side), y: start.y + (up ? -side : side))
        case .line, .highlighter:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        case .arrow, .pen, .pencil, .text, .step, .emoji:
            return end
        }
    }

    /// Whether there is anything to draw: a click that never moved is not an
    /// arrow, and a rectangle with no width or no height is a line the person did
    /// not ask for. Not finite is not usable either.
    public var isUsable: Bool {
        guard ([start.x, start.y, end.x, end.y] + points.flatMap { [$0.x, $0.y] }).allSatisfy(\.isFinite)
        else { return false }
        switch tool {
        case .arrow, .line: return hypot(end.x - start.x, end.y - start.y) >= 1
        case .rectangle, .ellipse, .blur, .spotlight: return abs(end.x - start.x) >= 1 && abs(end.y - start.y) >= 1
        case .magnifier: return min(abs(end.x - start.x), abs(end.y - start.y)) >= Magnifier.minimumDiameter
        case .emoji: return text.map { $0.count == 1 && !AnnotationText.isInvisible($0.first!) } == true
        case .pen, .pencil, .highlighter: return points.contains { hypot($0.x - start.x, $0.y - start.y) >= 1 }
        case .text: return text?.contains { !AnnotationText.isInvisible($0) } == true
        case .step: return true
        }
    }

    /// The shape, in the same top-left points: painted as `isFilled` says, otherwise
    /// stroked as `stroke` says. The one geometry the screen and the export both draw.
    /// The pen, the pencil and the highlighter are smoothed as a quadratic curve through the midpoints of
    /// their points, each point the control of the bend it makes, ending on the last; with no
    /// more than one point there is no path.
    public var outline: CGPath {
        switch tool {
        case .line:
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: end)
            return path
        case .ellipse:
            return CGPath(ellipseIn: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                            width: abs(end.x - start.x), height: abs(end.y - start.y)),
                          transform: nil)
        case .pen, .pencil, .highlighter:
            let path = CGMutablePath()
            guard let first = points.first, let last = points.last, points.count > 1 else { return path }
            path.move(to: first)
            for index in 1..<(points.count - 1) {
                let here = points[index], next = points[index + 1]
                path.addQuadCurve(to: CGPoint(x: (here.x + next.x) / 2, y: (here.y + next.y) / 2), control: here)
            }
            path.addLine(to: last)
            return path
        case .text, .emoji: return CGPath(rect: frame, transform: nil)
        case .step, .magnifier: return CGPath(ellipseIn: frame, transform: nil)
        case .spotlight: return Spotlights.outline(of: self)
        case .rectangle, .blur:
            return CGPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)),
                          transform: nil)
        case .arrow:
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { return CGMutablePath() }
            let along = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
            let across = CGVector(dx: -along.dy, dy: along.dx)
            // The head is at most as long as half the arrow, so a short one is still
            // an arrow and not a head with no shaft.
            let shaft = style.thickness.points(for: .arrow)
            let head = min(length * 0.5, shaft * 3)
            let base = CGPoint(x: end.x - along.dx * head, y: end.y - along.dy * head)
            func point(_ origin: CGPoint, _ side: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + across.dx * side, y: origin.y + across.dy * side)
            }
            let path = CGMutablePath()
            path.addLines(between: [
                point(start, shaft * 0.1), point(base, shaft * 0.5), point(base, shaft * 1.5),
                end,
                point(base, -shaft * 1.5), point(base, -shaft * 0.5), point(start, -shaft * 0.1),
            ])
            path.closeSubpath()
            return path
        }
    }
}
