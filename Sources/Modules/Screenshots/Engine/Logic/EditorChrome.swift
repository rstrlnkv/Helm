import CoreGraphics
import HelmRuntime

/// Where the editor's palette stands: one capsule, in the display's top-left points.
///
/// A function of the selection, the screen and the palette's measured size and nothing else, so every
/// edge and corner of the screen is a case that can be asked. **Below the area when there is room,
/// above it when below is short, inside it, against its bottom edge, when neither side has room**; held
/// on the screen last, so the palette is never off it. A side has room when the palette's height, the
/// gap and the margin fit on it.
public struct EditorChrome: Equatable, Sendable {
    public let palette: CGRect

    /// Whether a point is on the palette.
    public func covers(_ point: CGPoint) -> Bool { palette.contains(point) }

    /// Between the palette and the area, and inside the area from its bottom edge.
    public static let gap: CGFloat = 14
    /// The nearest the palette comes to the screen's edge, and the room kept free beyond it.
    public static let margin: CGFloat = 16

    /// `selection` is in the display's own points and `screen` is that display's size:
    /// the palette belongs to the display the selection is on, and no other.
    public static func place(selection: CGRect, in screen: CGSize, palette: CGSize) -> EditorChrome {
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
        return EditorChrome(palette: CGRect(x: along(selection.midX - width / 2, width, within: screen.width),
                                            y: along(y, height, within: screen.height), width: width, height: height))
    }
}
