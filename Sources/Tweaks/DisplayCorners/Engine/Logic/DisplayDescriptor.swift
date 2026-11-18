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

    init(id: UInt32, frame: CGRect, quartzBounds: CGRect, backingScale: CGFloat, pixelsPerPoint: CGFloat,
                isBuiltIn: Bool, isMirrored: Bool, maxFPS: Int) {
        self.id = id
        self.frame = frame
        self.quartzBounds = quartzBounds
        self.backingScale = backingScale
        self.pixelsPerPoint = pixelsPerPoint
        self.isBuiltIn = isBuiltIn
        self.isMirrored = isMirrored
        self.maxFPS = maxFPS
    }
}

struct CornerSettings: Equatable, Sendable {
    var builtIn: Bool
    var external: Bool
    var radiusPixels: Double

    init(builtIn: Bool, external: Bool, radiusPixels: Double) {
        self.builtIn = builtIn
        self.external = external
        self.radiusPixels = radiusPixels
    }
}
