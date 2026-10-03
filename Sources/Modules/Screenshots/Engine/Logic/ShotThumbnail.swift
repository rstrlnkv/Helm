import CoreGraphics
import HelmRuntime

/// How large the after-shot window's picture is: a function of the shot's pixels and nothing else, so the picture's
/// view, the window round it and the drag's frame all take one size, and a very wide, very tall or very small shot is a
/// case that can be asked.
public enum ShotThumbnail {
    /// The longest edge, in pixels, of the reduced copy the window holds: small enough to keep for the few seconds the
    /// window lives without keeping the frame, and what a drag or a share of the copy would hand over.
    public static let longestEdge: CGFloat = 520
    /// The largest the picture stands on the screen, in points.
    public static let maxWidth: CGFloat = 200
    public static let maxHeight: CGFloat = 126

    /// Far above any display, so that an endless size is a finite one and the scale below is never zero times infinity.
    private static let largestShot: CGFloat = 1_000_000

    /// The picture's size in points: the pixels as they are, reduced to fit `maxWidth` by `maxHeight` with the
    /// proportions kept, never enlarged. A size that is not a number, or has no area, is one point on that side.
    public static func fitted(pixels: CGSize) -> CGSize {
        let width = pixels.width.clamped(to: 1...largestShot, whenNotANumber: 1)
        let height = pixels.height.clamped(to: 1...largestShot, whenNotANumber: 1)
        let scale = min(1, maxWidth / width, maxHeight / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
