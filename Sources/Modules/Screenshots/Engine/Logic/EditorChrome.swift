import CoreGraphics
import HelmRuntime

/// Where the editor's two bars stand: the tool bar to the right of the selection and
/// the action row below it, in the display's top-left points.
///
/// A function of the selection, the screen and the two bars' sizes and nothing else, so every
/// edge and corner of the screen is a case that can be asked. **Outside the selection when there is room, and inward
/// when there is not**: a bar that would cross the screen's edge is put inside the
/// selection against the same edge, and whatever is left over is held on the screen,
/// so a bar is never off it. The two never overlap each other: the row steps left of
/// the tool bar when the two would meet, right of it when there is no room on the left, and under or
/// over it when there is none on either side; only a screen too small for both leaves them meeting.
public struct EditorChrome: Equatable, Sendable {
    public let tools: CGRect
    public let actions: CGRect

    /// Whether a point is on either bar.
    public func covers(_ point: CGPoint) -> Bool { tools.contains(point) || actions.contains(point) }

    /// Between a bar and the selection, and between the two bars.
    public static let gap: CGFloat = 8
    /// The nearest a bar comes to the screen's edge.
    public static let margin: CGFloat = 4

    /// `selection` is in the display's own points and `screen` is that display's size:
    /// the bars belong to the display the selection is on, and no other.
    public static func place(selection: CGRect, in screen: CGSize, tools: CGSize, actions: CGSize) -> EditorChrome {
        // Outside the selection on the far side, or inside against it when the far side
        // runs out; then held on the screen. A bar longer than the screen is put at its start.
        func along(_ start: CGFloat, _ length: CGFloat, within limit: CGFloat) -> CGFloat {
            let low = margin, high = max(margin, limit - length - margin)
            return start.clamped(to: low...high, whenNotANumber: low)
        }
        func beyond(_ edge: CGFloat, _ length: CGFloat, within limit: CGFloat) -> CGFloat {
            let outside = edge + gap
            return along(outside + length + margin <= limit ? outside : edge - gap - length, length, within: limit)
        }

        let right = beyond(selection.maxX, tools.width, within: screen.width)
        let toolBar = CGRect(x: right, y: along(selection.minY, tools.height, within: screen.height),
                             width: tools.width, height: tools.height)

        let below = beyond(selection.maxY, actions.height, within: screen.height)
        var row = CGRect(x: along(selection.maxX - actions.width, actions.width, within: screen.width), y: below,
                         width: actions.width, height: actions.height)
        func meets() -> Bool { row.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(toolBar) }
        if meets() {
            row.origin.x = along(toolBar.minX - gap - actions.width, actions.width, within: screen.width)
            // No room to the left of the tool bar (it is near the screen's left edge): the right.
            if meets() { row.origin.x = along(toolBar.maxX + gap, actions.width, within: screen.width) }
            // Neither side holds the row (a small screen, a tall tool bar): it goes under the tool
            // bar, or over it. Only a screen that cannot hold the two bars at all leaves them meeting,
            // and then the row yields to the screen's edge, not the tool bar to the row.
            if meets() {
                row.origin.y = along(toolBar.maxY + gap, actions.height, within: screen.height)
                if meets() { row.origin.y = along(toolBar.minY - gap - actions.height, actions.height, within: screen.height) }
            }
        }
        return EditorChrome(tools: toolBar, actions: row)
    }
}
