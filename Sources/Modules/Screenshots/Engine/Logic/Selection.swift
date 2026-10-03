import CoreGraphics

/// A selection being dragged out, in display-local points.
///
/// A value with the modifiers as arguments, so every rule is a function of what
/// was pressed and where the pointer is and none of it reads a keyboard: the
/// overlay feeds it events and draws what it answers.
public struct SelectionDrag: Sendable {
    public let bounds: CGRect
    private(set) var anchor: CGPoint
    private(set) var pointer: CGPoint
    /// Shift was pressed: one axis stands where it was, and this says which and
    /// at what value, so releasing shift hands the pointer back its freedom.
    private var locked: (axis: Axis, value: CGFloat)?
    private var lastPoint: CGPoint
    /// The pointer has been off the press point at some time in this drag, and stays so: back on it, the selection is
    /// empty but the drag is not a press any more.
    public private(set) var hasMoved = false

    public enum Axis: Sendable { case horizontal, vertical }

    public init(start: CGPoint, bounds: CGRect) {
        let start = Self.clamp(start, to: bounds)
        self.bounds = bounds
        self.anchor = start
        self.pointer = start
        self.lastPoint = start
    }

    /// Pointer moved, with the modifiers as they are now.
    ///
    /// - `shift` freezes the axis the pointer has moved **less** along, at the
    ///   value it had when shift went down, so the selection grows in one
    ///   direction only.
    /// - `option` makes the start the centre, so the selection grows both ways.
    /// - `space` moves the whole selection with the pointer rather than
    ///   resizing it, and keeps it inside the display.
    public mutating func move(to point: CGPoint, shift: Bool, option: Bool, space: Bool) {
        let point = Self.clamp(point, to: bounds)
        defer { lastPoint = point }
        if space {
            // The selection as it stands, carried by the pointer's own step. The
            // step is cut where the rectangle meets an edge so it cannot be
            // squeezed: a selection pushed against a wall stays the size it was.
            let rect = Self.rect(anchor: anchor, pointer: pointer, option: centred)
            var dx = point.x - lastPoint.x, dy = point.y - lastPoint.y
            dx = min(max(dx, bounds.minX - rect.minX), bounds.maxX - rect.maxX)
            dy = min(max(dy, bounds.minY - rect.minY), bounds.maxY - rect.maxY)
            anchor = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
            pointer = CGPoint(x: pointer.x + dx, y: pointer.y + dy)
            if pointer != anchor { hasMoved = true }
            return
        }
        var target = point
        if shift {
            if locked == nil {
                let horizontal = abs(pointer.x - anchor.x) >= abs(pointer.y - anchor.y)
                // Freeze the shorter side — the axis the person has not been
                // dragging along.
                locked = horizontal ? (.vertical, pointer.y) : (.horizontal, pointer.x)
            }
            if let locked {
                switch locked.axis {
                case .vertical: target.y = locked.value
                case .horizontal: target.x = locked.value
                }
            }
        } else {
            locked = nil
        }
        pointer = target
        centred = option
        if pointer != anchor { hasMoved = true }
    }

    private var centred = false

    /// The selection, normalised and inside the display.
    public var rect: CGRect {
        let raw = Self.rect(anchor: anchor, pointer: pointer, option: centred)
        return raw.intersection(bounds)
    }

    /// Whether there is anything to capture: a click that never moved is not a
    /// selection, and neither is a sliver under one point in either direction.
    public var isUsable: Bool { rect.width >= 1 && rect.height >= 1 }

    private static func rect(anchor: CGPoint, pointer: CGPoint, option: Bool) -> CGRect {
        if option {
            let dx = abs(pointer.x - anchor.x), dy = abs(pointer.y - anchor.y)
            return CGRect(x: anchor.x - dx, y: anchor.y - dy, width: 2 * dx, height: 2 * dy)
        }
        return CGRect(x: min(anchor.x, pointer.x), y: min(anchor.y, pointer.y),
                      width: abs(pointer.x - anchor.x), height: abs(pointer.y - anchor.y))
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        // A point that is not a number is taken to the origin of the bounds and
        // not passed through: `min` and `max` hand a NaN back untouched, and a
        // rectangle made of one crops nothing and reads as a selection.
        guard point.x.isFinite, point.y.isFinite else { return bounds.origin }
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

public enum Selection {
    /// Enter with nothing selected: the whole display, which is what macOS does.
    public static func wholeDisplay(_ bounds: CGRect) -> CGRect { bounds }

    /// The size a person reads while dragging, in pixels — a point is one to
    /// three pixels and the picture is made of pixels.
    public static func pixelSize(of rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        guard rect.width.isFinite, rect.height.isFinite, scale.isFinite, scale > 0 else { return (0, 0) }
        return (Int((rect.width * scale).rounded()), Int((rect.height * scale).rounded()))
    }
}
