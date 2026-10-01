import CoreGraphics
import Foundation

/// A display, as the system numbers it.
public struct DisplayID: Hashable, Sendable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
}

/// One display's frozen frame.
///
/// `@unchecked Sendable` because a `CGImage` is immutable and thread-safe and is
/// not declared so. `frame` is the display in CG-global points (see
/// `ScreenSpace`), `scale` the pixels to a point, and the image is at native
/// scale: a 5K display's frame is some sixty megabytes, which is why none of
/// this travels over the transport.
public struct FrozenDisplay: @unchecked Sendable {
    public let id: DisplayID
    public let frame: CGRect
    public let scale: CGFloat
    public let image: CGImage

    public init(id: DisplayID, frame: CGRect, scale: CGFloat, image: CGImage) {
        self.id = id
        self.frame = frame
        self.scale = scale
        self.image = image
    }
}

/// What the freeze found for one display: its frame, or the fact that it was
/// listed and then could not be captured — unplugged between the two calls.
public enum DisplayShot: @unchecked Sendable {
    case image(FrozenDisplay)
    case gone(DisplayID)
}

/// A window that was on screen when the freeze was taken, frame in CG-global points.
public struct FrozenWindow: Sendable, Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let layer: Int

    public init(id: UInt32, frame: CGRect, layer: Int) {
        self.id = id
        self.frame = frame
        self.layer = layer
    }
}

/// Every display and the window list, taken in one go.
///
/// **The window list is a reading.** It describes the desktop at the moment of
/// the freeze, and the act — a click on one of them — comes seconds later, so
/// `CaptureSession.window` asks again before it believes any entry.
public struct Freeze: @unchecked Sendable {
    public let displays: [DisplayShot]
    /// Front to back.
    public let windows: [FrozenWindow]

    public init(displays: [DisplayShot], windows: [FrozenWindow]) {
        self.displays = displays
        self.windows = windows
    }

    /// The displays that came back with a picture, main first.
    public var frames: [FrozenDisplay] {
        displays.compactMap { if case .image(let frame) = $0 { frame } else { nil } }
    }
}
