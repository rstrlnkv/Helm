import AppKit
import QuartzCore
import HelmUI

/// The white that says a shot was taken: 55 % over the selection's or the window's shape, fading out along
/// `HelmMotion.interfaceCurve` for `HelmMotion.interfaceDuration`.
///
/// **Decoration only.** Whether the overlay waits for it is the overlay's decision (`CaptureOverlay.close(after:)`
/// closes on a timer of the same length and not on this animation's completion, which a layer that is not in a
/// window never reports), and under Reduce Motion the overlay never calls `play`. The picture was taken from the
/// freeze before this was drawn, and a window's live picture is of that window alone, so the flash is in neither.
final class FlashLayer: CAShapeLayer {
    /// How white it is at its brightest.
    static let peak: Float = 0.55

    /// The rectangle being lit, in the layer's own space; nil while none is.
    private(set) var lit: CGRect?

    override init() {
        super.init()
        fillColor = NSColor.white.cgColor
        strokeColor = nil
        opacity = 0
    }
    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func play(over frame: CGRect, shape: CGPath) {
        lit = frame
        path = shape
        opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Self.peak
        fade.toValue = 0
        fade.duration = HelmMotion.interfaceDuration
        fade.timingFunction = HelmMotion.interfaceCurve
        add(fade, forKey: "flash")
    }
}
