import Foundation
import HelmRuntime

/// The colour of the calibration masks, in sRGB, every component in 0...1.
public struct CalibrationColour: Equatable, Sendable {
    public static let `default` = CalibrationColour(clamping: 1, 0.32, 0.16)
    private static let fallback = [1.0, 0.32, 0.16]

    public let red: Double
    public let green: Double
    public let blue: Double

    /// Clamped on the way in (review finding 1: a wide-gamut pick came back outside 0...1, was refused on
    /// read, and every launch drew the default). A component that is NaN or infinite is no colour: that
    /// channel takes the default's, the other two keep theirs.
    public init(clamping red: Double, _ green: Double, _ blue: Double) {
        func channel(_ value: Double, _ index: Int) -> Double {
            value.clampedIfFinite(to: 0...1) ?? Self.fallback[index]
        }
        self.red = channel(red, 0)
        self.green = channel(green, 1)
        self.blue = channel(blue, 2)
    }
}
