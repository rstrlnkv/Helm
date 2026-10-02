import CoreGraphics

/// Where a point is, in the three spaces a capture passes through.
///
/// - **AppKit global**: the origin is the lower-left of the *primary* display
///   and y grows upward. `NSEvent.mouseLocation` and `NSScreen.frame` speak it.
/// - **CG global**: the origin is the upper-left of the primary display and y
///   grows downward. ScreenCaptureKit, `CGWindowList` and `CGDisplayBounds`
///   speak it.
/// - **Display-local**: CG's orientation with the origin at the display's own
///   upper-left corner, in points. The overlay draws in it and a selection is
///   made in it, which is why a selection can never belong to two displays.
///
/// They differ by a flip of y about the primary display's height, and that flip
/// is the whole bug class: a second display above or left of the primary has
/// negative CG coordinates, and a crop taken without the flip is the picture
/// of a different part of the desk.
public enum ScreenSpace {

    public static func cgPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A CG-global rect in the local space of the display whose CG frame is `display`.
    public static func local(_ global: CGRect, in display: CGRect) -> CGRect {
        global.offsetBy(dx: -display.minX, dy: -display.minY)
    }

    public static func global(_ local: CGRect, in display: CGRect) -> CGRect {
        local.offsetBy(dx: display.minX, dy: display.minY)
    }

    /// The pixels of a display's image a selection in points covers.
    ///
    /// Rounded **outward** to whole pixels, so the picture is never narrower
    /// than the rectangle the person drew, and clamped into the image: a
    /// selection dragged to the very edge is a rectangle that ends on the last
    /// pixel and not one past it. Nil when nothing is left — a selection wholly
    /// outside the image, or one that is not a number.
    public static func pixels(ofLocal rect: CGRect, scale: CGFloat,
                              imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, scale.isFinite, scale > 0
        else { return nil }
        let scaled = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale)
        let x0 = max(0, scaled.minX.rounded(.down)), y0 = max(0, scaled.minY.rounded(.down))
        let x1 = min(CGFloat(imageWidth), scaled.maxX.rounded(.up))
        let y1 = min(CGFloat(imageHeight), scaled.maxY.rounded(.up))
        guard x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
