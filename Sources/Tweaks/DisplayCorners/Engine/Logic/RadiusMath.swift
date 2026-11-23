import CoreGraphics
import Foundation
import HelmRuntime

/// One mode of a display, as far as the pixels per point need it.
struct DisplayModeInfo: Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let isNative: Bool
}

/// The display's physical pixels per point. Review finding 6: the standalone app took the first mode
/// carrying the native flag, whatever its shape; a scaled mode of another aspect, or several native
/// modes, gave a wrong answer.
enum PixelsPerPoint {
    static func resolve(modes: [DisplayModeInfo], pointSize: CGSize, backing: CGFloat) -> CGFloat {
        let fallback = backing.isFinite && backing > 0 ? backing : 1
        let longEdge = max(pointSize.width, pointSize.height)
        guard pointSize.width.isFinite, pointSize.height.isFinite, pointSize.width > 0, pointSize.height > 0
        else { return fallback }
        let aspect = pointSize.width / pointSize.height
        let matching = modes.filter {
            $0.isNative && $0.pixelWidth > 0 && $0.pixelHeight > 0
                && abs(Double($0.pixelWidth) / Double($0.pixelHeight) - Double(aspect)) <= 0.01
        }
        guard let largest = matching.max(by: { max($0.pixelWidth, $0.pixelHeight) < max($1.pixelWidth, $1.pixelHeight) })
        else { return fallback }
        return CGFloat(max(largest.pixelWidth, largest.pixelHeight)) / longEdge
    }
}

/// Which display's scale a radius is stored at. Review finding 2: with the lid closed the standalone app
/// used an external display's scale, so a step stored a value that drew the built-in corners at another
/// physical size once the lid opened.
enum RadiusScale {
    /// The live built-in display's, else the one remembered from when it was seen, else the main
    /// display's. A scale that is not finite or not positive is not a scale: the next one answers, and 1
    /// is the last.
    static func reference(builtInNow: CGFloat?, remembered: CGFloat?, main: CGFloat?) -> CGFloat {
        [builtInNow, remembered, main].lazy.compactMap { $0 }.first { $0.isFinite && $0 > 0 } ?? 1
    }
}

/// The radius in pixels of the built-in display, its bounds, steps and presets.
enum RadiusMath {
    static let bounds = 0.5...128.0
    static let step = 0.5
    /// Presets, in points of the built-in display.
    static let presetPoints = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32]
    static let defaultPoints = 14.0

    /// A stored or computed radius is NaN or infinite → the default, here and at every site below: 14 pt
    /// at that scale, clamped to `bounds`. A scale that is not finite or not positive is 1 (14 px).
    static func defaultPixels(scale: CGFloat) -> Double {
        let scale = scale.isFinite && scale > 0 ? min(Double(scale), bounds.upperBound) : 1
        return min(max(defaultPoints * scale, bounds.lowerBound), bounds.upperBound)
    }

    static func pixels(stored: Double?, scale: CGFloat) -> Double {
        stored?.clampedIfFinite(to: bounds) ?? defaultPixels(scale: scale)
    }

    /// One step up or down (`direction` is its sign), kept on the half-pixel grid.
    static func stepped(_ pixels: Double, direction: Int, scale: CGFloat) -> Double {
        let moved = pixels + Double(direction.signum()) * step
        return ((moved / step).rounded() * step).clampedIfFinite(to: bounds) ?? defaultPixels(scale: scale)
    }

    static func preset(points: Double, scale: CGFloat) -> Double {
        (points * Double(scale)).clampedIfFinite(to: bounds) ?? defaultPixels(scale: scale)
    }

    /// The radius in points on a display of that pixels per point; 0 (no mask) when the scale is no scale.
    /// A radius that is not a number is the default radius (14 pt × scale, clamped to 0.5...128 px) at that scale.
    static func points(pixels: Double, pixelsPerPoint: CGFloat) -> CGFloat {
        guard pixelsPerPoint.isFinite, pixelsPerPoint > 0 else { return 0 }
        return CGFloat(pixels.clampedIfFinite(to: bounds) ?? defaultPixels(scale: pixelsPerPoint)) / pixelsPerPoint
    }
}
