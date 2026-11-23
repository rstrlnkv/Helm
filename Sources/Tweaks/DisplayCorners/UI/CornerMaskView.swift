import AppKit
import AVFoundation
import QuartzCore
import HelmRuntime
import HelmUI
import Tweak_DisplayCorners_Engine

/// **One corner mask: the layers, and the morph between rounded and square.**
///
/// The view is not flipped: `CornerPath` and the engine's pointer correction both read y up. The tree is the
/// standalone app's: the view's backing layer holds `maskLayer`, which scales around the display's physical
/// corner and clips; it holds `shape`, the square minus the visible curve filled even-odd; the capture shield
/// is `shape`'s mask. A mask opens rounded (scale 1, opacity 1) and says nothing of whether it should be; the
/// engine calls `morph(toRounded:)` for that.
///
/// `apply` writes only what differs from the spec it drew last, in a transaction without implicit actions, so a
/// colour change leaves the path alone and a step of the radius does not touch the colour. A step during a
/// morph resizes the layers under the running animation, which is not measured.
///
/// The morph is the standalone app's, with `HelmMotion.cornerMorphCurve` for its ease in and out and
/// `HelmMotion.cornerMorphDuration` for its length. It runs only where `HelmMotion.moves` allows it and only
/// once the shield has drawn (or there is none); otherwise the mask takes its end state at once.
@MainActor final class CornerMaskView: NSView {
    private static let morphKey = "cornerMorph"

    private let maskLayer = CALayer()
    private let shape = CAShapeLayer()
    private let shield: AVSampleBufferDisplayLayer?
    private var drawn: MaskSpec?
    /// The refresh rate of the display, from the last spec; it only tunes the frame-rate range of a morph.
    private var maxFPS: Int

    init(spec: MaskSpec) {
        shield = CaptureShield.make(frame: .zero)
        maxFPS = spec.maxFPS
        super.init(frame: NSRect(origin: .zero, size: spec.frame.size))
        shape.fillRule = .evenOdd
        shape.mask = shield
        maskLayer.masksToBounds = true
        maskLayer.addSublayer(shape)
        wantsLayer = true
        layer?.addSublayer(maskLayer)
        apply(spec)
    }

    required init?(coder: NSCoder) { nil }

    var hasShield: Bool { shield != nil }

    func apply(_ spec: MaskSpec) {
        let old = drawn
        drawn = spec
        maxFPS = spec.maxFPS
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if old?.frame.width != spec.frame.width || old?.radius != spec.radius || old?.key.corner != spec.key.corner {
            let corner = spec.key.corner
            let size = spec.frame.width
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            // Scale the clipped mask around the physical corner of the display.
            maskLayer.bounds = bounds
            maskLayer.anchorPoint = CGPoint(x: corner.isRight ? 1 : 0, y: corner.isTop ? 1 : 0)
            maskLayer.position = CGPoint(x: corner.isRight ? size : 0, y: corner.isTop ? size : 0)
            shape.frame = bounds
            shape.path = CornerPath.mask(size: size, radius: spec.radius, corner: corner)
            shield?.frame = bounds
        }
        if old?.colour != spec.colour {
            switch spec.colour {
            case .black:
                shape.fillColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            case .rgb(let colour):
                shape.fillColor = CGColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
            }
        }
        if old?.backingScale != spec.backingScale {
            for layer in [self.layer, maskLayer, shape, shield] { layer?.contentsScale = spec.backingScale }
        }
    }

    func morph(toRounded rounded: Bool) {
        let target: CGFloat = rounded ? 1 : 0
        let running = maskLayer.animation(forKey: Self.morphKey) != nil
        // The same target while its animation runs: leave it be, a restart would only stretch it.
        if running && maskLayer.transform.m11 == target { return }
        let current = maskLayer.presentation()?.transform.m11 ?? maskLayer.transform.m11
        let distance = abs(target - current)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        maskLayer.removeAnimation(forKey: Self.morphKey)
        maskLayer.setValue(target, forKeyPath: "transform.scale")
        maskLayer.opacity = rounded ? 1 : 0
        guard distance > 0.001, HelmMotion.moves(reduceMotion: HelmMotion.reduceMotion),
              shield?.isReadyForDisplay ?? true else { return }
        let duration = HelmMotion.cornerMorphDuration(rounding: rounded, travel: Double(distance))
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = current
        scale.toValue = target
        scale.duration = duration
        scale.timingFunction = HelmMotion.cornerMorphCurve
        let group = CAAnimationGroup()
        group.duration = duration
        group.animations = [scale]
        if !rounded {
            // Keep the mask opaque while it shrinks, then hide the empty layer.
            let visibility = CABasicAnimation(keyPath: "opacity")
            visibility.fromValue = 1
            visibility.toValue = 1
            visibility.duration = duration
            group.animations = [scale, visibility]
        }
        let rate = Float(maxFPS.clamped(to: 30...120))
        group.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
        maskLayer.add(group, forKey: Self.morphKey)
    }

    /// What is on screen now, for the pointer correction. Nil while the shield has not drawn, and, for a mask
    /// with no shield, while its window is not visible; `ready` is true in every value returned.
    var presentation: MaskPresentation? {
        if let shield {
            guard shield.isReadyForDisplay else { return nil }
        } else {
            guard window?.isVisible == true else { return nil }
        }
        let displayed = maskLayer.presentation() ?? maskLayer
        return MaskPresentation(scale: displayed.transform.m11, opacity: displayed.opacity, ready: true)
    }

    /// Ends the animation and takes the shield off the shape's mask; the window calls it before it closes. The
    /// shield stays held by this view until the window drops it.
    func stop() {
        maskLayer.removeAnimation(forKey: Self.morphKey)
        shape.mask = nil
    }
}
