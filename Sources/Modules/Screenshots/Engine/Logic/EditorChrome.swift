import CoreGraphics
import HelmRuntime

/// Where the editor's palette stands: one capsule, in the display's top-left points.
///
/// A function of the selection, the screen and the palette's measured size and nothing else, so every
/// edge and corner of the screen is a case that can be asked. **Below the area when there is room,
/// above it when below is short, inside it, against its bottom edge, when neither side has room**; held
/// on the screen last, so the palette is never off it. A side has room when the palette's height, the
/// gap and the margin fit on it.
///
/// **The pop-over, thickness and opacity or colours,** stands centred on the cell that opened it, `popoverGap` under the
/// palette when its height, the gap and the margin fit under it, else `popoverGap` above it, and is held on the
/// screen like the palette. It never moves the palette. A press on it is a press on the chrome; the gap between
/// the two is the picture's.
public struct EditorChrome: Equatable, Sendable {
    public let palette: CGRect
    /// Nil when no pop-over is open.
    public let popover: CGRect?

    /// Whether a point is on the palette or on the pop-over.
    public func covers(_ point: CGPoint) -> Bool { palette.contains(point) || popover?.contains(point) == true }

    /// Between the palette and the area, and inside the area from its bottom edge.
    public static let gap: CGFloat = 14
    /// Between the palette and its pop-over.
    public static let popoverGap: CGFloat = 8
    /// The nearest the palette comes to the screen's edge, and the room kept free beyond it.
    public static let margin: CGFloat = 16

    /// `selection` is in the display's own points and `screen` is that display's size:
    /// the palette belongs to the display the selection is on, and no other. `popover` is the pop-over's size, nil
    /// for none, and `anchorX` the opening cell's centre in the display's own points; one that is not a number is
    /// the screen's start, like any other position.
    public static func place(selection: CGRect, in screen: CGSize, palette: CGSize,
                             popover: CGSize? = nil, anchorX: CGFloat = 0) -> EditorChrome {
        // A size that is not a number is none; an infinite one is the largest there is, held at the
        // screen's start like any palette longer than the screen.
        let width = palette.width.clamped(to: 0...CGFloat.greatestFiniteMagnitude, whenNotANumber: 0)
        let height = palette.height.clamped(to: 0...CGFloat.greatestFiniteMagnitude, whenNotANumber: 0)

        func along(_ start: CGFloat, _ length: CGFloat, within limit: CGFloat) -> CGFloat {
            let low = margin, high = max(margin, limit - length - margin)
            return start.clamped(to: low...high, whenNotANumber: low)
        }

        let below = selection.maxY + gap
        let above = selection.minY - gap - height
        let y: CGFloat
        if below + height + margin <= screen.height {
            y = below
        } else if above >= margin {
            y = above
        } else {
            y = selection.maxY - gap - height
        }
        let stood = CGRect(x: along(selection.midX - width / 2, width, within: screen.width),
                           y: along(y, height, within: screen.height), width: width, height: height)
        guard let popover else { return EditorChrome(palette: stood, popover: nil) }
        let popoverWidth = popover.width.clamped(to: 0...CGFloat.greatestFiniteMagnitude, whenNotANumber: 0)
        let popoverHeight = popover.height.clamped(to: 0...CGFloat.greatestFiniteMagnitude, whenNotANumber: 0)
        let room = stood.maxY + popoverGap + popoverHeight + margin <= screen.height
        let top = room ? stood.maxY + popoverGap : stood.minY - popoverGap - popoverHeight
        return EditorChrome(palette: stood,
                            popover: CGRect(x: along(anchorX - popoverWidth / 2, popoverWidth, within: screen.width),
                                            y: along(top, popoverHeight, within: screen.height),
                                            width: popoverWidth, height: popoverHeight))
    }
}
