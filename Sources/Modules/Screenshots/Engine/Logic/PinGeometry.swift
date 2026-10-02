import CoreGraphics
import Foundation
import HelmRuntime

/// Where a pin opens, how far it scales, how opaque it gets and where it goes when its display leaves.
///
/// Pure arithmetic over **AppKit-global** points (the space a window's frame is in), so each
/// edge of a display and each display above or left of the primary is a case a test can ask.
/// The scale of a pin is its width over the selection's own width in points (`native`), so
/// "1:1" is 1 and the limits are limits on that one number.
public enum PinGeometry {

    /// How many pins are open at once. Each holds a full-resolution picture, and the plate that
    /// says so at the limit has no number in it, so this is not in any language.
    public static let limit = 8

    /// The shortest side a pin can be scaled down to, in points: small enough to park, big enough to
    /// take hold of. A selection already smaller than this keeps its own size as its floor.
    public static let minimumSide: CGFloat = 16

    /// The lowest opacity: a pin that cannot be seen cannot be found to be closed.
    public static let minimumOpacity: CGFloat = 0.1

    /// Scroll to scale: a trackpad reports pixels in the hundreds, a wheel notches in ones.
    private static func rate(precise: Bool) -> CGFloat { precise ? 0.005 : 0.05 }
    private static func opacityRate(precise: Bool) -> CGFloat { precise ? 0.002 : 0.05 }

    /// The frame a pin opens at: the selection's own pixels — cut as `CaptureSession.annotated`
    /// cuts them, rounded outward — divided by the display's scale, so the pin is the selection
    /// 1:1 and a Retina picture is shown at its own resolution. `display` is the display's frame
    /// in CG-global points, `local` the selection in that display's top-left points.
    public static func opening(local: CGRect, scale: CGFloat, imageWidth: Int, imageHeight: Int,
                               display: CGRect, primaryHeight: CGFloat) -> CGRect {
        let points = ScreenSpace.pixels(ofLocal: local, scale: scale, imageWidth: imageWidth, imageHeight: imageHeight)
            .map { CGRect(x: $0.minX / scale, y: $0.minY / scale, width: $0.width / scale, height: $0.height / scale) }
            ?? local
        return ScreenSpace.appKitRect(fromCG: ScreenSpace.global(points, in: display), primaryHeight: primaryHeight)
    }

    /// The scales a pin of this native size may have on `display`. The ceiling is raised to the
    /// floor first, so a display smaller than the floor leaves one scale and not a trap.
    private static func limits(native: CGSize, display: CGRect) -> ClosedRange<CGFloat> {
        let short = min(native.width, native.height)
        let floor = min(minimumSide, short) / short
        let ceiling = min(display.width / native.width, display.height / native.height)
        return floor...max(floor, ceiling)
    }

    private static func usable(_ native: CGSize) -> Bool {
        native.width.isFinite && native.height.isFinite && native.width > 0 && native.height > 0
    }

    /// `frame` scaled by a scroll of `delta` (positive enlarges) about the point `about`, which stays
    /// where it is on the picture even when a bound is reached. `scale` is the unrounded scale a caller
    /// that snaps its frame keeps, else the frame's own. A pin already past a bound of this display
    /// (carried from a bigger one) keeps its own size as that bound, so a scroll up never shrinks it
    /// and a scroll down never enlarges it. Nil when the delta or the point is
    /// not a number: no change, and the caller keeps the frame it had.
    public static func scaled(frame: CGRect, native: CGSize, delta: CGFloat, precise: Bool,
                              about: CGPoint, display: CGRect, scale: CGFloat? = nil) -> CGRect? {
        guard delta.isFinite, about.x.isFinite, about.y.isFinite, usable(native),
              frame.width.isFinite, frame.width > 0 else { return nil }
        let now = scale ?? frame.width / native.width
        guard now.isFinite, now > 0 else { return nil }
        let bounds = limits(native: native, display: display)
        let reach = min(bounds.lowerBound, now)...max(bounds.upperBound, now)
        let next = (now * exp(delta * rate(precise: precise))).clamped(to: reach)
        let ratio = next / now
        let size = CGSize(width: native.width * next, height: native.height * next)
        return CGRect(x: about.x - (about.x - frame.minX) * ratio, y: about.y - (about.y - frame.minY) * ratio,
                      width: size.width, height: size.height)
    }

    /// The opacity after a scroll of `delta` (positive raises it), between the floor and 1. Nil for a delta that is not a number.
    public static func opacity(_ current: CGFloat, delta: CGFloat, precise: Bool) -> CGFloat? {
        guard current.isFinite else { return nil }
        return (current + delta * opacityRate(precise: precise)).clampedIfFinite(to: minimumOpacity...1)
    }

    /// Where a pin goes when a display is unplugged or rearranged. Wholly on one screen, it stays.
    /// Otherwise the screen holding most of it takes it (the first of the list when it is on none),
    /// shrunk to fit keeping its proportions and pushed inside. No screens: unchanged, nothing made up.
    public static func rehome(frame: CGRect, native: CGSize,
                              screens: [(id: DisplayID, frame: CGRect)]) -> CGRect {
        guard let first = screens.first, usable(native), frame.width > 0 else { return frame }
        if screens.contains(where: { $0.frame.contains(frame) }) { return frame }
        let screen = WindowPick.home(of: frame, among: screens)
            .flatMap { home in screens.first { $0.id == home.id } } ?? first
        let fitted = (frame.width / native.width).clamped(to: limits(native: native, display: screen.frame))
        let size = CGSize(width: native.width * fitted, height: native.height * fitted)
        let x = frame.minX.clamped(to: screen.frame.minX...max(screen.frame.minX, screen.frame.maxX - size.width))
        let y = frame.minY.clamped(to: screen.frame.minY...max(screen.frame.minY, screen.frame.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
