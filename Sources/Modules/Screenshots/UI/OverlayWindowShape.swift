import CoreGraphics

/// The outline of a picked window, for the fill that lights it and the flash that says it was taken.
///
/// **One place, so the shape can be swapped.** The system gives no radius for a window's corners
/// (`CGWindowListCopyWindowInfo` has none, and `SCWindow` has only a frame), so the outline is the
/// window's frame as a rectangle. A rounded one — from the alpha of the window's own
/// picture, or a constant for the macOS this runs on — would change this function and nothing that
/// calls it; the corners that a rectangle leaves lit on the desktop are what that would take away.
enum WindowShape {
    /// `frame` is the window's rectangle in the view's own layer space.
    static func path(for frame: CGRect) -> CGPath {
        CGPath(rect: frame, transform: nil)
    }
}
