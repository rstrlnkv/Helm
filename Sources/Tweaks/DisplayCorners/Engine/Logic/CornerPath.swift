import CoreGraphics

/// **The one corner path, for the mask the UI draws and the boundary the pointer is held to.**
///
/// The standalone app cropped a corner out of SwiftUI's continuous `RoundedRectangle`, which an engine
/// cannot import (review finding 16). This draws the same kind of corner with CoreGraphics: three cubic
/// Béziers whose edge span is `edgeSpan` × radius, the proportions of the continuous corner.
/// **Measured, not assumed:** measured once outside the repo, it deviates from SwiftUI's `.continuous` by
/// at most 0.00005 pt at radii 5, 14, 28 and 64; `CornerLogicTests` pins it within 0.01 pt at radius 100.
///
/// Coordinates are the mask view's: origin bottom-left, y up, the square `size` × `size`.
public enum CornerPath {
    /// How far along each edge the curve starts, in radii.
    static let edgeSpan: CGFloat = 1.52866483

    /// The part of the display that stays visible, as a region that reaches far past the square, so
    /// `contains` answers for any point of it. Not finite or not positive radius → no rounding.
    public static func visible(size: CGFloat, radius: CGFloat, corner: CornerPosition) -> CGPath {
        let size = size.isFinite && size > 0 ? size : 0
        // A radius that is not a number is no radius: the corner is square, not trapped on.
        let r = radius.isFinite && radius > 0 ? radius : 0
        let far = size * 4
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r * edgeSpan, y: 0))
        path.addCurve(to: CGPoint(x: r * 0.63149379, y: r * 0.07491139),
                      control1: CGPoint(x: r * 1.08849296, y: 0), control2: CGPoint(x: r * 0.86840694, y: 0))
        path.addCurve(to: CGPoint(x: r * 0.07491139, y: r * 0.63149379),
                      control1: CGPoint(x: r * 0.37282383, y: r * 0.16905956),
                      control2: CGPoint(x: r * 0.16905956, y: r * 0.37282383))
        path.addCurve(to: CGPoint(x: 0, y: r * edgeSpan),
                      control1: CGPoint(x: 0, y: r * 0.86840694), control2: CGPoint(x: 0, y: r * 1.08849296))
        path.addLine(to: CGPoint(x: 0, y: far))
        path.addLine(to: CGPoint(x: far, y: far))
        path.addLine(to: CGPoint(x: far, y: 0))
        path.closeSubpath()
        // Drawn at the bottom-left corner; the other three are its mirrors about the square.
        var flip = CGAffineTransform(a: corner.isRight ? -1 : 1, b: 0, c: 0, d: corner.isTop ? -1 : 1,
                                     tx: corner.isRight ? size : 0, ty: corner.isTop ? size : 0)
        return path.copy(using: &flip) ?? path
    }

    /// The outer square plus the visible path, to be filled even-odd: what is left is the mask.
    public static func mask(size: CGFloat, radius: CGFloat, corner: CornerPosition) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: size.isFinite && size > 0 ? size : 0,
                            height: size.isFinite && size > 0 ? size : 0))
        path.addPath(visible(size: size, radius: radius, corner: corner))
        return path
    }
}
