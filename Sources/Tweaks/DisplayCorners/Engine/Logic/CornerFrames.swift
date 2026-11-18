import CoreGraphics

/// Where a mask window stands, in AppKit's coordinates, and where it rests in Quartz's.
enum CornerFrames {
    /// A window larger than this is capped to it, and so is the radius it holds (half of it): a radius that
    /// did not come from a sane setting.
    static let largestSize: CGFloat = 512

    /// `ceil(2r)`, or 0 for a radius that is not a number or not positive: a size that is 0 is no window.
    static func size(radius: CGFloat) -> CGFloat {
        guard radius.isFinite, radius > 0 else { return 0 }
        return min(ceil(radius * 2), largestSize)
    }

    static func isUsable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    /// The square of `size` at one corner of a display's AppKit frame.
    static func windowFrame(display: CGRect, size: CGFloat, corner: CornerPosition) -> CGRect {
        CGRect(x: corner.isRight ? display.maxX - size : display.minX,
               y: corner.isTop ? display.maxY - size : display.minY,
               width: size, height: size)
    }

    /// The same square in Quartz's coordinates (top-left origin, global): the frame the window list
    /// reports while the window rests. Flips about the display's own frame, so negative origins hold.
    static func restingQuartzFrame(window: CGRect, display: CGRect, quartzBounds: CGRect) -> CGRect {
        CGRect(x: quartzBounds.minX + window.minX - display.minX,
               y: quartzBounds.minY + display.maxY - window.maxY,
               width: window.width, height: window.height)
    }
}
