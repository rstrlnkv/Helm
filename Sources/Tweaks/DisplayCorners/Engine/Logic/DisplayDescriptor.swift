import CoreGraphics

/// A display as the layout decision sees it: values the port read, nothing live.
struct DisplayDescriptor: Equatable, Sendable {
    let id: UInt32
    /// AppKit's frame (bottom-left origin).
    let frame: CGRect
    /// Quartz's bounds (top-left origin).
    let quartzBounds: CGRect
    let backingScale: CGFloat
    let pixelsPerPoint: CGFloat
    let isBuiltIn: Bool
    let isMirrored: Bool
    let maxFPS: Int
}

struct CornerSettings: Equatable, Sendable {
    var builtIn: Bool
    var external: Bool
    var radiusPixels: Double
}
