import CoreGraphics
import Foundation

/// **The boundary between Display Corners' engine and its UI, in plain values.**
///
/// The engine decides where masks stand and whether they are rounded and publishes a `CornerState`;
/// the UI draws the masks and answers what is on screen. Nothing here names AppKit, SwiftUI or
/// Combine, so the engine can be built and tested without a display and the UI can be built without
/// the engine's ports. Every value is `Equatable`, so the engine refuses a payload equal to the last.
public enum CornerPosition: Int, CaseIterable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight

    public var isRight: Bool { self == .bottomRight || self == .topRight }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

/// One mask: a display and a corner of it. The UI keeps its windows by this key, so a change of
/// radius resizes a window instead of ordering it out and in (review finding 3).
public struct MaskKey: Hashable, Sendable {
    public let display: UInt32
    public let corner: CornerPosition

    public init(display: UInt32, corner: CornerPosition) {
        self.display = display
        self.corner = corner
    }
}

public enum MaskColour: Equatable, Sendable {
    case black
    case rgb(CalibrationColour)
}

/// What one mask window must be. `frame` is AppKit's (bottom-left origin, global), `radius` in points.
public struct MaskSpec: Equatable, Sendable {
    public let key: MaskKey
    public let frame: CGRect
    public let radius: CGFloat
    public let colour: MaskColour
    /// False for a coloured calibration mask, and for a corner another display touches (review finding 5):
    /// the mask is still drawn, the pointer is not held off it.
    public let constrainsCursor: Bool
    /// The top masks stand over the menu bar.
    public let topLevel: Bool
    public let backingScale: CGFloat
    /// Part of the spec, not read once at build time (review finding 7); it only retunes the sampler.
    public let maxFPS: Int

    public init(key: MaskKey, frame: CGRect, radius: CGFloat, colour: MaskColour, constrainsCursor: Bool,
                topLevel: Bool, backingScale: CGFloat, maxFPS: Int) {
        self.key = key
        self.frame = frame
        self.radius = radius
        self.colour = colour
        self.constrainsCursor = constrainsCursor
        self.topLevel = topLevel
        self.backingScale = backingScale
        self.maxFPS = maxFPS
    }
}

/// What the UI reads off a mask window for the pointer correction: the scale of its morph, its opacity,
/// and whether its capture shield has drawn.
public struct MaskPresentation: Equatable, Sendable {
    public let scale: CGFloat
    public let opacity: Float
    public let ready: Bool

    public init(scale: CGFloat, opacity: Float, ready: Bool) {
        self.scale = scale
        self.opacity = opacity
        self.ready = ready
    }
}

public enum PointerMode: Equatable, Sendable {
    case off, tap, monitorsOnly, unavailable
}

public struct CornerState: Equatable, Sendable {
    public var masks: [MaskSpec]
    /// Per display: whether its masks are at rest and so rounded.
    public var rounded: [UInt32: Bool]
    public var radiusPixels: Double
    public var referenceScale: CGFloat
    public var pointer: PointerMode
    public var calibrating: Bool
    /// The two switches, and the calibration colour while one is previewed: what the card shows, declared
    /// here once beside the rest of what the engine says.
    public var builtIn: Bool
    public var external: Bool
    public var calibrationColour: CalibrationColour?
    /// The first of `presetPoints` whose radius at `referenceScale` is the current one, within a thousandth of a
    /// pixel; nil when none is. A fact of the engine, which owns the scale: at a scale of 5, 28 pt and 32 pt both
    /// clamp to 128 px and the first wins.
    public var selectedPreset: Int?

    /// The presets the card offers, in points of the built-in display.
    public static let presetPoints = RadiusMath.presetPoints
    /// The radius the engine accepts, in pixels.
    public static let radiusBounds = RadiusMath.bounds

    public init(masks: [MaskSpec] = [], rounded: [UInt32: Bool] = [:], radiusPixels: Double = 0,
                referenceScale: CGFloat = 1, pointer: PointerMode = .off, calibrating: Bool = false,
                builtIn: Bool = false, external: Bool = false, calibrationColour: CalibrationColour? = nil,
                selectedPreset: Int? = nil) {
        self.masks = masks
        self.rounded = rounded
        self.radiusPixels = radiusPixels
        self.referenceScale = referenceScale
        self.pointer = pointer
        self.calibrating = calibrating
        self.builtIn = builtIn
        self.external = external
        self.calibrationColour = calibrationColour
        self.selectedPreset = selectedPreset
    }
}
